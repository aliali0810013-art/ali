import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/dashboard/server_status_api.dart';

class _Transport implements JsonTransport {
  _Transport(this.statusCode);

  final int statusCode;
  Uri? requestedUri;
  Map<String, String>? requestedHeaders;

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    requestedUri = uri;
    requestedHeaders = headers;
    return JsonResponse(statusCode: statusCode, body: '{}');
  }
}

void main() {
  test(
    'server heartbeat verifies the authenticated session endpoint',
    () async {
      final transport = _Transport(200);
      await ServerStatusApi(
        token: 'token-1',
        transport: transport,
        baseUrl: 'https://example.test/api/v1',
      ).verify();

      expect(transport.requestedUri?.path, '/api/v1/auth/me');
      expect(transport.requestedHeaders?['Authorization'], 'Bearer token-1');
    },
  );

  test('server heartbeat rejects an unauthenticated response', () async {
    await expectLater(
      ServerStatusApi(
        token: 'expired',
        transport: _Transport(401),
        baseUrl: 'https://example.test/api/v1',
      ).verify(),
      throwsA(isA<ServerStatusException>()),
    );
  });
}
