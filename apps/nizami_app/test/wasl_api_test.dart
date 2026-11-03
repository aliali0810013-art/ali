import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/wasl/wasl_api.dart';

class FakeTransport implements JsonTransport {
  final List<Uri> called = [];
  final List<Map<String, String>> headers = [];
  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    called.add(uri);
    this.headers.add(headers);
    if (uri.path.endsWith('capabilities')) {
      return const JsonResponse(
        statusCode: 200,
        body:
            '{"view_transfers":true,"view_raw_sms":false,"pair_devices":false}',
      );
    }
    if (uri.path.endsWith('transfers')) {
      return const JsonResponse(
        statusCode: 200,
        body:
            '{"items":[{"id":"101","amount":"1200.00","currency":"YER","source":"جيب","state":"sms_received","received_at":"2026-10-15"}]}',
      );
    }
    return const JsonResponse(statusCode: 403, body: '{"message":"غير مصرح"}');
  }
}

void main() {
  test(
    'WASL client calls accounting backend with user bearer, never WASL API key',
    () async {
      final fake = FakeTransport();
      final api = WaslApi(
        token: 'session-token',
        branchId: 'branch-1',
        transport: fake,
        baseUrl: 'https://accounting.example/api/v1',
      );
      final grants = await api.getCapabilities();
      expect(grants['view_raw_sms'], false);
      final items = await api.transfers();
      expect(items.single.state, 'sms_received');
      expect(fake.called.every((u) => u.host == 'accounting.example'), isTrue);
      expect(
        fake.headers.every(
          (h) =>
              h['Authorization'] == 'Bearer session-token' &&
              !h.containsKey('X-Integration-Key'),
        ),
        isTrue,
      );
      expect(() async => api.newPairingQr(), throwsA(isA<WaslApiError>()));
    },
  );
}
