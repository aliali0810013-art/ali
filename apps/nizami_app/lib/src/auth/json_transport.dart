import 'json_transport_stub.dart'
    if (dart.library.io) 'json_transport_io.dart'
    if (dart.library.html) 'json_transport_web.dart'
    as implementation;

class JsonResponse {
  const JsonResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

abstract interface class JsonTransport {
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  });
}

JsonTransport createJsonTransport() => implementation.createJsonTransport();
