import 'dart:convert';

import '../../auth/json_transport.dart';

/// Only an acknowledged accounting service may change a physical stock balance.
/// Never send transfers or counts through generic business_documents.
class StockOperationsApi {
  StockOperationsApi({
    required this.token,
    JsonTransport? transport,
    String? baseUrl,
  }) : _transport = transport ?? createJsonTransport(),
       _base = Uri.parse(
         '${(baseUrl ?? const String.fromEnvironment('NINESOFT_API_BASE_URL', defaultValue: 'https://ninesoft.qodynex.tech/api/v1')).replaceFirst(RegExp(r'/+$'), '')}/',
       );

  final String token;
  final JsonTransport _transport;
  final Uri _base;

  Future<Map<String, dynamic>> post(Map<String, dynamic> immutableBody) async {
    final type = immutableBody['kind'];
    final product = immutableBody['product_id']?.toString() ?? '';
    final uri = switch (type) {
      'inventory_count' when product.isNotEmpty =>
        _base.resolve('catalog/products/${Uri.encodeComponent(product)}/stock'),
      'stock_transfer' => _base.resolve('accounting/stock-transfers'),
      _ => throw const FormatException('عملية مخزون غير صالحة'),
    };
    // `kind` is a queue-side discriminator, not a server schema field.
    final request = Map<String, dynamic>.from(immutableBody)..remove('kind');
    final response = await _transport.request(
      uri,
      method: type == 'inventory_count' ? 'PUT' : 'POST',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(request),
    );
    Map<String, dynamic> decoded;
    try {
      final json = jsonDecode(response.body);
      if (json is! Map) throw const FormatException('Invalid response');
      decoded = Map<String, dynamic>.from(json);
    } catch (_) {
      throw const FormatException('استجابة خادم المخزون غير صالحة.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(decoded['message']?.toString() ??
          'تعذر ترحيل حركة المخزون (${response.statusCode}).');
    }
    final result = decoded[type == 'inventory_count' ? 'stock' : 'transfer'];
    if (result is! Map ||
        result['operation_id']?.toString() !=
            (immutableBody['operation_id'] ?? immutableBody['local_operation_id']).toString()) {
      throw const FormatException('الخادم لم يؤكد معرّف حركة المخزون.');
    }
    return Map<String, dynamic>.from(result);
  }
}
