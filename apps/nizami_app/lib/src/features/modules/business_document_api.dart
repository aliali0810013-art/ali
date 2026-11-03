import 'dart:convert';

import '../../auth/json_transport.dart';

class BusinessDocumentApi {
  BusinessDocumentApi({
    required this.token,
    JsonTransport? transport,
    String? baseUrl,
  }) : _transport = transport ?? createJsonTransport(),
       _base = Uri.parse(
         '${(baseUrl ?? const String.fromEnvironment('NINESOFT_API_BASE_URL', defaultValue: 'https://ninesoft.qodynex.tech/api/v1')).replaceFirst(RegExp(r'/+$'), '')}/',
       );

  final String token;
  final JsonTransport _transport;
  final Uri _base;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  Future<List<Map<String, dynamic>>> list(
    String branchId,
    String moduleKey,
  ) async {
    final uri = _base.resolve(
      'documents?branch_id=${Uri.encodeQueryComponent(branchId)}&module_key=${Uri.encodeQueryComponent(moduleKey)}',
    );
    final response = await _transport.request(
      uri,
      method: 'GET',
      headers: _headers,
    );
    final data = _decode(response.statusCode, response.body);
    return (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<String> save(
    Map<String, Object?> payload, {
    int restoreGeneration = 0,
  }) async {
    final response = await _transport.request(
      _base.resolve('documents'),
      method: 'POST',
      headers: _headers,
      body: jsonEncode({...payload, 'restore_generation': restoreGeneration}),
    );
    return _decode(response.statusCode, response.body)['id']?.toString() ?? '';
  }

  Future<void> remove(String id) async {
    final response = await _transport.request(
      _base.resolve('documents/${Uri.encodeComponent(id)}'),
      method: 'DELETE',
      headers: _headers,
    );
    _decode(response.statusCode, response.body);
  }

  Future<int> update(
    String id,
    Map<String, Object?> payload, {
    required int expectedVersion,
    required int restoreGeneration,
  }) async {
    final response = await _transport.request(
      _base.resolve('documents/${Uri.encodeComponent(id)}'),
      method: 'PUT',
      headers: _headers,
      body: jsonEncode({
        ...payload,
        'expected_version': expectedVersion,
        'restore_generation': restoreGeneration,
      }),
    );
    final value = _decode(response.statusCode, response.body);
    return ((value['document'] as Map?)?['version'] as num?)?.toInt() ??
        expectedVersion + 1;
  }

  Map<String, dynamic> _decode(int status, String body) {
    final decoded = jsonDecode(body);
    final data = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (status < 200 || status >= 300) {
      throw BusinessDocumentApiError(
        data['message']?.toString() ?? 'تعذر مزامنة المستندات مع الخادم.',
      );
    }
    return data;
  }
}

class BusinessDocumentApiError implements Exception {
  const BusinessDocumentApiError(this.message);
  final String message;
  @override
  String toString() => message;
}
