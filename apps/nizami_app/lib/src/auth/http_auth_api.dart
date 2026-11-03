import 'dart:convert';

import 'auth_api.dart';
import 'json_transport.dart';

AuthApi createHttpAuthApi({JsonTransport? transport, String? baseUrl}) =>
    HttpAuthApi(
      transport: transport ?? createJsonTransport(),
      baseUrl:
          baseUrl ??
          const String.fromEnvironment(
            'NINESOFT_API_BASE_URL',
            defaultValue: 'https://ninesoft.qodynex.tech/api/v1',
          ),
    );

class HttpAuthApi implements AuthApi, AuthSessionValidator {
  HttpAuthApi({required this._transport, required String baseUrl})
    : _baseUri = Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/');

  final JsonTransport _transport;
  final Uri _baseUri;

  @override
  Future<AuthSession> login({
    required String tenant,
    required String username,
    required String password,
  }) async {
    final response = await _request(
      'auth/login',
      method: 'POST',
      body: {
        'tenant': tenant.trim(),
        'username': username.trim(),
        'password': password,
        'device_name': 'NineSoft Flutter',
      },
    );
    return _sessionFromResponse(
      response,
      token: _string(response['token'], 'token'),
    );
  }

  AuthSession _sessionFromResponse(
    Map<String, dynamic> response, {
    required String token,
    DateTime? fallbackExpiresAt,
  }) {
    final user = _map(response['user'], 'user');
    final tenantData = _map(response['tenant'], 'tenant');
    final branches = user['branches'] is List
        ? user['branches'] as List
        : const [];

    return AuthSession(
      token: token,
      userId: _string(user['id'], 'user.id'),
      username: _string(user['username'], 'user.username'),
      displayName: _string(user['display_name'], 'user.display_name'),
      roleCode: _string(user['role_code'], 'user.role_code'),
      tenantId: _string(tenantData['id'], 'tenant.id'),
      tenantName: _string(tenantData['name'], 'tenant.name'),
      tenantSlug: _string(tenantData['slug'], 'tenant.slug'),
      branchIds: branches
          .whereType<Map>()
          .map((branch) => branch['id'])
          .whereType<String>()
          .toList(growable: false),
      mustChangePassword: user['must_change_password'] == true,
      permissions: (user['permissions'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      expiresAt:
          DateTime.tryParse(response['expires_at']?.toString() ?? '') ??
          fallbackExpiresAt,
    );
  }

  @override
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    await _request(
      'auth/password',
      method: 'PUT',
      token: token,
      body: {
        'current_password': currentPassword,
        'password': password,
        'password_confirmation': passwordConfirmation,
      },
    );
  }

  @override
  Future<void> logout(String token) async {
    await _request('auth/session', method: 'DELETE', token: token);
  }

  @override
  Future<AuthSession> validateSession(AuthSession cachedSession) async {
    final response = await _request(
      'auth/me',
      method: 'GET',
      token: cachedSession.token,
    );
    return _sessionFromResponse(
      response,
      token: cachedSession.token,
      fallbackExpiresAt: cachedSession.expiresAt,
    );
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    required String method,
    Map<String, Object?>? body,
    String? token,
  }) async {
    try {
      final response = await _transport.request(
        _baseUri.resolve(path),
        method: method,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: body == null ? null : jsonEncode(body),
      );
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthApiException(
          _errorMessage(data, response.statusCode),
          statusCode: response.statusCode,
        );
      }
      return data;
    } on AuthApiException {
      rethrow;
    } on FormatException {
      throw const AuthApiException('استجابة الخادم غير صالحة.');
    } catch (_) {
      throw const AuthApiException(
        'تعذر الاتصال بالخادم. تحقق من الإنترنت وعنوان الخادم.',
      );
    }
  }

  String _errorMessage(Map<String, dynamic> data, int statusCode) {
    final errors = data['errors'];
    if (errors is Map) {
      for (final value in errors.values) {
        if (value is List && value.isNotEmpty) return value.first.toString();
      }
    }
    if (data['message'] is String && (data['message'] as String).isNotEmpty) {
      return data['message'] as String;
    }
    return statusCode == 401
        ? 'انتهت الجلسة أو بيانات الدخول غير صحيحة.'
        : 'تعذر إكمال الطلب من الخادم.';
  }

  Map<String, dynamic> _map(Object? value, String field) {
    if (value is Map<String, dynamic>) return value;
    throw AuthApiException('استجابة الخادم لا تحتوي على $field.');
  }

  String _string(Object? value, String field) {
    if (value is String && value.isNotEmpty) return value;
    throw AuthApiException('استجابة الخادم لا تحتوي على $field.');
  }
}
