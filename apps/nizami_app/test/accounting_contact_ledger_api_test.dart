import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/accounting/accounting_api.dart';

void main() {
  test(
    'contact ledger sends the fixed role and branch without name matching',
    () async {
      final transport = _LedgerTransport();
      final api = AccountingApi(
        token: 'token',
        transport: transport,
        baseUrl: 'https://accounting.example/api/v1',
      );

      await api.contactLedger(
        branchId: 'branch-1',
        contactId: 'contact/id',
        role: 'supplier',
      );

      expect(
        transport.uri?.path,
        endsWith('/accounting/contacts/contact%2Fid/ledger'),
      );
      expect(transport.uri?.queryParameters['branch_id'], 'branch-1');
      expect(transport.uri?.queryParameters['role'], 'supplier');
    },
  );

  test(
    'contact ledger rejects an unsupported role before network access',
    () async {
      final transport = _LedgerTransport();
      final api = AccountingApi(
        token: 'token',
        transport: transport,
        baseUrl: 'https://accounting.example/api/v1',
      );

      await expectLater(
        api.contactLedger(
          branchId: 'branch-1',
          contactId: 'contact-1',
          role: 'both',
        ),
        throwsA(isA<AccountingApiError>()),
      );
      expect(transport.uri, isNull);
    },
  );

  test('source document sends the immutable accounting reference', () async {
    final transport = _LedgerTransport();
    final api = AccountingApi(
      token: 'token',
      transport: transport,
      baseUrl: 'https://accounting.example/api/v1',
    );

    await api.sourceDocument(
      branchId: 'branch-1',
      referenceType: 'purchase_invoice',
      referenceId: 'invoice/id',
    );

    expect(transport.uri?.path, endsWith('/accounting/source-document'));
    expect(transport.uri?.queryParameters, {
      'branch_id': 'branch-1',
      'reference_type': 'purchase_invoice',
      'reference_id': 'invoice/id',
    });
  });
}

class _LedgerTransport implements JsonTransport {
  Uri? uri;

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    this.uri = uri;
    return const JsonResponse(
      statusCode: 200,
      body: '{"contact":{"id":"contact-1"},"balance_minor":0,"data":[]}',
    );
  }
}
