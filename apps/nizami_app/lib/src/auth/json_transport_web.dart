// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import '../core/release/client_release.dart';
import 'json_transport.dart';

JsonTransport createJsonTransport() => WebJsonTransport();

class WebJsonTransport implements JsonTransport {
  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final request = html.HttpRequest();
    final completion = Completer<JsonResponse>();

    void fail(String message) {
      if (!completion.isCompleted) {
        completion.completeError(Exception(message));
      }
    }

    try {
      request.open(method, uri.toString(), async: true);
      request.timeout = 25000;
      ClientRelease.addHeaders(
        headers,
        platform: 'web',
      ).forEach(request.setRequestHeader);
      request.onLoad.listen((_) {
        if (!completion.isCompleted) {
          completion.complete(
            JsonResponse(
              statusCode: request.status ?? 0,
              body: request.responseText ?? '',
            ),
          );
        }
      });
      request.onError.listen(
        (_) => fail('تعذر الاتصال بالخادم. تحقق من الإنترنت ثم أعد المحاولة.'),
      );
      request.onAbort.listen(
        (_) => fail('أُلغي الاتصال بالخادم قبل اكتمال العملية.'),
      );
      request.onTimeout.listen(
        (_) => fail('انتهت مهلة الاتصال بالخادم. أعد المحاولة.'),
      );
      if (body == null) {
        request.send();
      } else {
        request.send(utf8.encode(body));
      }
    } catch (_) {
      fail('تعذر تجهيز الاتصال بالخادم. أعد المحاولة بعد لحظات.');
    }

    return completion.future;
  }
}
