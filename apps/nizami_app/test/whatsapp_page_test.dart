import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/whatsapp/whatsapp_api.dart';
import 'package:nizami/src/features/whatsapp/whatsapp_page.dart';

class _FakeTransport implements JsonTransport {
  _FakeTransport({this.initiallyConnected = false});

  final bool initiallyConnected;
  final List<String> methods = [];

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    methods.add('$method ${uri.path}');
    if (uri.path.endsWith('/connect')) {
      return const JsonResponse(
        statusCode: 200,
        body: '{"state":"connecting","qr_code":null}',
      );
    }
    if (method == 'DELETE') {
      return const JsonResponse(
        statusCode: 200,
        body: '{"state":"disconnected"}',
      );
    }
    return JsonResponse(
      statusCode: 200,
      body: initiallyConnected ? '{"state":"open"}' : '{"state":"close"}',
    );
  }
}

void main() {
  testWidgets('WhatsApp page requests an isolated branch QR connection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: WhatsappPage(
            branchIds: const ['branch-a', 'branch-b'],
            token: 'test-token',
            api: WhatsappApi(
              token: 'test-token',
              transport: _FakeTransport(),
              baseUrl: 'https://example.test/api/v1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('اربط واتساب هذا الفرع'), findsOneWidget);
    expect(find.byKey(const ValueKey('connect-whatsapp')), findsOneWidget);
  });

  testWidgets('connected branch can disconnect its server session', (
    tester,
  ) async {
    final transport = _FakeTransport(initiallyConnected: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: WhatsappPage(
            branchIds: const ['branch-a'],
            token: 'test-token',
            api: WhatsappApi(
              token: 'test-token',
              transport: transport,
              baseUrl: 'https://example.test/api/v1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('disconnect-whatsapp')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-disconnect-whatsapp')));
    await tester.pumpAndSettle();

    expect(
      transport.methods,
      contains('DELETE /api/v1/branches/branch-a/whatsapp'),
    );
    expect(find.byKey(const ValueKey('disconnect-whatsapp')), findsNothing);
  });
}
