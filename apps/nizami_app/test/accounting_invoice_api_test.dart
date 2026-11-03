import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/accounting/accounting_api.dart';
import 'package:nizami/src/features/invoices/invoice_pdf_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'ninesoft.accounting.device_uuid.v1':
          '11111111-1111-4111-8111-111111111111',
    });
  });

  test(
    'accounting synchronization is enabled in release builds by default',
    () {
      expect(AccountingApi.enabled, isTrue);
    },
  );

  test(
    'invoice post preserves discount, tendered amount and payment channel',
    () async {
      final transport = _InvoiceTransport();
      final api = AccountingApi(
        token: 'owner-token',
        transport: transport,
        baseUrl: 'https://accounting.example/api/v1',
      );
      final invoice = InvoiceDocument(
        number: 'INV-LOCAL-1',
        customerName: 'عميل',
        customerPhone: '770000000',
        lines: const [InvoiceLine(name: 'صنف', quantity: 2, unitPrice: 100)],
        currency: 'YER',
        employeeName: 'مالك',
        branchLabel: '',
        createdAt: DateTime.utc(2026, 10, 24),
        paymentMode: 'cash',
        paidAmount: 190,
        discountAmount: 10,
        amountTendered: 200,
        paymentChannel: 'bank',
        paymentAccountCode: '1190-BANK-TEST',
        localOperationId: '22222222-2222-4222-8222-222222222222',
      );

      await api.postInvoice(
        branchId: '33333333-3333-4333-8333-333333333333',
        invoice: invoice,
      );

      final payload = jsonDecode(transport.body!) as Map<String, dynamic>;
      expect(payload['paid_minor'], 19000);
      expect(payload['amount_tendered_minor'], 20000);
      expect(payload['payment_channel'], 'bank');
      expect(payload['payment_account_code'], '1190-BANK-TEST');
      expect((payload['items'] as List).first['discount_minor'], 1000);
    },
  );

  test(
    'unresolved local stock line is never serialized as a service',
    () async {
      final transport = _InvoiceTransport();
      final api = AccountingApi(token: 'owner-token', transport: transport);
      final pendingLine = const InvoiceLine(
        name: 'Offline stock',
        quantity: 1,
        unitPrice: 10,
        pendingCatalogSync: true,
      );
      final invoice = InvoiceDocument(
        number: 'INV-PENDING',
        customerName: 'Cash customer',
        customerPhone: '',
        lines: [pendingLine],
        currency: 'YER',
        employeeName: 'Owner',
        branchLabel: '',
        createdAt: DateTime.utc(2026, 11, 1),
        localOperationId: 'operation-pending',
      );

      await expectLater(
        api.postInvoice(branchId: 'branch-a', invoice: invoice),
        throwsA(isA<AccountingApiError>()),
      );
      expect(transport.body, isNull);
      expect(
        InvoiceLine.fromJson(pendingLine.toJson()).pendingCatalogSync,
        isTrue,
      );
    },
  );

  test(
    'prepare is deterministic and includes replacement and rational intent',
    () async {
      final api = AccountingApi(token: 'owner-token');
      final invoice = InvoiceDocument(
        number: 'INV-LOCAL-EXACT',
        customerName: 'Exact customer',
        customerPhone: '770000222',
        customerId: '44444444-4444-4444-8444-444444444444',
        lines: const [
          InvoiceLine(
            name: 'Milligrams',
            quantity: 250,
            unitPrice: 0.005,
            productId: '55555555-5555-4555-8555-555555555555',
            saleOptionId: '66666666-6666-4666-8666-666666666666',
            priceNumeratorMinor: 500000,
            priceDenominator: 1000000,
          ),
        ],
        currency: 'YER',
        employeeName: 'Owner',
        branchLabel: 'Main',
        createdAt: DateTime.utc(2026, 11, 1, 8),
        paidAmount: 1.25,
        amountTendered: 2,
        paymentChannel: 'bank',
        paymentAccountCode: '1190-BANK-TEST',
        localOperationId: '77777777-7777-4777-8777-777777777777',
        replacementInvoiceId: '88888888-8888-4888-8888-888888888888',
        restoreGenerationAtCreation: 3,
      );

      final first = await api.prepareInvoiceRequest(
        branchId: '33333333-3333-4333-8333-333333333333',
        invoice: invoice,
        restoreGeneration: 3,
      );
      final second = await api.prepareInvoiceRequest(
        branchId: '33333333-3333-4333-8333-333333333333',
        invoice: invoice,
        restoreGeneration: 3,
      );

      expect(jsonEncode(second), jsonEncode(first));
      expect(
        first['replacement_invoice_id'],
        '88888888-8888-4888-8888-888888888888',
      );
      final line = Map<String, dynamic>.from(
        (first['items'] as List).single as Map,
      );
      expect(line['quantity_milli'], 250000);
      expect(line['price_numerator_minor'], 500000);
      expect(line['price_denominator'], 1000000);
    },
  );

  test(
    'post sends exact persisted JSON and uses persisted replacement endpoint',
    () async {
      final transport = _InvoiceTransport();
      final api = AccountingApi(
        token: 'owner-token',
        transport: transport,
        baseUrl: 'https://accounting.example/api/v1',
      );
      final persisted = <String, dynamic>{
        'branch_id': 'branch-a',
        'device_id': 'device-a',
        'local_operation_id': 'operation-a',
        'restore_generation': 2,
        'operation_created_at': '2026-11-01T08:00:00.000Z',
        'replacement_invoice_id': 'invoice-old',
        'paid_minor': 125,
        'items': [
          {
            'name': 'Exact',
            'quantity_milli': 250000,
            'unit_price_minor': 1,
            'price_numerator_minor': 500000,
            'price_denominator': 1000000,
          },
        ],
      };

      await api.postInvoiceRequest(persisted);

      expect(transport.body, jsonEncode(persisted));
      expect(
        transport.uri?.path,
        endsWith('/accounting/invoices/invoice-old/replace'),
      );
    },
  );

  test(
    'manual option price intent is explicit and internally consistent',
    () async {
      final api = AccountingApi(token: 'owner-token');
      InvoiceDocument invoice(InvoiceLine line) => InvoiceDocument(
        number: 'INV-MANUAL-PRICE',
        customerName: 'Cash customer',
        customerPhone: '',
        lines: [line],
        currency: 'YER',
        employeeName: 'Owner',
        branchLabel: 'Main',
        createdAt: DateTime.utc(2026, 11, 1, 9),
        paidAmount: 10000.08,
        localOperationId: '99999999-9999-4999-8999-999999999999',
      );
      const valid = InvoiceLine(
        name: 'Carton item',
        quantity: 24,
        unitPrice: 416.67,
        productId: '55555555-5555-4555-8555-555555555555',
        saleOptionId: '66666666-6666-4666-8666-666666666666',
        exactQuantityMilli: 24000,
        priceNumeratorMinor: 41667,
        priceDenominator: 1,
        priceOverridden: true,
      );

      final request = await api.prepareInvoiceRequest(
        branchId: '33333333-3333-4333-8333-333333333333',
        invoice: invoice(valid),
      );
      final item = Map<String, dynamic>.from((request['items'] as List).single);
      expect(item['price_overridden'], isTrue);
      expect(item['price_numerator_minor'], 41667);
      expect(item['price_denominator'], 1);
      expect(InvoiceLine.fromJson(valid.toJson()).priceOverridden, isTrue);

      await expectLater(
        api.prepareInvoiceRequest(
          branchId: '33333333-3333-4333-8333-333333333333',
          invoice: invoice(
            const InvoiceLine(
              name: 'Carton item',
              quantity: 24,
              unitPrice: 416.67,
              productId: '55555555-5555-4555-8555-555555555555',
              saleOptionId: '66666666-6666-4666-8666-666666666666',
              priceNumeratorMinor: 1000001,
              priceDenominator: 24,
              priceOverridden: true,
            ),
          ),
        ),
        throwsA(
          isA<AccountingApiError>().having(
            (error) => error.message,
            'message',
            'MANUAL_PRICE_INTENT_MISMATCH',
          ),
        ),
      );
    },
  );

  test('purchase replacement uses the purchase PUT endpoint', () async {
    final transport = _InvoiceTransport();
    final api = AccountingApi(
      token: 'owner-token',
      transport: transport,
      baseUrl: 'https://accounting.example/api/v1',
    );
    final request = <String, dynamic>{
      'branch_id': 'branch-a',
      'supplier_name': 'Supplier A',
      'items': [
        {'name': 'Item A', 'quantity_milli': 1000, 'unit_price_minor': 5000},
      ],
    };

    final invoice = await api.replacePurchase(
      invoiceId: 'purchase-old',
      request: request,
    );

    expect(transport.method, 'PUT');
    expect(transport.uri?.path, endsWith('/accounting/purchases/purchase-old'));
    expect(transport.body, jsonEncode(request));
    expect(invoice['id'], 'invoice-id');
  });
}

class _InvoiceTransport implements JsonTransport {
  String? body;
  Uri? uri;
  String? method;

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    this.uri = uri;
    this.body = body;
    this.method = method;
    return const JsonResponse(
      statusCode: 201,
      body: '{"invoice":{"id":"invoice-id","number":"INV-1"}}',
    );
  }
}
