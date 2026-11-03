import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Read-only supplier and product directory snapshots for preparing a purchase
/// while offline. Canonical stock/ledger effects always originate on server.
/// Tenant AND branch scoping prevents one company's records leaking to another.
class PurchaseReferenceCache {
  PurchaseReferenceCache(this.tenantId, this.branchId);

  final String tenantId;
  final String branchId;
  String _key(String type) =>
      'ninesoft.purchase.references.v1.$tenantId.$branchId.$type';

  Future<List<Map<String, dynamic>>> read(String type) async {
    if (!const {'suppliers', 'products', 'cash_accounts'}.contains(type)) {
      throw ArgumentError('Unsupported purchase reference type');
    }
    final raw = (await SharedPreferences.getInstance()).getString(_key(type));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final value = jsonDecode(raw);
      if (value is! List) return const [];
      return value.whereType<Map>().map((row) =>
          Map<String, dynamic>.from(row)).toList(growable: false);
    } catch (_) {
      return const []; // Do not overwrite a damaged cache on read.
    }
  }

  Future<void> write(String type, List<Map<String, dynamic>> rows) async {
    if (!const {'suppliers', 'products', 'cash_accounts'}.contains(type)) {
      throw ArgumentError('Unsupported purchase reference type');
    }
    final data = jsonEncode(rows);
    final saved = await (await SharedPreferences.getInstance())
        .setString(_key(type), data);
    if (!saved) throw StateError('تعذر تخزين مرجع الشراء محليًا.');
  }
}
