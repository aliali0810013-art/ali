import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/modules/catalog_sync_api.dart';
import 'package:nizami/src/features/modules/module_workspace_page.dart';

void main() {
  test('customer save returns the canonical server identity', () async {
    final transport = _ContactTransport(
      responseBody: jsonEncode({
        'customer': {
          'id': '11111111-1111-4111-8111-111111111111',
          'name': 'عميل جديد',
          'phone': '777123456',
          'type': 'customer',
          'version': 4,
        },
      }),
    );
    final contact = await CatalogSyncApi(
      token: 'token',
      transport: transport,
    ).saveCustomer(name: 'عميل جديد', phone: '777123456');

    expect(contact.id, '11111111-1111-4111-8111-111111111111');
    expect(contact.version, 4);
    expect(contact.type, 'customer');
    expect(transport.method, 'POST');
    expect(transport.path, endsWith('/catalog/customers'));
    expect(jsonDecode(transport.body!)['phone'], '777123456');
  });

  test('supplier save returns the canonical server identity', () async {
    final contact = await CatalogSyncApi(
      token: 'token',
      transport: _ContactTransport(
        responseBody: jsonEncode({
          'supplier': {
            'id': '22222222-2222-4222-8222-222222222222',
            'name': 'مورد جديد',
            'phone': '733000000',
            'type': 'supplier',
            'version': 2,
          },
        }),
      ),
    ).saveSupplier(name: 'مورد جديد', phone: '733000000');

    expect(contact.id, '22222222-2222-4222-8222-222222222222');
    expect(contact.version, 2);
    expect(contact.type, 'supplier');
  });

  test(
    'contact selection normalizes whitespace and disambiguates by phone',
    () {
      final selected = selectCanonicalContact(
        const [
          {'id': 'a', 'name': 'أحمد   علي', 'phone': '711', 'type': 'customer'},
          {'id': 'b', 'name': 'أحمد علي', 'phone': '722', 'type': 'customer'},
        ],
        name: '  أحمد علي ',
        phone: '722',
      );

      expect(selected?.id, 'b');
    },
  );

  test('ambiguous same-name contacts are never linked to a random ledger', () {
    expect(
      () => selectCanonicalContact(
        const [
          {'id': 'a', 'name': 'محمد علي', 'phone': '711'},
          {'id': 'b', 'name': 'محمد علي', 'phone': '722'},
        ],
        name: 'محمد علي',
        phone: '',
      ),
      throwsStateError,
    );
  });

  test('a differing supplied phone never links a same-name contact', () {
    expect(
      () => selectCanonicalContact(
        const [
          {'id': 'a', 'name': 'محمد علي', 'phone': '711'},
        ],
        name: 'محمد علي',
        phone: '722',
      ),
      throwsStateError,
    );
  });

  test('a unique same-name contact may be selected when phone is absent', () {
    final selected = selectCanonicalContact(
      const [
        {'id': 'a', 'name': 'محمد علي', 'phone': '711'},
      ],
      name: 'محمد علي',
      phone: '',
    );

    expect(selected?.id, 'a');
  });

  test('statement guard admits only one in-flight open per contact', () {
    final guard = ContactStatementOpenGuard();
    expect(guard.tryAcquire('customer-1'), isTrue);
    expect(guard.tryAcquire('customer-1'), isFalse);
    expect(guard.isActive('customer-1'), isTrue);
    guard.release('customer-1');
    expect(guard.tryAcquire('customer-1'), isTrue);
  });
}

class _ContactTransport implements JsonTransport {
  _ContactTransport({required this.responseBody});

  final String responseBody;
  String? method;
  String? path;
  String? body;

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    this.method = method;
    path = uri.path;
    this.body = body;
    return JsonResponse(statusCode: 200, body: responseBody);
  }
}
