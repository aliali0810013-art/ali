import 'dart:convert';

import '../../auth/json_transport.dart';

/// NineSoft-only backend proxy. NEVER connect Flutter directly to WASL using an
/// X-Integration-Key: that secret stays on the authenticated accounting server.
class WaslApi {
  WaslApi({
    required this.token,
    required this.branchId,
    JsonTransport? transport,
    String? baseUrl,
  }) : _transport = transport ?? createJsonTransport(),
       _uri = Uri.parse(
         '${(baseUrl ?? const String.fromEnvironment('NINESOFT_API_BASE_URL', defaultValue: 'https://ninesoft.qodynex.tech/api/v1')).replaceFirst(RegExp(r'/+$'), '')}/',
       );

  static const bool enabled = bool.fromEnvironment(
    'NINESOFT_WASL_ENABLED',
    defaultValue: true,
  );
  final String token;
  final String branchId;
  final JsonTransport _transport;
  final Uri _uri;

  Future<Map<String, dynamic>> getCapabilities() => _call('wasl/capabilities');
  Future<Map<String, dynamic>> getStatus() =>
      _call('wasl/status?branch_id=${Uri.encodeQueryComponent(branchId)}');
  Future<Map<String, dynamic>> newPairingQr() => _call(
    'wasl/pairing/qr',
    method: 'POST',
    payload: {'branch_id': branchId},
  );

  Future<void> unlink() async {
    await _call(
      'wasl/unlink',
      method: 'POST',
      payload: {'branch_id': branchId},
    ).timeout(
      const Duration(seconds: 12),
      onTimeout: () => throw const WaslApiError(
        'انتهت مهلة فصل الجهاز. تحقق من اتصال الخادم ثم حاول مجددًا.',
      ),
    );
  }

  Future<Map<String, dynamic>> pairingStatus(String pairingId) => _call(
    'wasl/pairing/${Uri.encodeComponent(pairingId)}?branch_id=${Uri.encodeQueryComponent(branchId)}',
  );

  Future<int> sync() async {
    final r = await _call(
      'wasl/sync',
      method: 'POST',
      payload: {'branch_id': branchId},
    );
    return (r['processed'] as num?)?.toInt() ?? 0;
  }

  Future<List<WaslTransfer>> transfers({int afterId = 0}) async {
    final data = await _call(
      'wasl/transfers?after_id=$afterId&branch_id=${Uri.encodeQueryComponent(branchId)}',
    );
    return (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((v) => WaslTransfer.fromJson(Map<String, dynamic>.from(v)))
        .toList(growable: false);
  }

  Future<void> matchInvoice({
    required String transferId,
    required String invoiceNumber,
  }) async {
    await _call(
      'wasl/transfers/${Uri.encodeComponent(transferId)}/match',
      method: 'POST',
      payload: {'invoice_number': invoiceNumber, 'branch_id': branchId},
    );
  }

  Future<void> voidReceipt({
    required String transferId,
    required String reason,
  }) async {
    await _call(
      'wasl/transfers/${Uri.encodeComponent(transferId)}/void',
      method: 'POST',
      payload: {'reason': reason, 'branch_id': branchId},
    );
  }

  Future<void> deleteNotice(String transferId) async {
    await _call(
      'wasl/transfers/${Uri.encodeComponent(transferId)}?branch_id=${Uri.encodeQueryComponent(branchId)}',
      method: 'DELETE',
    );
  }

  Future<void> review({
    required String transferId,
    required String decision,
    required String reason,
  }) async {
    await _call(
      'wasl/transfers/${Uri.encodeComponent(transferId)}/review',
      method: 'POST',
      payload: {'decision': decision, 'reason': reason, 'branch_id': branchId},
    );
  }

  Future<Map<String, dynamic>> _call(
    String path, {
    String method = 'GET',
    Map<String, Object?>? payload,
  }) async {
    final response = await _transport.request(
      _uri.resolve(path),
      method: method,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: payload == null ? null : jsonEncode(payload),
    );
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      throw const WaslApiError('استجابة خادم التحويلات غير صالحة.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final serverMessage = data['message']?.toString();
      throw WaslApiError(
        response.statusCode == 401
            ? 'انتهت جلسة الدخول. سجل الخروج ثم ادخل مرة أخرى لتحديث الاتصال.'
            : (serverMessage == null || serverMessage == 'Unauthenticated.'
                  ? 'تعذر الاتصال بخدمة التحويلات (${response.statusCode}).'
                  : serverMessage),
        statusCode: response.statusCode,
      );
    }
    return data;
  }
}

class WaslApiError implements Exception {
  const WaslApiError(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// The SMS record is a *notice*, not confirmed settlement.
class WaslTransfer {
  const WaslTransfer({
    required this.id,
    required this.amount,
    required this.currency,
    required this.source,
    required this.receivedAt,
    required this.state,
    this.reference,
    this.body,
  });
  final String id;
  final String amount;
  final String currency;
  final String source;
  final String receivedAt;
  final String state;
  final String? reference;
  final String? body;

  factory WaslTransfer.fromJson(Map<String, dynamic> json) => WaslTransfer(
    id: json['id']?.toString() ?? '',
    amount: json['amount']?.toString() ?? '—',
    currency: json['currency']?.toString() ?? 'YER',
    source: json['source']?.toString() ?? 'محفظة',
    receivedAt: json['received_at']?.toString() ?? '',
    state: json['state']?.toString() ?? 'sms_received',
    reference: json['reference']?.toString(),
    body: json['body']?.toString(),
  );
}
