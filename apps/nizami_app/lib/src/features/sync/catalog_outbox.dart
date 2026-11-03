import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../modules/catalog_sync_api.dart';
import 'quarantined_operation_store.dart';

/// Durable retries for *explicitly saved* catalog edits. A failed network
/// response cannot silently drop a locally saved product or contact.
/// Entries are coalesced by entity+name; the server upserts by tenant/name.
class CatalogOutbox {
  CatalogOutbox(this.tenantId);

  final String tenantId;
  String get _key => 'ninesoft.catalog.outbox.v1.$tenantId';
  static final Map<String, Future<void>> _writers = {};
  static final Set<String> _flushing = {};

  static String _normalize(String text) => text.trim().toLowerCase();

  Future<T> _serial<T>(Future<T> Function() operation) async {
    final previous = _writers[_key] ?? Future<void>.value();
    final gate = Completer<void>();
    _writers[_key] = gate.future;
    await previous;
    try {
      return await operation();
    } finally {
      gate.complete();
      if (identical(_writers[_key], gate.future)) _writers.remove(_key);
    }
  }

  Future<List<Map<String, dynamic>>> _read() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Invalid catalog outbox');
    return decoded
        .whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
  }

  Future<void> _write(List<Map<String, dynamic>> items) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(items),
    );
    if (!saved) throw StateError('فشل تسجيل العملية للمزامنة اللاحقة.');
  }

  Future<void> enqueue(
    String entity,
    Map<String, dynamic> payload, {
    required int restoreGenerationAtCreation,
  }) => _serial(() async {
    if (!const {'products', 'customers', 'suppliers'}.contains(entity)) {
      throw ArgumentError.value(entity, 'entity');
    }
    final name = payload['name']?.toString().trim() ?? '';
    if (name.isEmpty) throw ArgumentError('اسم السجل فارغ.');
    final items = await _read();
    items.removeWhere(
      (item) =>
          item['entity'] == entity &&
          ((payload['id']?.toString().isNotEmpty == true &&
                  item['payload'] is Map &&
                  (item['payload'] as Map)['id']?.toString() ==
                      payload['id']?.toString()) ||
              _normalize(item['name']?.toString() ?? '') == _normalize(name)),
    );
    items.add({
      'op_id': const Uuid().v4(),
      'entity': entity,
      'name': name,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'restore_generation_at_creation': restoreGenerationAtCreation,
      'payload': payload,
    });
    await _write(items);
  });

  Future<void> discard(String entity, String name) => _serial(() async {
    final items = await _read();
    items.removeWhere(
      (item) =>
          item['entity'] == entity &&
          _normalize(item['name']?.toString() ?? '') == _normalize(name),
    );
    await _write(items);
  });

  /// Retry with the original operation. Deletion is intentionally not queued:
  /// deleting an accounting-linked contact/product requires server approval.
  Future<void> flush(
    CatalogSyncApi api, {
    DateTime? createdAfter,
    required int currentRestoreGeneration,
  }) async {
    if (!_flushing.add(_key)) return;
    try {
      final pending = await _serial(_read);
      for (final item in pending) {
        final operationId = item['op_id']?.toString() ?? '';
        final quarantine = QuarantinedOperationStore(tenantId);
        if (await quarantine.isDiscarded(operationId, 'catalog')) {
          continue;
        }
        final createdAt = DateTime.tryParse(
          item['created_at']?.toString() ?? '',
        );
        final operationGeneration =
            (item['restore_generation_at_creation'] as num?)?.toInt() ?? 0;
        if (operationGeneration != currentRestoreGeneration ||
            (createdAfter != null &&
                (createdAt == null || !createdAt.isAfter(createdAfter)))) {
          // Preserve pre-restore work for explicit user review. Never replay it
          // automatically over a restored accounting snapshot.
          await quarantine.quarantine(
            operationId: operationId,
            kind: 'catalog',
            reason: operationGeneration != currentRestoreGeneration
                ? 'restore_generation_at_creation_mismatch'
                : 'created_before_restore',
            payload: item,
          );
          continue;
        }
        final payload = item['payload'];
        if (payload is! Map) break;
        final data = Map<String, dynamic>.from(payload);
        try {
          switch (item['entity']) {
            case 'products':
              if ((data['id']?.toString() ?? '').isNotEmpty) {
                await api.updateProduct(
                  id: data['id'].toString(),
                  expectedVersion:
                      (data['expected_version'] as num?)?.toInt() ?? 1,
                  name: data['name']?.toString() ?? '',
                  barcode: data['barcode']?.toString() ?? '',
                  salePrice: (data['sale_price'] as num?)?.toDouble() ?? 0,
                  purchasePrice:
                      (data['purchase_price'] as num?)?.toDouble() ?? 0,
                );
                break;
              }
              await api.saveProduct(
                name: data['name']?.toString() ?? '',
                barcode: data['barcode']?.toString() ?? '',
                salePrice: (data['sale_price'] as num?)?.toDouble() ?? 0,
                purchasePrice:
                    (data['purchase_price'] as num?)?.toDouble() ?? 0,
              );
              break;
            case 'customers':
              if ((data['id']?.toString() ?? '').isNotEmpty) {
                await api.updateContact(
                  entity: 'customers',
                  id: data['id'].toString(),
                  expectedVersion:
                      (data['expected_version'] as num?)?.toInt() ?? 1,
                  name: data['name']?.toString() ?? '',
                  phone: data['phone']?.toString() ?? '',
                );
                break;
              }
              await api.saveCustomer(
                name: data['name']?.toString() ?? '',
                phone: data['phone']?.toString() ?? '',
              );
              break;
            case 'suppliers':
              if ((data['id']?.toString() ?? '').isNotEmpty) {
                await api.updateContact(
                  entity: 'suppliers',
                  id: data['id'].toString(),
                  expectedVersion:
                      (data['expected_version'] as num?)?.toInt() ?? 1,
                  name: data['name']?.toString() ?? '',
                  phone: data['phone']?.toString() ?? '',
                );
                break;
              }
              await api.saveSupplier(
                name: data['name']?.toString() ?? '',
                phone: data['phone']?.toString() ?? '',
              );
              break;
            default:
              return;
          }
        } catch (_) {
          // Stop at the failed item. Never falsely acknowledge unsent data.
          return;
        }
        // A later edit can supersede this entry during the network call;
        // acknowledge only the exact operation that was sent successfully.
        await _serial(() async {
          final items = await _read();
          items.removeWhere((current) => current['op_id'] == item['op_id']);
          await _write(items);
        });
      }
    } finally {
      _flushing.remove(_key);
    }
  }
}
