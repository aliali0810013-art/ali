import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/inventory/stock_operations_api.dart';
import 'package:nizami/src/features/sync/stock_operation_outbox.dart';
import 'package:nizami/src/features/sync/quarantined_operation_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Map<String, dynamic> countRequest(String operation) => {
    'kind': 'inventory_count',
    'product_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'branch_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'operation_id': operation,
    'expected_quantity_milli': 1000,
    'target_quantity_milli': 1500,
    'reason': 'Physical stock count',
    'restore_generation': 0,
    'operation_created_at': '2026-10-31T20:00:00.000Z',
  };

  test('lost response after stock posting retries identical request', () async {
    final transport = _StockTransport(failFirst: true);
    final api = StockOperationsApi(
      token: 'test',
      transport: transport,
      baseUrl: 'https://staging.example/api/v1',
    );
    final queue = StockOperationOutbox('tenant-stock-a',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    final request = countRequest('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
    await queue.enqueue(request);
    await queue.enqueue(request);
    expect(await queue.count(), 1);
    final first = await queue.flush(api: api, currentRestoreGeneration: 0);
    expect(first.sent, 0);
    expect(await queue.count(), 1);
    final second = await queue.flush(api: api, currentRestoreGeneration: 0);
    expect(second.sent, 1);
    expect(await queue.count(), 0);
    expect(transport.sentBodies, hasLength(2));
    expect(transport.sentBodies[0], transport.sentBodies[1]);
  });

  test('same operation with changed quantity is refused', () async {
    final queue = StockOperationOutbox('tenant-stock-b',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    final request = countRequest('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
    await queue.enqueue(request);
    final altered = Map<String, dynamic>.from(request)
      ..['target_quantity_milli'] = 3000;
    await expectLater(queue.enqueue(altered), throwsStateError);
    expect(await queue.count(), 1);
  });

  test('stale stock operation stays quarantined, does not post', () async {
    final transport = _StockTransport();
    final queue = StockOperationOutbox('tenant-stock-c',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    await queue.enqueue(countRequest('ffffffff-ffff-4fff-8fff-ffffffffffff'));
    final result = await queue.flush(
      api: StockOperationsApi(token: 'test', transport: transport,
          baseUrl: 'https://staging.example/api/v1'),
      currentRestoreGeneration: 3,
    );
    expect(result.sent, 0);
    expect(result.quarantined, 1);
    expect(transport.sentBodies, isEmpty);
    expect(await queue.count(), 1);
  });

  test('stock balance conflict requires owner review and never auto-discards', () async {
    final transport = _StockTransport(conflictFirst: true);
    const operationId = '11111111-1111-4111-8111-111111111111';
    final queue = StockOperationOutbox('tenant-stock-conflict',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    await queue.enqueue(countRequest(operationId));
    final api = StockOperationsApi(token: 'test', transport: transport,
        baseUrl: 'https://staging.example/api/v1');
    final first = await queue.flush(api: api, currentRestoreGeneration: 0);
    expect(first.sent, 0);
    expect(first.quarantined, 1);
    expect(await queue.count(), 1);
    final review = QuarantinedOperationStore('tenant-stock-conflict');
    expect((await review.list()).single['operation_id'], operationId);
    await review.resolve(operationId: operationId, decision: 'discard',
        reviewer: 'test-accountant', note: 'reconcile physical count separately');
    final second = await queue.flush(api: api, currentRestoreGeneration: 0);
    expect(second.sent, 0);
    expect(await queue.count(), 0);
    // A reviewed discard does not replay the invalid operation.
    expect(transport.sentBodies, hasLength(1));
    expect((await review.auditLog()).single['decision'], 'discard');
  });

  test('branch transfer body keeps original ID and endpoint', () async {
    final transport = _StockTransport();
    final request = countRequest('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
    request.remove('branch_id');
    request.remove('operation_id');
    request.remove('expected_quantity_milli');
    request.remove('target_quantity_milli');
    request['kind'] = 'stock_transfer';
    request['source_branch_id'] = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    request['destination_branch_id'] = '99999999-9999-4999-8999-999999999999';
    request['local_operation_id'] = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    request['quantity_milli'] = 300;
    request['expected_source_quantity_milli'] = 1000;
    final queue = StockOperationOutbox('tenant-stock-d',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    await queue.enqueue(request);
    final result = await queue.flush(
        api: StockOperationsApi(token: 'test', transport: transport,
            baseUrl: 'https://staging.example/api/v1'),
        currentRestoreGeneration: 0);
    expect(result.sent, 1);
    expect(transport.urls.single, endsWith('/accounting/stock-transfers'));
  });
}

class _StockTransport implements JsonTransport {
  _StockTransport({this.failFirst = false, this.conflictFirst = false});
  final bool failFirst;
  final bool conflictFirst;
  final List<String> sentBodies = [];
  final List<String> urls = [];

  @override
  Future<JsonResponse> request(Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    urls.add(uri.toString());
    sentBodies.add(body ?? '');
    final data = Map<String, dynamic>.from(jsonDecode(body!) as Map);
    expect(data, isNot(contains('kind')));
    if (failFirst && sentBodies.length == 1) {
      throw StateError('simulated lost HTTP acknowledgement');
    }
    if (conflictFirst && sentBodies.length == 1) {
      return const JsonResponse(statusCode: 409,
          body: '{"message":"INVENTORY_BALANCE_CONFLICT"}');
    }
    final id = data['operation_id'] ?? data['local_operation_id'];
    if (uri.path.contains('stock-transfers')) {
      expect(method, 'POST');
      return JsonResponse(statusCode: 201,
          body: jsonEncode({'transfer': {'operation_id': id, 'value_minor': 300}}));
    }
    expect(method, 'PUT');
    return JsonResponse(statusCode: 200,
        body: jsonEncode({'stock': {'operation_id': id, 'quantity_milli': 1500}}));
  }
}
