import 'dart:convert';

import '../../auth/json_transport.dart';

class AdministrationApi {
  AdministrationApi({required this.token, JsonTransport? transport})
    : _transport = transport ?? createJsonTransport(),
      _baseUri = Uri.parse(
        '${const String.fromEnvironment('NINESOFT_API_BASE_URL', defaultValue: 'https://ninesoft.qodynex.tech/api/v1').replaceFirst(RegExp(r'/+$'), '')}/',
      );

  final String token;
  final JsonTransport _transport;
  final Uri _baseUri;

  Future<List<Map<String, dynamic>>> branches() => _list('branches');
  Future<List<Map<String, dynamic>>> customerCopies() =>
      _list('customer-copies');
  Future<List<Map<String, dynamic>>> users() => _list('users');

  Future<Map<String, dynamic>> createCustomerCopy({
    required String name,
    required String slug,
    required String ownerUsername,
    required String ownerName,
    required String password,
    required DateTime accessExpiresAt,
    required String address,
    required String phone,
  }) => _request('customer-copies', 'POST', {
    'name': name.trim(),
    'slug': slug.trim().toLowerCase(),
    'owner_username': ownerUsername.trim().toLowerCase(),
    'owner_name': ownerName.trim(),
    'password': password,
    'access_expires_at': accessExpiresAt.toUtc().toIso8601String(),
    'address': address.trim().isEmpty ? null : address.trim(),
    'phone': phone.trim().isEmpty ? null : phone.trim(),
  });

  Future<void> stopCustomerCopy(String id) async {
    await _request('customer-copies/$id', 'DELETE');
  }

  Future<Map<String, dynamic>> createBranch({
    required String code,
    required String name,
    required String address,
    required String phone,
  }) => _request('branches', 'POST', {
    'code': code.trim().toUpperCase(),
    'name': name.trim(),
    'address': address.trim().isEmpty ? null : address.trim(),
    'phone': phone.trim().isEmpty ? null : phone.trim(),
  });

  Future<Map<String, dynamic>> createUser({
    required String username,
    required String displayName,
    required String password,
    required String roleCode,
    required List<String> branchIds,
    List<String> permissions = const [],
    DateTime? accessExpiresAt,
  }) => _request('users', 'POST', {
    'username': username.trim().toLowerCase(),
    'display_name': displayName.trim(),
    'password': password,
    'role_code': roleCode,
    'branch_ids': branchIds,
    'permissions': permissions,
    'access_expires_at': accessExpiresAt?.toUtc().toIso8601String(),
  });

  Future<Map<String, dynamic>> updateUser(
    String id, {
    String? password,
    DateTime? accessExpiresAt,
    bool clearExpiry = false,
    List<String>? permissions,
  }) => _request('users/$id', 'PUT', {
    if (password != null && password.isNotEmpty) 'password': password,
    if (clearExpiry || accessExpiresAt != null)
      'access_expires_at': accessExpiresAt?.toUtc().toIso8601String(),
    'permissions': ?permissions,
  });

  Future<void> deleteBranch(String id) async {
    await _request('branches/$id', 'DELETE');
  }

  Future<Map<String, dynamic>> updateBranch(
    String id, {
    required String name,
  }) => _request('branches/$id', 'PUT', {'name': name.trim()});

  Future<void> deleteUser(String id) async {
    await _request('users/$id', 'DELETE');
  }

  Future<List<Map<String, dynamic>>> _list(String path) async {
    final response = await _request(path, 'GET');
    final values = response['data'];
    return values is List
        ? values
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : const [];
  }

  Future<Map<String, dynamic>> _request(
    String path,
    String method, [
    Map<String, Object?>? body,
  ]) async {
    final response = await _transport.request(
      _baseUri.resolve(path),
      method: method,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $token',
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
      final message = data['message']?.toString();
      final errors = data['errors'];
      final firstError = errors is Map
          ? errors.values
                .whereType<List>()
                .expand((e) => e)
                .firstOrNull
                ?.toString()
          : null;
      throw AdministrationApiError(
        firstError ?? message ?? 'تعذر إكمال الطلب.',
      );
    }
    return data['data'] is Map
        ? Map<String, dynamic>.from(data['data'] as Map)
        : data;
  }
}

class AdministrationApiError implements Exception {
  const AdministrationApiError(this.message);
  final String message;
  @override
  String toString() => message;
}
