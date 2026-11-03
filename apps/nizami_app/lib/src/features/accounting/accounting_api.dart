import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../auth/json_transport.dart';
import '../invoices/invoice_pdf_service.dart';
import '../products/unit_conversion_math.dart';
import 'minor_allocation.dart';
import 'settlement_idempotency_store.dart';

/// Explicit opt-in only. Never auto-post a draft when the user types or saves locally.
class AccountingApi {
  AccountingApi({required this.token, JsonTransport? transport, String? baseUrl})
    : _transport = transport ?? createJsonTransport(),
      _baseUri = Uri.parse(
        '${(baseUrl ?? const String.fromEnvironment('NINESOFT_API_BASE_URL', defaultValue: 'https://ninesoft.qodynex.tech/api/v1')).replaceFirst(RegExp(r'/+$'), '')}/',
      );

  static const enabled = bool.fromEnvironment(
    'NINESOFT_ACCOUNTING_ENABLED',
    defaultValue: true,
  );
  final String token;
  final JsonTransport _transport;
  final Uri _baseUri;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  static String? _cachedDeviceId;
  static Future<String>? _deviceIdLoad;

  Future<String> _deviceId() async {
    final cached = _cachedDeviceId;
    if (cached != null && cached.isNotEmpty) return cached;
    final load = _deviceIdLoad ??= _loadDeviceId();
    try {
      final value = await load;
      _cachedDeviceId = value;
      return value;
    } finally {
      if (identical(_deviceIdLoad, load)) _deviceIdLoad = null;
    }
  }

  static Future<String> _loadDeviceId() async {
    final preferences = await SharedPreferences.getInstance();
    var deviceId = preferences.getString('ninesoft.accounting.device_uuid.v1');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await preferences.setString(
        'ninesoft.accounting.device_uuid.v1',
        deviceId,
      );
    }
    return deviceId;
  }

  Future<Map<String, dynamic>> prepareInvoiceRequest({
    required String branchId,
    required InvoiceDocument invoice,
    int restoreGeneration = 0,
  }) async {
    if (invoice.lines.isEmpty || invoice.localOperationId.isEmpty) {
      throw const AccountingApiError(
        'رقم عملية الفاتورة أو الأصناف غير مكتمل.',
      );
    }
    final items = <Map<String, Object?>>[];
    final grossMinor = <int>[];
    for (final line in invoice.lines) {
      if (line.pendingCatalogSync) {
        throw const AccountingApiError(
          'PENDING_CATALOG_PRODUCT_REQUIRES_CANONICAL_ID',
        );
      }
      if (!line.unitPrice.isFinite ||
          line.unitPrice < 0 ||
          !line.quantity.isFinite ||
          line.quantity <= 0) {
        throw const AccountingApiError('بيانات الأصناف غير صالحة للترحيل.');
      }
      final quantityMilli =
          line.exactQuantityMilli ?? (line.quantity * 1000).round();
      final unitPriceMinor = (line.unitPrice * 100).round();
      final numerator = line.priceNumeratorMinor;
      final denominator = line.priceDenominator;
      if ((numerator == null) != (denominator == null)) {
        throw const AccountingApiError('سعر الوحدة الدقيق غير مكتمل.');
      }
      if (line.priceOverridden &&
          (line.saleOptionId.isEmpty ||
              numerator != unitPriceMinor ||
              denominator != 1)) {
        throw const AccountingApiError('MANUAL_PRICE_INTENT_MISMATCH');
      }
      final item = <String, Object?>{
        'name': line.name,
        if (line.productId.isNotEmpty) 'product_id': line.productId,
        if (line.saleOptionId.isNotEmpty) 'sale_option_id': line.saleOptionId,
        'quantity_milli': quantityMilli,
        'unit_price_minor': unitPriceMinor,
        'price_numerator_minor': ?numerator,
        'price_denominator': ?denominator,
        if (line.priceOverridden) 'price_overridden': true,
        'kind': line.productId.isEmpty ? 'service' : 'stock',
      };
      items.add(item);
      grossMinor.add(
        numerator == null
            ? MinorAllocation.lineGross(quantityMilli, unitPriceMinor)
            : ExactUnitPrice.grossMinor(
                quantityMilli: quantityMilli,
                priceNumeratorMinor: numerator,
                priceDenominator: denominator!,
              ),
      );
    }
    if (!invoice.discountAmount.isFinite || invoice.discountAmount < 0) {
      throw const AccountingApiError('خصم الفاتورة غير صالح.');
    }
    try {
      final discounts = MinorAllocation.discount(
        grossMinor
            .asMap()
            .entries
            .map(
              (entry) =>
                  entry.value - invoice.lines[entry.key].lineDiscountMinor,
            )
            .toList(),
        (invoice.discountAmount * 100).round(),
      );
      for (var index = 0; index < items.length; index++) {
        items[index]['discount_minor'] =
            discounts[index] + invoice.lines[index].lineDiscountMinor;
      }
    } on ArgumentError {
      throw const AccountingApiError(
        'الخصم يتجاوز إجمالي الفاتورة أو توجد كمية غير صالحة.',
      );
    }
    return <String, dynamic>{
      'branch_id': branchId,
      'device_id': await _deviceId(),
      'local_operation_id': invoice.localOperationId,
      'restore_generation': restoreGeneration,
      'operation_created_at': invoice.createdAt.toUtc().toIso8601String(),
      if (invoice.replacementInvoiceId.isNotEmpty)
        'replacement_invoice_id': invoice.replacementInvoiceId,
      'customer_name': invoice.customerName == 'عميل نقدي'
          ? ''
          : invoice.customerName,
      'customer_phone': invoice.customerPhone,
      if (invoice.customerId.isNotEmpty) 'contact_id': invoice.customerId,
      'paid_minor': (invoice.paidAmount * 100).round(),
      'payment_mode': invoice.paymentMode,
      'amount_tendered_minor': (invoice.amountTendered * 100).round(),
      if (invoice.paymentChannel.isNotEmpty)
        'payment_channel': invoice.paymentChannel,
      if (invoice.paymentAccountCode.isNotEmpty)
        'payment_account_code': invoice.paymentAccountCode,
      if (invoice.isCredit)
        'due_at': invoice.createdAt
            .add(const Duration(hours: 48))
            .toUtc()
            .toIso8601String(),
      'notes': invoice.notes,
      'items': items,
    };
  }

  Future<Map<String, dynamic>> postInvoiceRequest(
    Map<String, dynamic> request,
  ) async {
    if ((request['local_operation_id']?.toString() ?? '').isEmpty ||
        (request['device_id']?.toString() ?? '').isEmpty ||
        (request['operation_created_at']?.toString() ?? '').isEmpty ||
        request['items'] is! List ||
        (request['items'] as List).isEmpty) {
      throw const AccountingApiError('بيانات عملية البيع المحفوظة غير مكتملة.');
    }
    final replacementId = request['replacement_invoice_id']?.toString() ?? '';
    final response = await _transport.request(
      _baseUri.resolve(
        replacementId.isEmpty
            ? 'accounting/invoices'
            : 'accounting/invoices/$replacementId/replace',
      ),
      method: 'POST',
      headers: _headers,
      body: jsonEncode(request),
    );
    final value = _decodeMap(response, 'تعذر ترحيل فاتورة البيع.');
    final invoice = value['invoice'];
    if (invoice is! Map ||
        (invoice['id']?.toString() ?? '').isEmpty ||
        (invoice['number']?.toString() ?? '').isEmpty) {
      throw const AccountingApiError(
        'لا تحتوي الاستجابة على معرف ورقم الفاتورة المرحّلة.',
      );
    }
    return Map<String, dynamic>.from(invoice);
  }

  Future<Map<String, dynamic>> postInvoice({
    required String branchId,
    required InvoiceDocument invoice,
    int restoreGeneration = 0,
  }) async => postInvoiceRequest(
    await prepareInvoiceRequest(
      branchId: branchId,
      invoice: invoice,
      restoreGeneration: restoreGeneration,
    ),
  );

  Future<List<Map<String, dynamic>>> listInvoices({
    required String branchId,
  }) async {
    final result = <Map<String, dynamic>>[];
    String? snapshotAt;
    String? afterOccurredAt;
    String? afterId;
    for (var page = 1; page <= 1000; page++) {
      final query = <String, String>{
        'branch_id': branchId,
        'snapshot': '1',
        'per_page': '200',
        'snapshot_at': ?snapshotAt,
        'after_occurred_at': ?afterOccurredAt,
        'after_id': ?afterId,
      };
      final response = await _transport.request(
        _baseUri.resolve(
          'accounting/invoices?${Uri(queryParameters: query).query}',
        ),
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AccountingApiError(
          decoded is Map && decoded['message'] != null
              ? decoded['message'].toString()
              : 'تعذر جلب الفواتير من الخادم.',
        );
      }
      final data = decoded is Map ? decoded['data'] : null;
      if (data is! List) {
        throw const AccountingApiError('رد قائمة الفواتير غير صالح.');
      }
      result.addAll(
        data.whereType<Map>().map((row) => Map<String, dynamic>.from(row)),
      );
      if (decoded is Map && decoded.containsKey('has_more')) {
        snapshotAt ??= decoded['snapshot_at']?.toString();
        if (decoded['has_more'] != true) return result;
        final nextOccurredAt =
            decoded['next_after_occurred_at']?.toString() ?? '';
        final nextId = decoded['next_after_id']?.toString() ?? '';
        if (nextOccurredAt.isEmpty ||
            nextId.isEmpty ||
            (nextOccurredAt == afterOccurredAt && nextId == afterId)) {
          throw const AccountingApiError('مؤشر لقطة الفواتير لم يتقدم.');
        }
        afterOccurredAt = nextOccurredAt;
        afterId = nextId;
      } else {
        final last = (decoded['last_page'] as num?)?.toInt() ?? page;
        if (page >= last) return result;
      }
      if (page == 1000) {
        throw const AccountingApiError(
          'عدد الفواتير يتجاوز حد الاستعادة الحالي.',
        );
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> invoice(String id) async {
    final response = await _transport.request(
      _baseUri.resolve('accounting/invoices/$id'),
      method: 'GET',
      headers: _headers,
    );
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded is! Map) {
      throw AccountingApiError(
        decoded is Map && decoded['message'] != null
            ? decoded['message'].toString()
            : 'تعذر جلب الفاتورة من الخادم.',
      );
    }
    final invoice = Map<String, dynamic>.from(decoded['invoice'] as Map);
    invoice['items'] = decoded['items'] as List? ?? const [];
    return invoice;
  }

  Future<void> voidInvoice({
    required String invoiceId,
    required String reason,
  }) async {
    final response = await _transport.request(
      _baseUri.resolve('accounting/invoices/$invoiceId'),
      method: 'DELETE',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'reason': reason}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {}
      throw AccountingApiError(
        decoded is Map && decoded['message'] != null
            ? decoded['message'].toString()
            : 'تعذر حذف الفاتورة على الخادم.',
      );
    }
  }

  Future<String> storeReceipt({
    required String invoiceId,
    required double amount,
    required String currency,
    required String idempotencyKey,
    String channel = 'cash',
    String accountCode = '',
    required String reason,
  }) async {
    if (idempotencyKey.trim().isEmpty) {
      throw const AccountingApiError(
        'معرّف إعادة المحاولة لسند القبض غير مكتمل.',
      );
    }
    final response = await _transport.request(
      _baseUri.resolve('accounting/invoices/$invoiceId/receipts'),
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'amount_minor': (amount * 100).round(),
        'currency': currency,
        'idempotency_key': idempotencyKey.trim(),
        'channel': channel,
        if (accountCode.isNotEmpty) 'account_code': accountCode,
        'reason': canonicalSettlementReason(
          SettlementOperationKind.customerReceipt,
          reason,
        ),
      }),
    );
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AccountingApiError(
        decoded is Map && decoded['message'] != null
            ? decoded['message'].toString()
            : 'تعذر ترحيل سند القبض إلى حساب العميل.',
      );
    }
    final receiptId = decoded is Map
        ? decoded['receipt_id']?.toString().trim() ?? ''
        : '';
    if (receiptId.isEmpty) {
      throw const AccountingApiError(
        'استجابة سند القبض لا تحتوي المعرّف المحاسبي.',
      );
    }
    return receiptId;
  }

  Future<void> voidReceipt(String receiptId, {required String reason}) async {
    final response = await _transport.request(
      _baseUri.resolve('accounting/receipts/$receiptId/void'),
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'reason': reason.trim().length >= 8
            ? reason.trim()
            : 'إلغاء سند القبض من قائمة المستندات',
      }),
    );
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AccountingApiError(
        decoded is Map && decoded['message'] != null
            ? decoded['message'].toString()
            : 'تعذر حذف سند القبض على الخادم.',
      );
    }
  }

  /// Builds the complete purchase request ONCE, before durable local storage.
  /// The same body (including device ID, dates and operation ID) must be used
  /// for all retries; regenerating it breaks server idempotency fingerprints.
  Future<Map<String, dynamic>> preparePurchaseRequest({
    required String branchId,
    required String supplierName,
    required String supplierPhone,
    String contactId = '',
    required String paymentMode,
    String paymentChannel = 'cash',
    String paymentAccountCode = '',
    required List<Map<String, Object?>> items,
    String notes = '',
    required int restoreGeneration,
    String? operationId,
    DateTime? createdAt,
  }) async {
    if (items.isEmpty) {
      throw const AccountingApiError('أضف صنفًا واحدًا على الأقل.');
    }
    if (supplierName.trim().isEmpty) {
      throw const AccountingApiError('حدد اسم المورد قبل الحفظ.');
    }
    if (!const {'cash', 'credit'}.contains(paymentMode)) {
      throw const AccountingApiError('طريقة سداد الشراء غير صالحة.');
    }
    final operationTime = (createdAt ?? DateTime.now()).toUtc();
    return <String, dynamic>{
      'branch_id': branchId,
      'device_id': await _deviceId(),
      'local_operation_id': operationId ?? const Uuid().v4(),
      'restore_generation': restoreGeneration,
      'operation_created_at': operationTime.toIso8601String(),
      'supplier_name': supplierName.trim(),
      'supplier_phone': supplierPhone.trim(),
      if (contactId.trim().isNotEmpty) 'contact_id': contactId.trim(),
      'payment_mode': paymentMode,
      if (paymentMode == 'cash') 'payment_channel': paymentChannel,
      if (paymentMode == 'cash' && paymentAccountCode.isNotEmpty)
        'payment_account_code': paymentAccountCode,
      if (paymentMode == 'cash')
        'paid_minor': items.fold<int>(
          0,
          (sum, item) =>
              sum +
              (((item['quantity_milli'] as int) *
                          (item['unit_price_minor'] as int) +
                      500) ~/
                  1000),
        ),
      if (paymentMode == 'credit')
        'due_at': operationTime
            .add(const Duration(hours: 48))
            .toIso8601String(),
      'notes': notes,
      'items': items,
    };
  }

  /// Posts the ORIGINAL persisted request. Never alters its timestamps,
  /// IDs, money or items on retry after an ambiguous network failure.
  Future<Map<String, dynamic>> postPurchaseRequest(
    Map<String, dynamic> request,
  ) => postPurchaseRequestBody(jsonEncode(request));

  /// Sends an already-persisted request without re-encoding its bytes.
  Future<Map<String, dynamic>> postPurchaseRequestBody(
    String requestBody,
  ) async {
    dynamic decoded;
    try {
      decoded = jsonDecode(requestBody);
    } catch (_) {
      throw const AccountingApiError('Invalid persisted purchase request.');
    }
    if (decoded is! Map) {
      throw const AccountingApiError('Invalid persisted purchase request.');
    }
    final request = Map<String, dynamic>.from(decoded);
    if ((request['local_operation_id']?.toString() ?? '').isEmpty ||
        (request['device_id']?.toString() ?? '').isEmpty ||
        (request['operation_created_at']?.toString() ?? '').isEmpty ||
        request['items'] is! List ||
        (request['items'] as List).isEmpty) {
      throw const AccountingApiError('بيانات عملية الشراء غير مكتملة.');
    }
    final response = await _transport.request(
      _baseUri.resolve('accounting/purchases'),
      method: 'POST',
      headers: _headers,
      body: requestBody,
    );
    final value = _decodeMap(response, 'تعذر ترحيل فاتورة الشراء.');
    final invoice = value['invoice'];
    if (invoice is! Map || (invoice['id']?.toString() ?? '').isEmpty) {
      throw const AccountingApiError('استجابة فاتورة الشراء غير مكتملة.');
    }
    return Map<String, dynamic>.from(invoice);
  }

  /// Compatibility path for callers not yet using the persistent outbox.
  /// Prefer preparePurchaseRequest + PurchaseOutbox for any new workflow.
  Future<Map<String, dynamic>> postPurchase({
    required String branchId,
    required String supplierName,
    required String supplierPhone,
    String contactId = '',
    required String paymentMode,
    String paymentChannel = 'cash',
    String paymentAccountCode = '',
    required List<Map<String, Object?>> items,
    String notes = '',
    required int restoreGeneration,
    String? operationId,
  }) async => postPurchaseRequest(
    await preparePurchaseRequest(
      branchId: branchId,
      supplierName: supplierName,
      supplierPhone: supplierPhone,
      contactId: contactId,
      paymentMode: paymentMode,
      paymentChannel: paymentChannel,
      paymentAccountCode: paymentAccountCode,
      items: items,
      notes: notes,
      restoreGeneration: restoreGeneration,
      operationId: operationId,
    ),
  );

  Future<List<Map<String, dynamic>>> listPurchases({
    required String branchId,
  }) => _listData('accounting/purchases', branchId, 'تعذر جلب فواتير الشراء.');

  Future<void> voidPurchase({
    required String invoiceId,
    required String reason,
  }) async {
    final response = await _transport.request(
      _baseUri.resolve('accounting/purchases/$invoiceId'),
      method: 'DELETE',
      headers: _headers,
      body: jsonEncode({'reason': reason}),
    );
    _decodeMap(response, 'تعذر حذف فاتورة الشراء.');
  }

  Future<Map<String, dynamic>> replacePurchase({
    required String invoiceId,
    required Map<String, dynamic> request,
  }) async {
    final response = await _transport.request(
      _baseUri.resolve('accounting/purchases/$invoiceId'),
      method: 'PUT',
      headers: _headers,
      body: jsonEncode(request),
    );
    final value = _decodeMap(response, 'تعذر تعديل فاتورة الشراء.');
    final invoice = value['invoice'];
    if (invoice is! Map || (invoice['id']?.toString() ?? '').isEmpty) {
      throw const AccountingApiError('استجابة تعديل فاتورة الشراء غير مكتملة.');
    }
    return Map<String, dynamic>.from(invoice);
  }

  Future<String> storeSupplierPayment({
    required String invoiceId,
    required double amount,
    required String currency,
    required String idempotencyKey,
    required String channel,
    String accountCode = '',
    required String reason,
  }) async {
    if (idempotencyKey.trim().isEmpty) {
      throw const AccountingApiError(
        'معرّف إعادة المحاولة لسند الصرف غير مكتمل.',
      );
    }
    final response = await _transport.request(
      _baseUri.resolve('accounting/purchases/$invoiceId/payments'),
      method: 'POST',
      headers: _headers,
      body: jsonEncode({
        'amount_minor': (amount * 100).round(),
        'currency': currency,
        'idempotency_key': idempotencyKey.trim(),
        'channel': channel,
        if (accountCode.isNotEmpty) 'account_code': accountCode,
        'reason': canonicalSettlementReason(
          SettlementOperationKind.supplierPayment,
          reason,
        ),
      }),
    );
    final value = _decodeMap(response, 'تعذر ترحيل سند الصرف.');
    final paymentId = value['payment_id']?.toString().trim() ?? '';
    if (paymentId.isEmpty) {
      throw const AccountingApiError(
        'استجابة سند الصرف لا تحتوي المعرّف المحاسبي.',
      );
    }
    return paymentId;
  }

  Future<void> voidSupplierPayment(
    String paymentId, {
    required String reason,
  }) async {
    final response = await _transport.request(
      _baseUri.resolve('accounting/payments/$paymentId/void'),
      method: 'POST',
      headers: _headers,
      body: jsonEncode({'reason': reason}),
    );
    _decodeMap(response, 'تعذر حذف سند الصرف.');
  }

  Future<String> storeDirectVoucher({
    required bool receipt,
    required String branchId,
    required String partyKind,
    String contactId = '',
    String employeeId = '',
    required String partyName,
    String partyPhone = '',
    required double amount,
    required String currency,
    required String idempotencyKey,
    required String channel,
    String accountCode = '',
    required String counterAccountCode,
    required String reason,
  }) async {
    if (idempotencyKey.trim().isEmpty || partyKind.trim().isEmpty) {
      throw const AccountingApiError('بيانات سند القبض أو الصرف غير مكتملة.');
    }
    final response = await _transport.request(
      _baseUri.resolve(
        receipt ? 'accounting/receipts/direct' : 'accounting/payments/direct',
      ),
      method: 'POST',
      headers: _headers,
      body: jsonEncode({
        'branch_id': branchId,
        'party_kind': partyKind,
        if (contactId.isNotEmpty) 'contact_id': contactId,
        if (employeeId.isNotEmpty) 'employee_id': employeeId,
        if (partyName.isNotEmpty) 'party_name': partyName,
        if (partyPhone.isNotEmpty) 'party_phone': partyPhone,
        'amount_minor': (amount * 100).round(),
        'currency': currency,
        'idempotency_key': idempotencyKey.trim(),
        'channel': channel,
        if (accountCode.isNotEmpty) 'account_code': accountCode,
        if (counterAccountCode.isNotEmpty)
          'counter_account_code': counterAccountCode,
        'reason': reason,
      }),
    );
    final value = _decodeMap(
      response,
      receipt ? 'تعذر ترحيل سند القبض.' : 'تعذر ترحيل سند الصرف.',
    );
    final id =
        value[receipt ? 'receipt_id' : 'payment_id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw const AccountingApiError(
        'استجابة السند لا تحتوي المعرّف المحاسبي.',
      );
    }
    return id;
  }

  Future<List<Map<String, dynamic>>> listJournals({required String branchId}) =>
      _listData('accounting/journals', branchId, 'تعذر جلب القيود اليومية.');

  Future<List<Map<String, dynamic>>> listReceipts({required String branchId}) =>
      _listData('accounting/receipts', branchId, 'تعذر جلب سندات القبض.');

  Future<List<Map<String, dynamic>>> listSupplierPayments({
    required String branchId,
  }) => _listData('accounting/payments', branchId, 'تعذر جلب سندات الصرف.');

  Future<List<Map<String, dynamic>>> listContactBalances({
    required String branchId,
    String? type,
  }) async {
    final query = <String, String>{'branch_id': branchId};
    if (type != null && type.isNotEmpty) query['type'] = type;
    final response = await _transport.request(
      _baseUri
          .resolve('accounting/contact-balances')
          .replace(queryParameters: query),
      method: 'GET',
      headers: _headers,
    );
    final value = _decodeMap(response, 'تعذر جلب أرصدة العملاء والموردين.');
    final data = value['data'];
    return data is List
        ? data
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false)
        : const [];
  }

  Future<Map<String, dynamic>> contactLedger({
    required String branchId,
    required String contactId,
    required String role,
  }) async {
    if (role != 'customer' && role != 'supplier') {
      throw const AccountingApiError('نوع كشف الطرف غير صالح.');
    }
    final uri = _baseUri
        .resolve('accounting/contacts/${Uri.encodeComponent(contactId)}/ledger')
        .replace(queryParameters: {'branch_id': branchId, 'role': role});
    final response = await _transport.request(
      uri,
      method: 'GET',
      headers: _headers,
    );
    return _decodeMap(response, 'تعذر جلب كشف حساب العميل أو المورد.');
  }

  Future<Map<String, dynamic>> postSimpleJournal({
    required String branchId,
    required String localOperationId,
    required String description,
    required String debitAccountCode,
    required String creditAccountCode,
    required double amount,
    String? debitContactId,
    String? creditContactId,
  }) async {
    if (localOperationId.trim().isEmpty) {
      throw const AccountingApiError('معرّف عملية القيد غير مكتمل.');
    }
    if (!amount.isFinite || amount <= 0) {
      throw const AccountingApiError('أدخل مبلغًا صحيحًا أكبر من صفر.');
    }
    if (debitAccountCode == creditAccountCode) {
      throw const AccountingApiError('اختر حسابين مختلفين للمدين والدائن.');
    }
    final amountMinor = (amount * 100).round();
    final response = await _transport.request(
      _baseUri.resolve('accounting/journals'),
      method: 'POST',
      headers: _headers,
      body: jsonEncode({
        'branch_id': branchId,
        'local_operation_id': localOperationId,
        'description': description.trim(),
        'lines': [
          {
            'account_code': debitAccountCode,
            'debit_minor': amountMinor,
            'credit_minor': 0,
            if (debitContactId != null && debitContactId.isNotEmpty)
              'contact_id': debitContactId,
          },
          {
            'account_code': creditAccountCode,
            'debit_minor': 0,
            'credit_minor': amountMinor,
            if (creditContactId != null && creditContactId.isNotEmpty)
              'contact_id': creditContactId,
          },
        ],
      }),
    );
    final value = _decodeMap(response, 'تعذر ترحيل القيد البسيط.');
    final entry = value['entry'];
    if (entry is! Map) {
      throw const AccountingApiError('استجابة القيد المرحّل غير مكتملة.');
    }
    return Map<String, dynamic>.from(entry);
  }

  Future<void> voidSimpleJournal(
    String entryId, {
    required String reason,
  }) async {
    final response = await _transport.request(
      _baseUri.resolve(
        'accounting/journals/${Uri.encodeComponent(entryId)}/void',
      ),
      method: 'POST',
      headers: _headers,
      body: jsonEncode({'reason': reason.trim()}),
    );
    _decodeMap(response, 'تعذر حذف القيد البسيط.');
  }

  // Period management and opening balances are explicit owner actions.
  // Never automatically replay them merely because a screen is opened.
  Future<Map<String, dynamic>> administrationMetadata() =>
      _getMap('accounting/metadata', {}, 'تعذر جلب بيانات فترة المحاسبة.');

  Future<List<Map<String, dynamic>>> periodLocks() async => _mapList(
    (await _getMap(
      'accounting/period-locks',
      {},
      'تعذر جلب الفترات المقفلة.',
    ))['items'],
  );

  Future<Map<String, dynamic>> closeAccountingPeriod({
    required String branchId,
    required String through,
    required String reason,
    required int restoreGeneration,
    required String operationCreatedAt,
  }) => _postAdministration('accounting/period-locks', {
    'branch_id': branchId,
    'closed_through': through,
    'reason': reason,
    'restore_generation': restoreGeneration,
    'operation_created_at': operationCreatedAt,
  }, 'تعذر إقفال الفترة المحاسبية.');

  Future<Map<String, dynamic>> reopenAccountingPeriod({
    required String branchId,
    required String reason,
    required int restoreGeneration,
    required String operationCreatedAt,
  }) => _postAdministration('accounting/period-locks/reopen', {
    'branch_id': branchId,
    'reason': reason,
    'restore_generation': restoreGeneration,
    'operation_created_at': operationCreatedAt,
  }, 'تعذر إعادة فتح الفترة المحاسبية.');

  Future<Map<String, dynamic>> openingBalanceStatus(String branchId) => _getMap(
    'accounting/opening-balances/status',
    {'branch_id': branchId},
    'تعذر التحقق من صلاحية افتتاح الحسابات.',
  );

  Future<Map<String, dynamic>> postOpeningBalances(
    Map<String, dynamic> immutableRequest,
  ) => _postAdministration(
    'accounting/opening-balances',
    immutableRequest,
    'تعذر ترحيل الأرصدة الافتتاحية.',
  );

  Future<Map<String, dynamic>> accountingIntegrity(String branchId) => _getMap(
    'accounting/reports/integrity',
    {'branch_id': branchId},
    'تعذر إجراء مطابقة القيود والمخزون.',
  );

  Future<Map<String, dynamic>> consolidatedBalanceSheet({String? asOf}) =>
      _getMap(
        'accounting/reports/consolidated-balance-sheet',
        {'as_of': ?asOf},
        'تعذر إعداد المركز المالي المجمع.',
      );

  Future<List<Map<String, dynamic>>> fiscalYearClosures() async => _mapList(
    (await _getMap(
      'accounting/fiscal-year-closures',
      {},
      'تعذر قراءة السنوات المالية المقفلة.',
    ))['items'],
  );

  Future<Map<String, dynamic>> closeFiscalYear({
    required String branchId,
    required int year,
    required String operationId,
    required String reason,
    required int restoreGeneration,
    required String operationCreatedAt,
  }) => _postAdministration('accounting/fiscal-year-closures', {
    'branch_id': branchId,
    'fiscal_year': year,
    'operation_id': operationId,
    'reason': reason,
    'restore_generation': restoreGeneration,
    'operation_created_at': operationCreatedAt,
  }, 'تعذر إقفال السنة المالية.');

  Future<Map<String, dynamic>> _postAdministration(
    String path,
    Map<String, dynamic> request,
    String error,
  ) async {
    final response = await _transport.request(
      _baseUri.resolve(path),
      method: 'POST',
      headers: _headers,
      body: jsonEncode(request),
    );
    return _decodeMap(response, error);
  }

  Future<List<Map<String, dynamic>>> trialBalance({
    required String branchId,
    String? from,
    String? to,
    bool includeZero = false,
  }) async {
    final value = await _getMap('accounting/trial-balance', {
      'branch_id': branchId,
      'from': ?from,
      'to': ?to,
      if (includeZero) 'include_zero': '1',
    }, 'تعذر إعداد ميزان المراجعة.');
    return _mapList(value['items']);
  }

  Future<Map<String, dynamic>> profitAndLoss({
    required String branchId,
    required String from,
    required String to,
  }) => _getMap('accounting/reports/profit-loss', {
    'branch_id': branchId,
    'from': from,
    'to': to,
  }, 'تعذر إعداد قائمة الأرباح والخسائر.');

  Future<Map<String, dynamic>> balanceSheet({
    required String branchId,
    required String asOf,
  }) => _getMap('accounting/reports/balance-sheet', {
    'branch_id': branchId,
    'as_of': asOf,
  }, 'تعذر إعداد قائمة المركز المالي.');

  Future<Map<String, dynamic>> cashFlow({
    required String branchId,
    required String from,
    required String to,
  }) => _getMap('accounting/reports/cash-flow', {
    'branch_id': branchId,
    'from': from,
    'to': to,
  }, 'تعذر إعداد قائمة التدفقات النقدية.');

  Future<List<Map<String, dynamic>>> accountDirectory({
    required String branchId,
    String query = '',
  }) async => _mapList(
    (await _getMap('accounting/account-directory', {
      'branch_id': branchId,
      if (query.isNotEmpty) 'q': query,
    }, 'تعذر جلب دليل الحسابات والأطراف.'))['items'],
  );

  Future<Map<String, dynamic>> accountStatement({
    required String branchId,
    String accountId = '',
    String contactId = '',
    String role = '',
    String? from,
    String? to,
    bool includeChildren = false,
  }) => _getMap('accounting/account-statement', {
    'branch_id': branchId,
    if (accountId.isNotEmpty) 'account_id': accountId,
    if (contactId.isNotEmpty) 'contact_id': contactId,
    if (role.isNotEmpty) 'role': role,
    'from': ?from,
    'to': ?to,
    if (includeChildren) 'include_children': '1',
  }, 'تعذر إعداد كشف الحساب.');

  Future<Map<String, dynamic>> sourceDocument({
    required String branchId,
    required String referenceType,
    required String referenceId,
  }) => _getMap('accounting/source-document', {
    'branch_id': branchId,
    'reference_type': referenceType,
    'reference_id': referenceId,
  }, 'تعذر فتح المستند المحاسبي.');

  Future<List<Map<String, dynamic>>> productInquiry({
    required String branchId,
    String query = '',
  }) async => _mapList(
    (await _getMap('accounting/product-inquiry', {
      'branch_id': branchId,
      if (query.isNotEmpty) 'q': query,
    }, 'تعذر الاستعلام عن الصنف.'))['items'],
  );

  Future<Map<String, dynamic>> storeAccountTransfer({
    required String branchId,
    required String fromAccountCode,
    required String toAccountCode,
    required double amount,
    required String description,
    String? occurredAt,
  }) async {
    final response = await _transport.request(
      _baseUri.resolve('accounting/transfers'),
      method: 'POST',
      headers: _headers,
      body: jsonEncode({
        'branch_id': branchId,
        'operation_id': const Uuid().v4(),
        'from_account_code': fromAccountCode,
        'to_account_code': toAccountCode,
        'amount_minor': (amount * 100).round(),
        'description': description.trim(),
        'occurred_at': ?occurredAt,
      }),
    );
    final value = _decodeMap(response, 'تعذر ترحيل التحويل بين الحسابات.');
    return Map<String, dynamic>.from(value['entry'] as Map);
  }

  Future<List<Map<String, dynamic>>> listAccountTransfers({
    required String branchId,
  }) async => _mapList(
    (await _getMap('accounting/transfers', {
      'branch_id': branchId,
    }, 'تعذر جلب التحويلات.'))['items'],
  );

  Future<List<Map<String, dynamic>>> listStockMovements({
    required String branchId,
  }) => _listData(
    'accounting/stock-movements',
    branchId,
    'تعذر جلب حركات المخزون.',
  );

  Future<List<Map<String, dynamic>>> listReturns({
    required String branchId,
    required String type,
  }) => _listData(
    'accounting/returns',
    branchId,
    'تعذر جلب المرتجعات.',
    query: {'type': type},
  );

  Future<List<Map<String, dynamic>>> stockValuation({
    required String branchId,
  }) => _listItems(
    'accounting/stock-valuation',
    branchId,
    'تعذر إعداد تقييم المخزون.',
  );

  Future<List<Map<String, dynamic>>> _listData(
    String path,
    String branchId,
    String message, {
    Map<String, String> query = const {},
  }) async {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (var page = 1; page <= 1000; page++) {
      final uri = _baseUri
          .resolve(path)
          .replace(
            queryParameters: {
              ...query,
              'branch_id': branchId,
              'page': '$page',
              'per_page': '100',
            },
          );
      final response = await _transport
          .request(uri, method: 'GET', headers: _headers)
          .timeout(const Duration(seconds: 30));
      final value = _decodeMap(response, message);
      final data = value['data'];
      if (data is! List) {
        throw const AccountingApiError('استجابة قائمة المستندات غير مكتملة.');
      }
      for (final item in data) {
        if (item is! Map) {
          throw const AccountingApiError('مستند غير صالح في الاستجابة.');
        }
        final row = Map<String, dynamic>.from(item);
        final id = row['id']?.toString();
        if (id == null || seen.add(id)) result.add(row);
      }
      final lastPage = (value['last_page'] as num?)?.toInt() ?? 1;
      if (page >= lastPage) return result;
      if (data.isEmpty) {
        throw const AccountingApiError('توقفت صفحات المستندات قبل اكتمالها.');
      }
    }
    throw const AccountingApiError(
      'تجاوزت القائمة حد القراءة؛ استخدم فترة أو فرعًا أصغر.',
    );
  }

  Future<List<Map<String, dynamic>>> _listItems(
    String path,
    String branchId,
    String message,
  ) async {
    final response = await _transport.request(
      _baseUri.resolve('$path?branch_id=${Uri.encodeQueryComponent(branchId)}'),
      method: 'GET',
      headers: _headers,
    );
    final value = _decodeMap(response, message);
    final data = value['items'];
    return data is List
        ? data
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : const [];
  }

  Future<Map<String, dynamic>> _getMap(
    String path,
    Map<String, String> query,
    String message,
  ) async {
    final response = await _transport.request(
      _baseUri.resolve(path).replace(queryParameters: query),
      method: 'GET',
      headers: _headers,
    );
    return _decodeMap(response, message);
  }

  List<Map<String, dynamic>> _mapList(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false)
      : const [];

  Map<String, dynamic> _decodeMap(
    JsonResponse response,
    String fallbackMessage,
  ) {
    dynamic decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } catch (_) {
      throw const AccountingApiError('استجابة خادم المحاسبة غير صالحة.');
    }
    final value = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AccountingApiError(
        value['message']?.toString() ?? fallbackMessage,
        statusCode: response.statusCode,
      );
    }
    return value;
  }
}

class AccountingApiError implements Exception {
  const AccountingApiError(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  bool get retryableAuthentication => statusCode == 401;
  bool get restoreBoundaryViolation =>
      statusCode == 409 &&
      const {
        'RESTORE_GENERATION_REQUIRED',
        'RESTORE_GENERATION_MISMATCH',
        'RESTORE_GENERATION_AT_CREATION_MISMATCH',
        'OPERATION_CREATION_TIME_REQUIRED_AFTER_RESTORE',
        'OPERATION_CREATED_BEFORE_RESTORE',
        'CREATED_BEFORE_RESTORE',
      }.contains(message);
  bool get definitelyRejected =>
      statusCode != null &&
      statusCode! >= 400 &&
      statusCode! < 500 &&
      !retryableAuthentication &&
      !restoreBoundaryViolation &&
      !const {408, 425, 429}.contains(statusCode);
  @override
  String toString() => switch (message) {
    'ACCOUNTING_PERIOD_CLOSED' =>
      'الفترة المالية مقفلة؛ لا يمكن ترحيل هذه العملية قبل مراجعة مالك المنشأة.',
    'OPENING_OPERATION_CONFLICT' =>
      'معرّف الافتتاح مستخدم مسبقًا لبيانات مختلفة؛ تحقق من المستند على الخادم.',
    _ => message,
  };
}
