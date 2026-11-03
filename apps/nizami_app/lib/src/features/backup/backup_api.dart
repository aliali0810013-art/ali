import 'dart:convert';

import '../../auth/json_transport.dart';

class BackupApi {
  BackupApi({required this.token, JsonTransport? transport})
    : _transport = transport ?? createJsonTransport(),
      _baseUri = Uri.parse(
        '${const String.fromEnvironment('NINESOFT_API_BASE_URL', defaultValue: 'https://ninesoft.qodynex.tech/api/v1').replaceFirst(RegExp(r'/+$'), '')}/',
      );

  final String token;
  final JsonTransport _transport;
  final Uri _baseUri;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json; charset=utf-8',
    'Authorization': 'Bearer $token',
  };

  Future<List<ServerBackup>> list() async {
    final response = await _transport.request(
      _baseUri.resolve('backups'),
      method: 'GET',
      headers: _headers,
    );
    final data = _decode(response);
    final values = data['data'];
    return values is List
        ? values
              .whereType<Map>()
              .map(
                (item) =>
                    ServerBackup.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : const [];
  }

  Future<void> create() async {
    final response = await _transport.request(
      _baseUri.resolve('backups'),
      method: 'POST',
      headers: _headers,
    );
    _decode(response);
  }

  Future<void> restore(String name) async {
    final response = await _transport.request(
      _baseUri.resolve('backups/${Uri.encodeComponent(name)}/restore'),
      method: 'POST',
      headers: _headers,
    );
    _decode(response);
  }

  Future<String> download(String name) async {
    final response = await _transport.request(
      _baseUri.resolve('backups/${Uri.encodeComponent(name)}'),
      method: 'GET',
      headers: _headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('تعذر تنزيل النسخة الاحتياطية.');
    }
    return response.body;
  }

  Map<String, dynamic> _decode(JsonResponse response) {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    final data = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data['message']?.toString() ?? 'تعذر إكمال طلب النسخ الاحتياطي.',
      );
    }
    return data;
  }
}

class ServerBackup {
  const ServerBackup({
    required this.name,
    required this.size,
    required this.createdAt,
  });
  final String name;
  final int size;
  final DateTime createdAt;

  factory ServerBackup.fromJson(Map<String, dynamic> json) => ServerBackup(
    name: json['name']?.toString() ?? '',
    size: int.tryParse(json['size']?.toString() ?? '') ?? 0,
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.now(),
  );
}
