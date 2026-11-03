import 'dart:convert';
import 'dart:io';

import '../core/release/client_release.dart';
import 'json_transport.dart';

JsonTransport createJsonTransport() => IoJsonTransport();

class IoJsonTransport implements JsonTransport {
  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.openUrl(method, uri);
      ClientRelease.addHeaders(
        headers,
        platform: Platform.operatingSystem,
      ).forEach(request.headers.set);
      if (body != null) {
        request.add(utf8.encode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      return JsonResponse(
        statusCode: response.statusCode,
        body: await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 25)),
      );
    } finally {
      client.close(force: true);
    }
  }
}
