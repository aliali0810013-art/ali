import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Durable review queue. Restore-conflicting financial writes are never
/// deleted and never replayed until an authorized user explicitly resolves
/// them.
class QuarantinedOperationStore {
  QuarantinedOperationStore(this.tenantId);
  final String tenantId;
  String get _key => 'ninesoft.financial.quarantine.v1.$tenantId';
  String get _auditKey => 'ninesoft.financial.quarantine.audit.v1.$tenantId';
  String get _decisionsKey =>
      'ninesoft.financial.quarantine.decisions.v1.$tenantId';
  static final Map<String, Future<void>> _writers = {};

  Future<T> _serial<T>(Future<T> Function() work) async {
    final previous = _writers[_key] ?? Future<void>.value();
    final gate = Completer<void>();
    _writers[_key] = gate.future;
    await previous;
    try {
      return await work();
    } finally {
      gate.complete();
      if (identical(_writers[_key], gate.future)) _writers.remove(_key);
    }
  }

  Future<List<Map<String, dynamic>>> list() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final value = jsonDecode(raw);
    return value is List
        ? value
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : [];
  }

  Future<void> quarantine({
    required String operationId,
    required String kind,
    required String reason,
    required Map<String, dynamic> payload,
  }) => _serial(() async {
    if (await isDiscarded(operationId, kind)) return;
    final items = (await list()).toList();
    if (items.any(
      (item) => item['operation_id'] == operationId && item['kind'] == kind,
    )) {
      return;
    }
    items.add({
      'operation_id': operationId,
      'kind': kind,
      'reason': reason,
      'payload': payload,
      'quarantined_at': DateTime.now().toUtc().toIso8601String(),
    });
    final saved = await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(items),
    );
    if (!saved) throw StateError('Unable to persist financial quarantine');
  });

  Future<void> remove(String operationId) => _serial(() async {
    final items = (await list()).toList()
      ..removeWhere((item) => item['operation_id'] == operationId);
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(items),
    );
  });

  Future<List<Map<String, dynamic>>> auditLog() async {
    final raw = (await SharedPreferences.getInstance()).getString(_auditKey);
    if (raw == null || raw.isEmpty) return [];
    final value = jsonDecode(raw);
    return value is List
        ? value
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : [];
  }

  Future<List<Map<String, dynamic>>> decisions() async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _decisionsKey,
    );
    if (raw == null || raw.isEmpty) return const [];
    final value = jsonDecode(raw);
    return value is List
        ? value
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : const [];
  }

  Future<bool> isDiscarded(String operationId, String kind) async =>
      (await decisions()).any(
        (item) =>
            item['operation_id'] == operationId &&
            item['kind'] == kind &&
            item['decision'] == 'discard',
      );

  /// Resolves a quarantined operation without ever reposting it. Accounting
  /// corrections must be entered as a new, separately identified operation.
  Future<void> resolve({
    required String operationId,
    required String decision,
    required String reviewer,
    String note = '',
  }) => _serial(() async {
    if (!const {'discard', 'keep'}.contains(decision)) {
      throw ArgumentError.value(decision, 'decision');
    }
    final items = (await list()).toList();
    final index = items.indexWhere(
      (item) => item['operation_id'] == operationId,
    );
    if (index < 0) throw StateError('Quarantined operation not found');
    final item = items[index];
    final reviewedAt = DateTime.now().toUtc().toIso8601String();
    final audit = (await auditLog()).toList()
      ..add({
        'operation_id': operationId,
        'kind': item['kind'],
        'reason': item['reason'],
        'decision': decision,
        'reviewer': reviewer,
        'note': note,
        'reviewed_at': reviewedAt,
        'payload': item['payload'],
      });
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_auditKey, jsonEncode(audit))) {
      throw StateError('Unable to persist quarantine audit');
    }
    if (decision == 'discard') {
      final terminal = (await decisions()).toList()
        ..removeWhere(
          (entry) =>
              entry['operation_id'] == operationId &&
              entry['kind'] == item['kind'],
        )
        ..add({
          'operation_id': operationId,
          'kind': item['kind'],
          'reason': item['reason'],
          'decision': decision,
          'reviewer': reviewer,
          'note': note,
          'reviewed_at': reviewedAt,
          'payload': item['payload'],
        });
      if (!await prefs.setString(_decisionsKey, jsonEncode(terminal))) {
        throw StateError('Unable to persist terminal quarantine decision');
      }
      items.removeAt(index);
      if (!await prefs.setString(_key, jsonEncode(items))) {
        throw StateError('Unable to persist quarantine resolution');
      }
    }
  });
}
