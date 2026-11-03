import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/accounting/accounting_api.dart';

void main() {
  test('simple journal posts one balanced debit and credit request', () async {
    final transport = _JournalTransport();
    final api = AccountingApi(
      token: 'owner-token',
      transport: transport,
      baseUrl: 'https://accounting.example/api/v1',
    );

    final entry = await api.postSimpleJournal(
      branchId: '11111111-1111-4111-8111-111111111111',
      localOperationId: '22222222-2222-4222-8222-222222222222',
      description: 'إيداع رأس مال',
      debitAccountCode: '1100-CASH',
      creditAccountCode: '3100-CAPITAL',
      amount: 125.50,
    );

    expect(entry['id'], 'entry-id');
    expect(transport.method, 'POST');
    expect(transport.uri.path, '/api/v1/accounting/journals');
    expect(transport.headers['Authorization'], 'Bearer owner-token');
    final payload = jsonDecode(transport.body!) as Map<String, dynamic>;
    expect(payload['description'], 'إيداع رأس مال');
    expect(
      payload['local_operation_id'],
      '22222222-2222-4222-8222-222222222222',
    );
    expect(payload['lines'], [
      {'account_code': '1100-CASH', 'debit_minor': 12550, 'credit_minor': 0},
      {'account_code': '3100-CAPITAL', 'debit_minor': 0, 'credit_minor': 12550},
    ]);
  });

  test(
    'simple journal rejects invalid amount and same account locally',
    () async {
      final api = AccountingApi(
        token: 'token',
        transport: _JournalTransport(),
        baseUrl: 'https://accounting.example/api/v1',
      );

      await expectLater(
        api.postSimpleJournal(
          branchId: 'branch',
          localOperationId: '22222222-2222-4222-8222-222222222222',
          description: 'اختبار',
          debitAccountCode: '1100-CASH',
          creditAccountCode: '2100-AP',
          amount: 0,
        ),
        throwsA(isA<AccountingApiError>()),
      );
      await expectLater(
        api.postSimpleJournal(
          branchId: 'branch',
          localOperationId: '22222222-2222-4222-8222-222222222222',
          description: 'اختبار',
          debitAccountCode: '1100-CASH',
          creditAccountCode: '1100-CASH',
          amount: 10,
        ),
        throwsA(isA<AccountingApiError>()),
      );
    },
  );

  test('simple journal retry preserves the caller operation id', () async {
    final transport = _JournalTransport();
    final api = AccountingApi(
      token: 'owner-token',
      transport: transport,
      baseUrl: 'https://accounting.example/api/v1',
    );
    const operationId = '33333333-3333-4333-8333-333333333333';

    for (var attempt = 0; attempt < 2; attempt++) {
      await api.postSimpleJournal(
        branchId: '11111111-1111-4111-8111-111111111111',
        localOperationId: operationId,
        description: 'Retry after lost response',
        debitAccountCode: '1100-CASH',
        creditAccountCode: '3100-CAPITAL',
        amount: 25,
      );
    }

    expect(transport.bodies, hasLength(2));
    for (final body in transport.bodies) {
      expect(
        (jsonDecode(body) as Map<String, dynamic>)['local_operation_id'],
        operationId,
      );
    }
  });

  test(
    'simple journal reversal sends a reason to the scoped endpoint',
    () async {
      final transport = _JournalTransport();
      final api = AccountingApi(
        token: 'owner-token',
        transport: transport,
        baseUrl: 'https://accounting.example/api/v1',
      );

      await api.voidSimpleJournal('entry-id', reason: 'اختيار حساب خاطئ');

      expect(transport.method, 'POST');
      expect(transport.uri.path, '/api/v1/accounting/journals/entry-id/void');
      expect(jsonDecode(transport.body!), {'reason': 'اختيار حساب خاطئ'});
    },
  );
}

class _JournalTransport implements JsonTransport {
  Uri uri = Uri();
  String method = '';
  String? body;
  Map<String, String> headers = const {};
  final List<String> bodies = [];

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    this.uri = uri;
    this.method = method;
    this.headers = headers;
    this.body = body;
    if (body != null) bodies.add(body);
    return const JsonResponse(
      statusCode: 201,
      body: '{"entry":{"id":"entry-id"}}',
    );
  }
}
