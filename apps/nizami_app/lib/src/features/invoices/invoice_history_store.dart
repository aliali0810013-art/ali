import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'invoice_pdf_service.dart';

class InvoiceHistoryStore {
  static final Map<String, Future<void>> _writers = {};

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

  static String _key(String tenant, String branch) =>
      'ninesoft.invoices.v1.$tenant.$branch';

  Future<List<InvoiceDocument>> read(String tenant, String branch) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _key(tenant, branch),
    );
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map(
            (value) =>
                InvoiceDocument.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(
    String tenant,
    String branch,
    InvoiceDocument invoice, {
    bool Function()? isValid,
  }) => _serial(_key(tenant, branch), () async {
    final invoices = await read(tenant, branch);
    if (isValid != null && !isValid()) {
      throw const InvoiceHistoryWriteInvalidated();
    }
    invoices.removeWhere(
      (item) =>
          item.number == invoice.number ||
          (invoice.localOperationId.isNotEmpty &&
              item.localOperationId == invoice.localOperationId) ||
          (invoice.serverInvoiceId.isNotEmpty &&
              item.serverInvoiceId == invoice.serverInvoiceId),
    );
    invoices.insert(0, invoice);
    final saved = await (await SharedPreferences.getInstance()).setString(
      _key(tenant, branch),
      jsonEncode(invoices.map((item) => item.toJson()).toList()),
    );
    if (!saved) throw StateError('Failed to persist invoice history.');
  });

  /// Persists the terminal restore-boundary state before an outbox row is
  /// removed. This keeps a quarantined financial operation visible and locked
  /// after an application restart instead of making it look like a draft.
  Future<bool> markQuarantined(
    String tenant,
    String branch,
    String operationId,
    String reason, {
    InvoiceDocument? fallback,
    bool Function()? isValid,
  }) => _serial(_key(tenant, branch), () async {
    final invoices = await read(tenant, branch);
    if (isValid != null && !isValid()) {
      throw const InvoiceHistoryWriteInvalidated();
    }
    final index = invoices.indexWhere(
      (item) => item.localOperationId == operationId,
    );
    final source = index < 0 ? fallback : invoices[index];
    if (source == null) return false;
    final quarantined = source.quarantined(reason);
    if (index < 0) {
      invoices.insert(0, quarantined);
    } else {
      invoices[index] = quarantined;
    }
    final saved = await (await SharedPreferences.getInstance()).setString(
      _key(tenant, branch),
      jsonEncode(invoices.map((item) => item.toJson()).toList()),
    );
    if (!saved) throw StateError('Failed to persist invoice quarantine.');
    return true;
  });

  /// Reconcile a COMPLETE server invoice snapshot in one local write.
  /// Pending offline drafts are retained; server records replace duplicates
  /// by the immutable local operation ID. Called only after all pages load.
  Future<void> replaceRemoteSnapshot(
    String tenant,
    String branch,
    List<InvoiceDocument> remote,
  ) => _serial(_key(tenant, branch), () async {
    final local = await read(tenant, branch);
    final byOperation = <String, InvoiceDocument>{};
    String identity(InvoiceDocument invoice) {
      if (invoice.localOperationId.isNotEmpty) {
        return 'operation:${invoice.localOperationId}';
      }
      if (invoice.serverInvoiceId.isNotEmpty) {
        return 'server:${invoice.serverInvoiceId}';
      }
      return 'number:${invoice.number}';
    }

    for (final document in local.where((doc) => !doc.postedToServer)) {
      byOperation[identity(document)] = document;
    }
    for (final document in remote) {
      byOperation[identity(document)] = document;
    }
    final merged = byOperation.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final saved = await (await SharedPreferences.getInstance()).setString(
      _key(tenant, branch),
      jsonEncode(merged.map((item) => item.toJson()).toList()),
    );
    if (!saved) throw StateError('فشل حفظ سجل الفواتير المزامن.');
  });

  Future<void> remove(String tenant, String branch, String number) =>
      _serial(_key(tenant, branch), () async {
        final invoices = await read(tenant, branch);
        invoices.removeWhere((item) => item.number == number);
        await (await SharedPreferences.getInstance()).setString(
          _key(tenant, branch),
          jsonEncode(invoices.map((item) => item.toJson()).toList()),
        );
      });

  Future<void> removeServerId(String tenant, String branch, String id) =>
      _serial(_key(tenant, branch), () async {
        final invoices = await read(tenant, branch)
          ..removeWhere((item) => item.serverInvoiceId == id);
        await (await SharedPreferences.getInstance()).setString(
          _key(tenant, branch),
          jsonEncode(invoices.map((item) => item.toJson()).toList()),
        );
      });
}

class InvoiceHistoryWriteInvalidated implements Exception {
  const InvoiceHistoryWriteInvalidated();
}
