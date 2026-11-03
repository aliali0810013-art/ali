import 'dart:convert';
import 'dart:typed_data';

import '../../auth/json_transport.dart';

class WhatsappStatus {
  const WhatsappStatus({required this.state, this.qrCode, this.number});

  final String state;
  final String? qrCode;
  final String? number;

  bool get connected => state == 'open';
}

class WhatsappApi {
  WhatsappApi({required this.token, JsonTransport? transport, String? baseUrl})
    : _transport = transport ?? createJsonTransport(),
      _baseUri = Uri.parse(
        '${(baseUrl ?? const String.fromEnvironment('NINESOFT_API_BASE_URL', defaultValue: 'https://ninesoft.qodynex.tech/api/v1')).replaceFirst(RegExp(r'/+$'), '')}/',
      );

  final String token;
  final JsonTransport _transport;
  final Uri _baseUri;

  Future<WhatsappStatus> status(String branchId) async {
    final data = await _request('branches/$branchId/whatsapp', 'GET');
    return WhatsappStatus(
      state: data['state']?.toString() ?? 'close',
      number: data['number']?.toString(),
    );
  }

  Future<WhatsappStatus> connect(String branchId) async {
    final data = await _request('branches/$branchId/whatsapp/connect', 'POST');
    return WhatsappStatus(
      state: data['state']?.toString() ?? 'connecting',
      qrCode: data['qr_code']?.toString(),
    );
  }

  Future<WhatsappStatus> disconnect(String branchId) async {
    final data = await _request('branches/$branchId/whatsapp', 'DELETE');
    return WhatsappStatus(state: data['state']?.toString() ?? 'disconnected');
  }

  Future<Map<String, dynamic>> sendInvoice({
    required String branchId,
    required String localNumber,
    required String caption,
    required String filename,
    required Uint8List image,
    required String idempotencyKey,
  }) async {
    return _request(
      'branches/$branchId/whatsapp/invoices',
      'POST',
      body: {
        'local_number': localNumber,
        'caption': caption,
        'filename': filename,
        'image_base64': base64Encode(image),
        'idempotency_key': idempotencyKey,
      },
    );
  }

  Future<Map<String, dynamic>> _request(
    String path,
    String method, {
    Map<String, Object?>? body,
  }) async {
    final response = await _transport.request(
      _baseUri.resolve(path),
      method: method,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: body == null ? null : jsonEncode(body),
    );
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    final data = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errors = data['errors'];
      if (errors is Map && errors.values.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) throw Exception(first.first);
      }
      throw Exception(data['message'] ?? 'تعذر إكمال طلب واتساب.');
    }
    return data;
  }
}
