import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SavedCustomer {
  const SavedCustomer({
    this.id = '',
    required this.name,
    required this.phone,
    required this.updatedAt,
    this.version = 1,
  });

  final String id;
  final String name;
  final String phone;
  final DateTime updatedAt;
  final int version;

  factory SavedCustomer.fromJson(Map<String, dynamic> v) => SavedCustomer(
    id: v['id']?.toString() ?? '',
    name: v['name']?.toString() ?? '',
    phone: v['phone']?.toString() ?? '',
    updatedAt:
        DateTime.tryParse(v['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    version: (v['version'] as num?)?.toInt() ?? 1,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'updatedAt': updatedAt.toIso8601String(),
    'version': version,
  };
}

/// Tenant-scoped local customer cache. The server's contact ID is canonical.
class CustomerStore {
  CustomerStore(this.tenant);
  final String tenant;
  String get _key => 'ninesoft.customers.v2.$tenant';
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

  static String _keyName(String name) => name.trim().toLowerCase();

  Future<List<SavedCustomer>> read() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map(
            (value) => SavedCustomer.fromJson(Map<String, dynamic>.from(value)),
          )
          .where((v) => v.name.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<SavedCustomer> customers) async {
    final success = await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(customers.map((v) => v.toJson()).toList()),
    );
    if (!success) throw StateError('تعذر حفظ العملاء محليًا.');
  }

  static List<SavedCustomer> _unique(Iterable<SavedCustomer> source) {
    final output = <SavedCustomer>[];
    for (final item in source) {
      output.removeWhere(
        (other) =>
            (item.id.isNotEmpty && other.id == item.id) ||
            _keyName(other.name) == _keyName(item.name),
      );
      output.add(item);
    }
    return output;
  }

  Future<void> save(String name, String phone) => _serial(() async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    final entries = await read();
    final existing = entries.where(
      (v) => _keyName(v.name) == _keyName(cleanName),
    );
    final previousId = existing.isEmpty ? '' : existing.first.id;
    await _write(
      _unique([
        ...entries,
        SavedCustomer(
          id: previousId,
          name: cleanName,
          phone: phone.trim(),
          updatedAt: DateTime.now(),
          version: existing.isEmpty ? 1 : existing.first.version,
        ),
      ]),
    );
  });

  Future<void> replaceRemoteSnapshot(Iterable<Map<String, dynamic>> contacts) =>
      _serial(() async {
        final offline = (await read()).where((c) => c.id.isEmpty);
        final remote = contacts
            .where(
              (v) => const [
                'customer',
                'both',
              ].contains(v['type']?.toString() ?? 'customer'),
            )
            .map(
              (v) => SavedCustomer(
                id: v['id']?.toString() ?? '',
                name: v['name']?.toString() ?? '',
                phone: v['phone']?.toString() ?? '',
                updatedAt:
                    DateTime.tryParse(v['updated_at']?.toString() ?? '') ??
                    DateTime.now(),
                version: (v['version'] as num?)?.toInt() ?? 1,
              ),
            );
        await _write(_unique([...offline, ...remote]));
      });

  Future<void> applyRemoteChange(
    String id,
    String operation,
    Map<String, dynamic> payload,
  ) => _serial(() async {
    final existing = await read();
    existing.removeWhere((c) => c.id == id);
    if (operation != 'delete' &&
        const ['customer', 'both'].contains(payload['type'])) {
      final name = payload['name']?.toString() ?? '';
      if (name.trim().isNotEmpty) {
        await _write(
          _unique([
            ...existing,
            SavedCustomer(
              id: id,
              name: name,
              phone: payload['phone']?.toString() ?? '',
              updatedAt: DateTime.now(),
              version: (payload['version'] as num?)?.toInt() ?? 1,
            ),
          ]),
        );
        return;
      }
    }
    await _write(existing);
  });

  Future<void> remove(String name) => _serial(() async {
    final list = await read();
    list.removeWhere((c) => _keyName(c.name) == _keyName(name));
    await _write(list);
  });
}
