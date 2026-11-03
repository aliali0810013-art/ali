import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A dedicated cache for posted purchase invoices. Purchase deltas must never
/// enter the sales [InvoiceHistoryStore].
class PurchaseInvoiceStore {
  static final Map<String, Future<void>> _writers = {};

  static String _key(String tenant, String branch) =>
      'ninesoft.purchases.v1.$tenant.$branch';

  static Future<T> _serial<T>(String key, Future<T> Function() action) async {
    final previous = _writers[key] ?? Future<void>.value();
    final gate = Completer<void>();
    _writers[key] = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
      if (identical(_writers[key], gate.future)) _writers.remove(key);
    }
  }

  Future<List<Map<String, dynamic>>> read(String tenant, String branch) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _key(tenant, branch),
    );
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _readForWrite(
    String tenant,
    String branch,
  ) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _key(tenant, branch),
    );
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.any((value) => value is! Map)) {
        throw const FormatException('Purchase cache is not an invoice list');
      }
      return decoded
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
    } catch (failure) {
      throw PurchaseInvoiceCacheCorrupted(failure);
    }
  }

  Future<void> save(
    String tenant,
    String branch,
    Map<String, dynamic> invoice, {
    bool Function()? isValid,
  }) => _serial(_key(tenant, branch), () async {
    if (invoice['type']?.toString() != 'purchase') {
      throw ArgumentError('Only purchase invoices belong in this store');
    }
    final id = invoice['id']?.toString() ?? '';
    if (id.isEmpty) throw ArgumentError('Purchase invoice ID is required');
    if (isValid != null && !isValid()) {
      throw const PurchaseInvoiceWriteInvalidated();
    }
    final invoices = await _readForWrite(tenant, branch)
      ..removeWhere((item) => item['id']?.toString() == id)
      ..insert(0, invoice);
    if (isValid != null && !isValid()) {
      throw const PurchaseInvoiceWriteInvalidated();
    }
    await _write(tenant, branch, invoices);
  });

  Future<void> remove(String tenant, String branch, String id) =>
      _serial(_key(tenant, branch), () async {
        final invoices = (await read(tenant, branch)).toList()
          ..removeWhere((item) => item['id']?.toString() == id);
        await _write(tenant, branch, invoices);
      });

  Future<void> replaceRemoteSnapshot(
    String tenant,
    String branch,
    Iterable<Map<String, dynamic>> remote,
  ) => _serial(_key(tenant, branch), () async {
    final purchases = remote
        .where((item) => item['type']?.toString() == 'purchase')
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    await _write(tenant, branch, purchases);
  });

  Future<void> _write(
    String tenant,
    String branch,
    List<Map<String, dynamic>> invoices,
  ) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      _key(tenant, branch),
      jsonEncode(invoices),
    );
    if (!saved) throw StateError('Unable to persist purchase invoice cache');
  }
}

class PurchaseInvoiceWriteInvalidated implements Exception {
  const PurchaseInvoiceWriteInvalidated();
}

class PurchaseInvoiceCacheCorrupted implements Exception {
  const PurchaseInvoiceCacheCorrupted(this.cause);

  final Object cause;

  @override
  String toString() => 'Purchase invoice cache is corrupted: $cause';
}
