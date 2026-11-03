import 'dart:convert';
import '../../auth/json_transport.dart';

class ReturnsApiError implements Exception {
  const ReturnsApiError(this.message, this.statusCode);
  final String message;
  final int statusCode;
  // These responses reject the transaction. A timeout/5xx/409 is retained for safe replay/review.
  bool get definitelyRejected => const {400, 422}.contains(statusCode);
  @override
  String toString() => message;
}

class ReturnsApi {
  ReturnsApi({required this.token, JsonTransport? transport, String? baseUrl})
    : _transport = transport ?? createJsonTransport(),
      _baseUri = Uri.parse(
        '${(baseUrl ?? const String.fromEnvironment('NINESOFT_API_BASE_URL', defaultValue: 'https://ninesoft.qodynex.tech/api/v1')).replaceFirst(RegExp(r'/+$'), '')}/',
      );
  final String token;
  final JsonTransport _transport;
  final Uri _baseUri;

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _transport
        .request(
          _baseUri.resolve(path),
          method: body == null ? 'GET' : 'POST',
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw ReturnsApiError(
        'استجابة غير مكتملة؛ أعد المحاولة بنفس الطلب.',
        response.statusCode >= 500 ? response.statusCode : 0,
      );
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded is! Map) {
      throw ReturnsApiError(
        decoded is Map
            ? decoded['message']?.toString() ?? 'تعذر تنفيذ طلب المرتجع.'
            : 'استجابة غير صالحة.',
        response.statusCode,
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> originals(
    String branch,
    String type,
    String query, {
    int page = 1,
  }) => _request(
    'accounting/returns/originals?${Uri(queryParameters: {'branch_id': branch, 'type': type, 'q': query, 'page': '$page'}).query}',
  );
  Future<Map<String, dynamic>> list(
    String branch,
    String type, {
    int page = 1,
  }) => _request(
    'accounting/returns?${Uri(queryParameters: {'branch_id': branch, 'type': '${type}_return', 'page': '$page'}).query}',
  );
  Future<Map<String, dynamic>> returnable(String invoiceId) =>
      _request('accounting/invoices/$invoiceId/returnable-items');
  Future<Map<String, dynamic>> post(
    String invoiceId,
    Map<String, dynamic> immutablePayload,
  ) async {
    final result = await _request(
      'accounting/invoices/$invoiceId/returns',
      body: immutablePayload,
    );
    final invoice = result['invoice'];
    if (invoice is! Map ||
        invoice['id'] is! String ||
        (invoice['id'] as String).isEmpty ||
        invoice['reversal_of_id'] != invoiceId ||
        invoice['status'] != 'posted' ||
        invoice['device_id'] != immutablePayload['device_id'] ||
        invoice['local_operation_id'] !=
            immutablePayload['local_operation_id'] ||
        !const {'sale_return', 'purchase_return'}.contains(invoice['type'])) {
      throw const ReturnsApiError(
        'تأكيد المرتجع غير مكتمل؛ احتفظ بمعرف العملية وأعد المحاولة.',
        0,
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> postDirect(
    Map<String, dynamic> immutablePayload,
  ) async {
    final result = await _request(
      'accounting/returns/direct',
      body: immutablePayload,
    );
    final invoice = result['invoice'];
    if (invoice is! Map ||
        invoice['id'] is! String ||
        (invoice['id'] as String).isEmpty ||
        invoice['reversal_of_id'] != null ||
        invoice['status'] != 'posted' ||
        invoice['device_id'] != immutablePayload['device_id'] ||
        invoice['local_operation_id'] !=
            immutablePayload['local_operation_id'] ||
        invoice['type'] != immutablePayload['type']) {
      throw const ReturnsApiError(
        'تأكيد المرتجع المباشر غير مكتمل؛ أعد إرسال الطلب نفسه ولا تنشئ طلبًا جديدًا.',
        0,
      );
    }
    return result;
  }
}
