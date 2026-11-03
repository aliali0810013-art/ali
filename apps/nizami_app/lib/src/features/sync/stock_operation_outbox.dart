import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../inventory/stock_operations_api.dart';
import 'quarantined_operation_store.dart';

/// FIFO accounting outbox: identical retries keep the SAME operation ID and
/// body. SharedPreferences is a compatibility layer, not a transactional DB.
class StockOperationOutbox {
  StockOperationOutbox(this.tenantId, this.branchId);

  final String tenantId;
  final String branchId;
  String get _key => 'ninesoft.stock.operations.v1.$tenantId.$branchId';
  static final Map<String, Future<void>> _writers = {};
  static final Set<String> _flushing = {};

  Future<T> _serial<T>(Future<T> Function() callback) async {
    final previous = _writers[_key] ?? Future<void>.value();
    final gate = Completer<void>();
    _writers[_key] = gate.future;
    await previous;
    try {
      return await callback();
    } finally {
      gate.complete();
      if (identical(_writers[_key], gate.future)) _writers.remove(_key);
    }
  }

  Future<List<Map<String, dynamic>>> list() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Stock outbox corrupted');
    return decoded
        .map((item) {
          if (item is! Map) throw const FormatException('Invalid stock entry');
          return Map<String, dynamic>.from(item);
          // Flush removes acknowledged or explicitly discarded entries in place.
          // A fixed-length decoded list made successful server posts look failed and
          // left them queued for duplicate retries.
        })
        .toList(growable: true);
  }

  Future<int> count() async => (await list()).length;

  Future<void> _save(List<Map<String, dynamic>> entries) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(entries),
    )) {
      throw StateError('تعذر حفظ عملية المخزون المعلقة.');
    }
  }

  Future<void> enqueue(Map<String, dynamic> request) => _serial(() async {
    final operationId = _operationId(request);
    final source = request['branch_id'] ?? request['source_branch_id'];
    if (source != branchId ||
        operationId.isEmpty ||
        request['operation_created_at'] == null ||
        request['restore_generation'] is! int ||
        !const {
          'inventory_count',
          'stock_transfer',
        }.contains(request['kind'])) {
      throw ArgumentError('عملية جرد أو تحويل ناقصة.');
    }
    final queue = await list();
    for (final original in queue) {
      if (_operationId(original) != operationId) continue;
      if (jsonEncode(original) != jsonEncode(request)) {
        throw StateError('معرف حركة المخزون مستخدم ببيانات أخرى.');
      }
      return;
    }
    queue.add(Map<String, dynamic>.from(request));
    await _save(queue);
  });

  static String _operationId(Map<String, dynamic> request) =>
      (request['operation_id'] ?? request['local_operation_id'])?.toString() ??
      '';

  Future<StockFlushResult> flush({
    required StockOperationsApi api,
    required int currentRestoreGeneration,
    DateTime? restoreEpoch,
    int maxPerCycle = 3,
  }) async {
    if (!_flushing.add(_key)) return const StockFlushResult();
    var sent = 0;
    var quarantined = 0;
    String? lastError;
    try {
      for (final body in await list()) {
        if (sent >= maxPerCycle) break;
        final request = Map<String, dynamic>.from(body);
        final id = _operationId(request);
        final timestamp = DateTime.tryParse(
          request['operation_created_at']?.toString() ?? '',
        )?.toUtc();
        final generation = (request['restore_generation'] as num?)?.toInt();
        final invalid =
            generation != currentRestoreGeneration ||
            timestamp == null ||
            (restoreEpoch != null && !timestamp.isAfter(restoreEpoch.toUtc()));
        if (await QuarantinedOperationStore(
          tenantId,
        ).isDiscarded(id, 'stock_operation')) {
          // The owner explicitly discarded this stale operation after review.
          // Keep that decision in the quarantine audit; remove only its outbox
          // copy so it cannot block newer stock operations forever.
          await _serial(() async {
            final pending = await list();
            pending.removeWhere((item) => _operationId(item) == id);
            await _save(pending);
          });
          quarantined++;
          continue;
        }
        if (invalid) {
          await QuarantinedOperationStore(tenantId).quarantine(
            operationId: id,
            kind: 'stock_operation',
            reason: generation != currentRestoreGeneration
                ? 'restore_generation_mismatch'
                : 'created_before_restore',
            payload: request,
          );
          quarantined++;
          // Never skip ahead past a quarantined stock balance dependency.
          break;
        }
        try {
          await api.post(request);
          await _serial(() async {
            final pending = await list();
            pending.removeWhere((item) => _operationId(item) == id);
            await _save(pending);
          });
          sent++;
        } catch (error) {
          lastError = error.toString();
          // A stale stock snapshot needs explicit human review, not repeated
          // blind posting. Preserve the immutable request in the outbox AND
          // quarantine it until an authorized reviewer resolves the conflict.
          if (lastError.contains('RESTORE_GENERATION_') ||
              lastError.contains('OPERATION_CREATED_BEFORE_RESTORE') ||
              lastError.contains('INVENTORY_BALANCE_CONFLICT') ||
              lastError.contains('STOCK_TRANSFER_OPERATION_CONFLICT') ||
              lastError.contains('INVENTORY_OPERATION_CONFLICT')) {
            await QuarantinedOperationStore(tenantId).quarantine(
              operationId: id,
              kind: 'stock_operation',
              reason: lastError,
              payload: request,
            );
            quarantined++;
          }
          break; // Retry unchanged, never let later stock commands overtake.
        }
      }
    } finally {
      _flushing.remove(_key);
    }
    return StockFlushResult(
      sent: sent,
      quarantined: quarantined,
      error: lastError,
    );
  }
}

class StockFlushResult {
  const StockFlushResult({this.sent = 0, this.quarantined = 0, this.error});
  final int sent;
  final int quarantined;
  final String? error;
}
