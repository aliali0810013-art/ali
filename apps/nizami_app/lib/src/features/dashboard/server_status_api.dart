import '../../auth/json_transport.dart';

class ServerStatusApi {
  ServerStatusApi({
    required this.token,
    JsonTransport? transport,
    String? baseUrl,
  }) : _transport = transport ?? createJsonTransport(),
       _baseUri = Uri.parse(
         '${(baseUrl ?? const String.fromEnvironment('NINESOFT_API_BASE_URL', defaultValue: 'https://ninesoft.qodynex.tech/api/v1')).replaceFirst(RegExp(r'/+$'), '')}/',
       );

  final String token;
  final JsonTransport _transport;
  final Uri _baseUri;

  Future<void> verify() async {
    final response = await _transport.request(
      _baseUri.resolve('auth/me'),
      method: 'GET',
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ServerStatusException(response.statusCode);
    }
  }
}

class ServerStatusException implements Exception {
  const ServerStatusException(this.statusCode);

  final int statusCode;
}
