import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/accounting/accounting_api.dart';
import 'package:nizami/src/features/accounting/settlement_idempotency_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'lost receipt response retries with the same durable idempotency key',
    () async {
      final store = SettlementIdempotencyStore(
        tenantScope: 'tenant-1',
        branchId: 'branch-1',
      );
      final firstClaim = await store.claim(
        kind: SettlementOperationKind.customerReceipt,
        invoiceId: 'invoice-1',
        amountMinor: 12500,
        currency: 'YER',
        channel: 'cash',
        reason: 'دفعة من العميل',
      );
      final transport = _LostResponseTransport(responseId: 'receipt-1');
      final api = AccountingApi(
        token: 'token',
        transport: transport,
        baseUrl: 'https://example.test/api/v1',
      );

      await expectLater(
        api.storeReceipt(
          invoiceId: 'invoice-1',
          amount: 125,
          currency: 'YER',
          idempotencyKey: firstClaim.idempotencyKey,
          channel: 'cash',
          reason: 'دفعة من العميل',
        ),
        throwsA(isA<TimeoutException>()),
      );

      final retryClaim =
          await SettlementIdempotencyStore(
            tenantScope: 'tenant-1',
            branchId: 'branch-1',
          ).claim(
            kind: SettlementOperationKind.customerReceipt,
            invoiceId: 'invoice-1',
            amountMinor: 12500,
            currency: 'yer',
            channel: 'CASH',
            reason: '  دفعة   من العميل  ',
          );

      expect(retryClaim.idempotencyKey, firstClaim.idempotencyKey);
      expect(
        await api.storeReceipt(
          invoiceId: 'invoice-1',
          amount: 125,
          currency: 'YER',
          idempotencyKey: retryClaim.idempotencyKey,
          channel: 'cash',
          reason: 'دفعة من العميل',
        ),
        'receipt-1',
      );
      expect(transport.keys, [
        firstClaim.idempotencyKey,
        firstClaim.idempotencyKey,
      ]);

      await store.acknowledge(retryClaim);
      final nextOperation = await store.claim(
        kind: SettlementOperationKind.customerReceipt,
        invoiceId: 'invoice-1',
        amountMinor: 12500,
        currency: 'YER',
        channel: 'cash',
        reason: 'دفعة من العميل',
      );
      expect(nextOperation.idempotencyKey, isNot(firstClaim.idempotencyKey));
    },
  );

  test('lost supplier-payment response also reuses its durable key', () async {
    final store = SettlementIdempotencyStore(
      tenantScope: 'tenant-2',
      branchId: 'branch-2',
    );
    final firstClaim = await store.claim(
      kind: SettlementOperationKind.supplierPayment,
      invoiceId: 'purchase-1',
      amountMinor: 5000,
      currency: 'YER',
      channel: 'bank',
      reason: 'دفعة للمورد',
    );
    final transport = _LostResponseTransport(responseId: 'payment-1');
    final api = AccountingApi(
      token: 'token',
      transport: transport,
      baseUrl: 'https://example.test/api/v1',
    );

    await expectLater(
      api.storeSupplierPayment(
        invoiceId: 'purchase-1',
        amount: 50,
        currency: 'YER',
        idempotencyKey: firstClaim.idempotencyKey,
        channel: 'bank',
        reason: 'دفعة للمورد',
      ),
      throwsA(isA<TimeoutException>()),
    );
    final retryClaim =
        await SettlementIdempotencyStore(
          tenantScope: 'tenant-2',
          branchId: 'branch-2',
        ).claim(
          kind: SettlementOperationKind.supplierPayment,
          invoiceId: 'purchase-1',
          amountMinor: 5000,
          currency: 'YER',
          channel: 'bank',
          reason: 'دفعة للمورد',
        );
    expect(retryClaim.idempotencyKey, firstClaim.idempotencyKey);
    expect(
      await api.storeSupplierPayment(
        invoiceId: 'purchase-1',
        amount: 50,
        currency: 'YER',
        idempotencyKey: retryClaim.idempotencyKey,
        channel: 'bank',
        reason: 'دفعة للمورد',
      ),
      'payment-1',
    );
    expect(transport.keys, [
      firstClaim.idempotencyKey,
      firstClaim.idempotencyKey,
    ]);
    await store.acknowledge(retryClaim);
  });

  test('changing the real settlement account creates a distinct key', () async {
    final store = SettlementIdempotencyStore(
      tenantScope: 'tenant-3',
      branchId: 'branch-3',
    );
    final cash = await store.claim(
      kind: SettlementOperationKind.customerReceipt,
      invoiceId: 'invoice-3',
      amountMinor: 1000,
      currency: 'YER',
      channel: 'cash',
      accountCode: '1100-CASH',
      reason: 'تحصيل فاتورة',
    );
    final bank = await store.claim(
      kind: SettlementOperationKind.customerReceipt,
      invoiceId: 'invoice-3',
      amountMinor: 1000,
      currency: 'YER',
      channel: 'cash',
      accountCode: '1190-BANK',
      reason: 'تحصيل فاتورة',
    );

    expect(bank.idempotencyKey, isNot(cash.idempotencyKey));
  });
}

class _LostResponseTransport implements JsonTransport {
  _LostResponseTransport({required this.responseId});

  final String responseId;
  final List<String> keys = <String>[];
  var _calls = 0;

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final payload = Map<String, dynamic>.from(jsonDecode(body!) as Map);
    keys.add(payload['idempotency_key']?.toString() ?? '');
    _calls += 1;
    if (_calls == 1) {
      throw TimeoutException('response lost after server commit');
    }
    final responseKey = uri.path.contains('/payments')
        ? 'payment_id'
        : 'receipt_id';
    return JsonResponse(
      statusCode: 201,
      body: jsonEncode(<String, Object?>{responseKey: responseId}),
    );
  }
}
