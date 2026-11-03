import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/accounting/accounting_api.dart';
import 'package:nizami/src/features/modules/module_workspace_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'ninesoft.accounting.device_uuid.v1':
          '11111111-1111-4111-8111-111111111111',
    }),
  );

  test('stable UI routes only stock increases through purchase', () {
    expect(stableStockIncrease(current: 2, requested: 3), isTrue);
    expect(stableStockIncrease(current: 3, requested: 3), isFalse);
    expect(stableStockIncrease(current: 3, requested: 2), isFalse);
  });

  test('stable purchase operation keeps the same id for retry', () async {
    final transport = _Transport();
    await AccountingApi(
      token: 'token',
      transport: transport,
      baseUrl: 'https://example.test/api/v1',
    ).postPurchase(
      branchId: '22222222-2222-4222-8222-222222222222',
      supplierName: 'مورد',
      supplierPhone: '',
      paymentMode: 'credit',
      operationId: '33333333-3333-4333-8333-333333333333',
      items: const [
        {
          'product_id': '44444444-4444-4444-8444-444444444444',
          'name': 'صنف',
          'quantity_milli': 1000,
          'unit_price_minor': 100,
        },
      ],
      restoreGeneration: 0,
    );
    final body = jsonDecode(transport.body!) as Map<String, dynamic>;
    expect(body['local_operation_id'], '33333333-3333-4333-8333-333333333333');
  });

  test('stable stock supply requires a supplier for paid and credit modes', () {
    final source = File(
      'lib/src/features/modules/module_workspace_page.dart',
    ).readAsStringSync();
    expect(source, contains("labelText: 'اسم المورد (مطلوب)'"));
    expect(source, contains('سواء كان التوريد مدفوعًا أو آجلًا'));
    expect(
      source,
      isNot(contains("supplierName: request.paymentMode == 'credit'")),
    );
  });
}

class _Transport implements JsonTransport {
  String? body;

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    this.body = body;
    return const JsonResponse(
      statusCode: 201,
      body: '{"invoice":{"id":"id","number":"PUR-1"}}',
    );
  }
}
