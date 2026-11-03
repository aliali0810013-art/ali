import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/accounting/accounting_api.dart';
import 'package:nizami/src/features/modules/module_workspace_page.dart';

void main() {
  test(
    'receipt and supplier payment lists use canonical accounting routes',
    () async {
      final transport = _SettlementListTransport();
      final api = AccountingApi(
        token: 'owner-token',
        transport: transport,
        baseUrl: 'https://accounting.example/api/v1',
      );

      final receipts = await api.listReceipts(branchId: 'branch-1');
      final payments = await api.listSupplierPayments(branchId: 'branch-1');

      expect(receipts.single['id'], 'receipt-1');
      expect(payments.single['id'], 'payment-1');
      expect(
        transport.uris.map((uri) => uri.path),
        containsAll(<String>[
          '/api/v1/accounting/receipts',
          '/api/v1/accounting/payments',
        ]),
      );
      for (final uri in transport.uris) {
        expect(uri.queryParameters['branch_id'], 'branch-1');
        expect(uri.queryParameters['page'], '1');
        expect(uri.queryParameters['per_page'], '100');
        expect(uri.path, isNot(contains('/documents')));
      }
    },
  );

  test('general voucher sends a free party and explicit counter account', () async {
    final transport = _GeneralVoucherTransport();
    final api = AccountingApi(
      token: 'owner-token',
      transport: transport,
      baseUrl: 'https://accounting.example/api/v1',
    );

    final id = await api.storeDirectVoucher(
      receipt: false,
      branchId: 'branch-1',
      partyKind: 'other',
      partyName: 'فني صيانة',
      partyPhone: '771123456',
      amount: 225,
      currency: 'YER',
      idempotencyKey: 'operation-1',
      channel: 'cash',
      accountCode: '1100-CASH',
      counterAccountCode: '5200-EXPENSES',
      reason: 'صرف أتعاب صيانة لشخص غير مسجل كمورد',
    );

    expect(id, 'payment-1');
    expect(transport.uri.path, '/api/v1/accounting/payments/direct');
    expect(transport.body['party_kind'], 'other');
    expect(transport.body['party_name'], 'فني صيانة');
    expect(transport.body['counter_account_code'], '5200-EXPENSES');
    expect(transport.body['amount_minor'], 22500);
  });

  test(
    'canonical settlement rows preserve party amount channel and identity',
    () {
      final receipt = projectSettlementRecord(<String, dynamic>{
        'id': 'receipt-1',
        'idempotency_key': 'operation-1',
        'number': 'REC-1',
        'invoice_number': 'INV-1',
        'customer_name': 'عميل الاختبار',
        'amount_minor': 12345,
        'currency': 'YER',
        'channel': 'cash',
        'reason': 'تحصيل دفعة اختبارية',
        'status': 'posted',
        'created_at': '2026-10-29T08:30:00Z',
      }, isReceipt: true);
      final payment = projectSettlementRecord(
        <String, dynamic>{
          'id': 'payment-1',
          'number': 'PAY-1',
          'supplier_name': 'مورد الاختبار',
          'amount_minor': 5000,
          'channel': 'bank',
          'status': 'voided',
        },
        isReceipt: false,
        fallbackNow: DateTime.utc(2026, 10, 29),
      );

      expect(receipt['title'], 'عميل الاختبار');
      expect(receipt['amount'], 123.45);
      expect(receipt['settled'], isTrue);
      expect(receipt['serverId'], 'receipt-1');
      expect(receipt['clientOperationId'], 'operation-1');
      expect(receipt['details'], contains('REC-1'));
      expect(receipt['details'], contains('INV-1'));
      expect(receipt['details'], contains('نقدًا'));
      expect(payment['title'], 'مورد الاختبار');
      expect(payment['amount'], 50.0);
      expect(payment['settled'], isFalse);
      expect(payment['status'], 'voided');
      expect(payment['details'], contains('تحويل بنكي'));
    },
  );
}

class _GeneralVoucherTransport implements JsonTransport {
  late Uri uri;
  Map<String, dynamic> body = const {};

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    this.uri = uri;
    this.body = Map<String, dynamic>.from(jsonDecode(body ?? '{}') as Map);
    return const JsonResponse(
      statusCode: 201,
      body: '{"payment_id":"payment-1","status":"posted"}',
    );
  }
}

class _SettlementListTransport implements JsonTransport {
  final uris = <Uri>[];

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    uris.add(uri);
    final isReceipt = uri.path.endsWith('/accounting/receipts');
    return JsonResponse(
      statusCode: 200,
      body:
          '{"data":[{"id":"${isReceipt ? 'receipt-1' : 'payment-1'}"}],"last_page":1}',
    );
  }
}
