import 'dart:convert';

import '../../auth/json_transport.dart';
import '../../settings/business_identity_store.dart';

class IdentityApi {
  IdentityApi({required this.token, JsonTransport? transport})
    : _transport = transport ?? createJsonTransport(),
      _base = Uri.parse(
        '${const String.fromEnvironment('NINESOFT_API_BASE_URL', defaultValue: 'https://ninesoft.qodynex.tech/api/v1').replaceFirst(RegExp(r'/+$'), '')}/',
      );
  final String token;
  final JsonTransport _transport;
  final Uri _base;

  Future<BranchBusinessProfile> load(
    String branchId,
    String tenantScope,
  ) async {
    final data = await _request('branches/$branchId/identity', 'GET');
    return BranchBusinessProfile.fromJson({
      'tenantScope': tenantScope,
      'branchId': branchId,
      'businessName': data['business_name'],
      'businessNameEn': data['business_name_en'],
      'tagline': data['business_tagline'],
      'phone': data['phone'],
      'address': data['address'],
      'email': data['email'],
      'header': data['invoice_header'],
      'footer': data['invoice_footer'],
      'primaryColorValue': data['primary_color'],
      'logoScale': data['logo_scale'],
      'logo': data['logo_base64'],
    });
  }

  Future<void> save(BranchBusinessProfile profile) =>
      _request('branches/${profile.branchId}/identity', 'PUT', {
        'business_name': profile.businessName,
        'business_name_en': profile.businessNameEn,
        'business_tagline': profile.tagline,
        'phone': profile.phone,
        'address': profile.address,
        'email': profile.email,
        'invoice_header': profile.header,
        'invoice_footer': profile.footer,
        'primary_color': profile.primaryColorValue,
        'logo_scale': profile.logoScale,
        'logo_base64': profile.logoBytes == null
            ? null
            : base64Encode(profile.logoBytes!),
      });

  Future<Map<String, dynamic>> _request(
    String path,
    String method, [
    Map<String, Object?>? body,
  ]) async {
    final response = await _transport.request(
      _base.resolve(path),
      method: method,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $token',
      },
      body: body == null ? null : jsonEncode(body),
    );
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    final map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(map['message'] ?? 'تعذرت مزامنة هوية الفرع.');
    }
    return map['data'] is Map
        ? Map<String, dynamic>.from(map['data'] as Map)
        : map;
  }
}
