import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/json_transport.dart';

class ChartAccount {
  const ChartAccount({
    required this.id,
    required this.code,
    required this.nameAr,
    required this.type,
    required this.normalBalance,
    this.classification = '',
    this.closingStatement = '',
    required this.balanceMinor,
    this.parentId,
    this.nameEn = '',
    this.allowPosting = true,
    this.isSystem = false,
    this.active = true,
    this.sortOrder = 0,
    this.version = 1,
    this.cashFlowActivity,
    this.isCashEquivalent = false,
    this.settlementChannel = '',
  });
  final String id, code, nameAr, nameEn, type, normalBalance;
  final String classification, closingStatement;
  final String? cashFlowActivity;
  final String? parentId;
  final int balanceMinor;
  final bool allowPosting, isSystem, active, isCashEquivalent;
  final int sortOrder, version;
  final String settlementChannel;
  factory ChartAccount.fromJson(Map<String, dynamic> json) {
    final normal = json['normal_balance']?.toString() ?? 'debit';
    final debit = int.tryParse(json['debit_minor']?.toString() ?? '') ?? 0;
    final credit = int.tryParse(json['credit_minor']?.toString() ?? '') ?? 0;
    return ChartAccount(
      id: json['id'].toString(),
      code: json['code'].toString(),
      nameAr: json['name_ar'].toString(),
      nameEn: json['name_en']?.toString() ?? '',
      type: json['type'].toString(),
      normalBalance: normal,
      classification: json['classification']?.toString() ?? '',
      closingStatement: json['closing_statement']?.toString() ?? '',
      cashFlowActivity: json['cash_flow_activity']?.toString(),
      parentId: json['parent_id']?.toString(),
      balanceMinor: normal == 'debit' ? debit - credit : credit - debit,
      allowPosting: json['allow_posting'] == true || json['allow_posting'] == 1,
      isSystem: json['is_system'] == true || json['is_system'] == 1,
      active: json['active'] == true || json['active'] == 1,
      isCashEquivalent:
          json['is_cash_equivalent'] == true || json['is_cash_equivalent'] == 1,
      settlementChannel: _settlementChannelFor(json['code']?.toString() ?? ''),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name_ar': nameAr,
    'name_en': nameEn,
    'type': type,
    'normal_balance': normalBalance,
    'classification': classification,
    'closing_statement': closingStatement,
    'cash_flow_activity': cashFlowActivity,
    'parent_id': parentId,
    'debit_minor': normalBalance == 'debit'
        ? (balanceMinor >= 0 ? balanceMinor : 0)
        : (balanceMinor < 0 ? -balanceMinor : 0),
    'credit_minor': normalBalance == 'credit'
        ? (balanceMinor >= 0 ? balanceMinor : 0)
        : (balanceMinor < 0 ? -balanceMinor : 0),
    'allow_posting': allowPosting,
    'is_system': isSystem,
    'active': active,
    'is_cash_equivalent': isCashEquivalent,
    'sort_order': sortOrder,
    'version': version,
  };

  Map<String, dynamic> toSettlementChoiceJson() => {
    'id': id,
    'code': code,
    'name': nameAr,
    'channel': settlementChannel.isEmpty
        ? _settlementChannelFor(code)
        : settlementChannel,
    'version': version,
  };

  factory ChartAccount.fromSettlementChoiceJson(Map<String, dynamic> json) {
    const allowed = {'id', 'code', 'name', 'channel', 'version'};
    if (json.keys.any((key) => !allowed.contains(key)) ||
        json['id'] is! String ||
        (json['id'] as String).trim().isEmpty ||
        json['code'] is! String ||
        (json['code'] as String).trim().isEmpty ||
        json['name'] is! String ||
        (json['name'] as String).trim().isEmpty ||
        !const {'cash', 'bank', 'wallet'}.contains(json['channel']) ||
        json['version'] is! int ||
        (json['version'] as int) < 1) {
      throw const FormatException('Invalid cached settlement choice');
    }
    return ChartAccount(
      id: json['id'] as String,
      code: json['code'] as String,
      nameAr: json['name'] as String,
      type: '',
      normalBalance: '',
      balanceMinor: 0,
      version: json['version'] as int,
      settlementChannel: json['channel'] as String,
      allowPosting: true,
      active: true,
      isCashEquivalent: true,
    );
  }
}

String _settlementChannelFor(String code) {
  final upper = code.toUpperCase();
  if (upper.contains('WALLET')) return 'wallet';
  if (upper.contains('BANK')) return 'bank';
  return 'cash';
}

/// Durable read-through cache used by cashiers that may create invoices but
/// intentionally do not have permission to read the chart of accounts.
class ChartAccountCache {
  ChartAccountCache(
    this.tenantId,
    this.branchId, {
    required String sessionToken,
    required String roleCode,
    required Iterable<String> permissions,
  }) : _canCreate =
           roleCode == 'owner' || permissions.contains('invoices.create'),
       _canRefresh =
           roleCode == 'owner' ||
           (permissions.contains('invoices.create') &&
               permissions.contains('invoices.read')),
       _sessionFingerprint = _fingerprint(sessionToken, roleCode, permissions);

  final String tenantId;
  final String branchId;
  final bool _canCreate;
  final bool _canRefresh;
  final String _sessionFingerprint;

  String get _key => 'ninesoft.chart_accounts.v2.$tenantId.$branchId';
  String get _legacyKey => 'ninesoft.chart_accounts.v1.$tenantId.$branchId';

  static String _fingerprint(
    String token,
    String roleCode,
    Iterable<String> permissions,
  ) {
    final normalizedPermissions = permissions.toSet().toList()..sort();
    return sha256
        .convert(
          utf8.encode(jsonEncode([token, roleCode, normalizedPermissions])),
        )
        .toString();
  }

  Future<List<ChartAccount>> read() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_legacyKey);
    if (!_canCreate) {
      await preferences.remove(_key);
      return const [];
    }
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['schema'] != 1 ||
          decoded['session_fingerprint'] != _sessionFingerprint ||
          decoded['accounts'] is! List) {
        await preferences.remove(_key);
        return const [];
      }
      return (decoded['accounts'] as List)
          .map(
            (value) => ChartAccount.fromSettlementChoiceJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      await preferences.remove(_key);
      return const [];
    }
  }

  Future<void> replace(
    List<ChartAccount> accounts, {
    bool Function()? isValid,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_legacyKey);
    if (isValid != null && !isValid()) {
      throw StateError('Settlement choice write was invalidated');
    }
    if (!_canRefresh) {
      await preferences.remove(_key);
      throw StateError('Settlement choices require invoice create and read');
    }
    if (isValid != null && !isValid()) {
      throw StateError('Settlement choice write was invalidated');
    }
    final saved = await preferences.setString(
      _key,
      jsonEncode({
        'schema': 1,
        'session_fingerprint': _sessionFingerprint,
        'accounts': accounts
            .map((account) => account.toSettlementChoiceJson())
            .toList(),
      }),
    );
    if (!saved) throw StateError('Failed to cache chart accounts.');
  }
}

class ChartAccountsApi {
  ChartAccountsApi(this.token, {JsonTransport? transport})
    : _transport = transport ?? createJsonTransport();
  final String token;
  final JsonTransport _transport;
  final Uri _base = Uri.parse(
    '${const String.fromEnvironment('NINESOFT_API_BASE_URL', defaultValue: 'https://ninesoft.qodynex.tech/api/v1').replaceFirst(RegExp(r'/+$'), '')}/',
  );
  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };
  Future<List<ChartAccount>> list(String branchId) async {
    final r = await _transport.request(
      _base.resolve(
        'accounting/chart?branch_id=${Uri.encodeQueryComponent(branchId)}',
      ),
      method: 'GET',
      headers: _headers,
    );
    if (r.statusCode != 200) throw Exception(_message(r.body));
    return ((jsonDecode(r.body) as Map)['items'] as List)
        .map((e) => ChartAccount.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> create(String branchId, Map<String, Object?> data) async {
    final r = await _transport.request(
      _base.resolve('accounting/chart'),
      method: 'POST',
      headers: _headers,
      body: jsonEncode({...data, 'branch_id': branchId}),
    );
    if (r.statusCode != 201) throw Exception(_message(r.body));
  }

  Future<void> update(
    String branchId,
    String id,
    Map<String, Object?> data,
  ) async {
    final r = await _transport.request(
      _base.resolve('accounting/chart/$id'),
      method: 'PUT',
      headers: _headers,
      body: jsonEncode({...data, 'branch_id': branchId}),
    );
    if (r.statusCode != 200) throw Exception(_message(r.body));
  }

  Future<void> delete(String branchId, String id) async {
    final r = await _transport.request(
      _base.resolve(
        'accounting/chart/$id?branch_id=${Uri.encodeQueryComponent(branchId)}',
      ),
      method: 'DELETE',
      headers: _headers,
    );
    if (r.statusCode != 200) throw Exception(_message(r.body));
  }

  String _message(String body) {
    try {
      return (jsonDecode(body) as Map)['message']?.toString() ??
          'تعذر تنفيذ العملية.';
    } catch (_) {
      return 'تعذر الاتصال بالخادم.';
    }
  }
}
