import 'json_transport.dart';

JsonTransport createJsonTransport() => _UnsupportedJsonTransport();

class _UnsupportedJsonTransport implements JsonTransport {
  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) {
    throw UnsupportedError('HTTP transport is unavailable on this platform.');
  }
}
