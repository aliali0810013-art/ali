import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/auth_api.dart';
import 'package:nizami/src/auth/http_auth_api.dart';
import 'package:nizami/src/auth/json_transport.dart';

void main() {
  test('login sends normalized credentials and maps tenant context', () async {
    final transport = _FakeTransport(
      JsonResponse(
        statusCode: 200,
        body: jsonEncode({
          'token': 'plain-token',
          'expires_at': '2026-11-01T00:00:00Z',
          'user': {
            'id': 'user-id',
            'username': 'owner',
            'display_name': 'المالك',
            'role_code': 'owner',
            'branches': [
              {'id': 'branch-id'},
            ],
          },
          'tenant': {'id': 'tenant-id', 'name': 'المؤسسة', 'slug': 'company'},
        }),
      ),
    );
    final api = HttpAuthApi(
      transport: transport,
      baseUrl: 'https://api.example.test/api/v1/',
    );

    final session = await api.login(
      tenant: ' company ',
      username: ' owner ',
      password: 'secret',
    );

    expect(
      transport.uri.toString(),
      'https://api.example.test/api/v1/auth/login',
    );
    expect(transport.method, 'POST');
    expect(jsonDecode(transport.body!), {
      'tenant': 'company',
      'username': 'owner',
      'password': 'secret',
      'device_name': 'NineSoft Flutter',
    });
    expect(session.token, 'plain-token');
    expect(session.displayName, 'المالك');
    expect(session.branchIds, ['branch-id']);
  });

  test('validation error is exposed without leaking request details', () async {
    final api = HttpAuthApi(
      transport: _FakeTransport(
        JsonResponse(
          statusCode: 422,
          body: jsonEncode({
            'errors': {
              'username': ['بيانات الدخول غير صحيحة.'],
            },
          }),
        ),
      ),
      baseUrl: 'https://api.example.test/api/v1',
    );

    await expectLater(
      api.login(tenant: 'company', username: 'owner', password: 'wrong'),
      throwsA(
        isA<AuthApiException>()
            .having((error) => error.statusCode, 'statusCode', 422)
            .having(
              (error) => error.message,
              'message',
              'بيانات الدخول غير صحيحة.',
            ),
      ),
    );
  });

  test(
    'cached session validation uses auth/me with the bearer token',
    () async {
      final transport = _FakeTransport(
        JsonResponse(
          statusCode: 200,
          body: jsonEncode({
            'user': {
              'id': 'fresh-user-id',
              'username': 'fresh-owner',
              'display_name': 'Fresh Owner',
              'role_code': 'cashier',
              'must_change_password': true,
              'permissions': ['invoices.view'],
              'branches': [
                {'id': 'remaining-branch'},
              ],
            },
            'tenant': {
              'id': 'fresh-tenant-id',
              'name': 'Fresh Tenant',
              'slug': 'fresh-tenant',
            },
          }),
        ),
      );
      final api = HttpAuthApi(
        transport: transport,
        baseUrl: 'https://api.example.test/api/v1',
      );

      final refreshed = await api.validateSession(_cachedSession);

      expect(transport.uri?.path, '/api/v1/auth/me');
      expect(transport.method, 'GET');
      expect(transport.headers?['Authorization'], 'Bearer cached-token');
      expect(transport.body, isNull);
      expect(refreshed.token, 'cached-token');
      expect(refreshed.userId, 'fresh-user-id');
      expect(refreshed.username, 'fresh-owner');
      expect(refreshed.roleCode, 'cashier');
      expect(refreshed.tenantId, 'fresh-tenant-id');
      expect(refreshed.branchIds, ['remaining-branch']);
      expect(refreshed.permissions, ['invoices.view']);
      expect(refreshed.expiresAt, _cachedSession.expiresAt);
    },
  );

  test(
    'cached session validation preserves the confirmed HTTP status',
    () async {
      final api = HttpAuthApi(
        transport: _FakeTransport(
          const JsonResponse(
            statusCode: 401,
            body: '{"message":"Unauthenticated"}',
          ),
        ),
        baseUrl: 'https://api.example.test/api/v1',
      );

      await expectLater(
        api.validateSession(_cachedSession),
        throwsA(
          isA<AuthApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    },
  );
}

final _cachedSession = AuthSession(
  token: 'cached-token',
  userId: 'cached-user-id',
  username: 'cached-owner',
  displayName: 'Cached Owner',
  roleCode: 'owner',
  tenantId: 'cached-tenant-id',
  tenantName: 'Cached Tenant',
  tenantSlug: 'cached-tenant',
  branchIds: const ['revoked-branch', 'remaining-branch'],
  mustChangePassword: false,
  permissions: const ['invoices.view', 'invoices.delete'],
  expiresAt: DateTime.utc(2026, 11),
);

class _FakeTransport implements JsonTransport {
  _FakeTransport(this.response);

  final JsonResponse response;
  Uri? uri;
  String? method;
  String? body;
  Map<String, String>? headers;

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    this.uri = uri;
    this.method = method;
    this.body = body;
    this.headers = headers;
    return response;
  }
}
