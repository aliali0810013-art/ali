import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

enum SettlementOperationKind { customerReceipt, supplierPayment }

String canonicalSettlementReason(SettlementOperationKind kind, String reason) {
  final normalized = reason.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length >= 8) return normalized;
  return kind == SettlementOperationKind.customerReceipt
      ? 'سند قبض معتمد من المستخدم'
      : 'سند صرف معتمد للمورد';
}

class SettlementIdempotencyClaim {
  const SettlementIdempotencyClaim({
    required this.fingerprint,
    required this.idempotencyKey,
  });

  final String fingerprint;
  final String idempotencyKey;
}

/// Keeps a settlement request's idempotency key durable until the caller has
/// both received the canonical server response and persisted/refreshed its
/// local state. A lost HTTP response therefore retries with the same key.
class SettlementIdempotencyStore {
  SettlementIdempotencyStore({
    required this.tenantScope,
    required this.branchId,
  });

  static const _storageKey =
      'ninesoft.accounting.pending_settlement_idempotency.v1';
  static Future<void> _serializationTail = Future<void>.value();

  final String tenantScope;
  final String branchId;

  Future<SettlementIdempotencyClaim> claim({
    required SettlementOperationKind kind,
    required String invoiceId,
    required int amountMinor,
    required String currency,
    required String channel,
    String accountCode = '',
    required String reason,
  }) {
    final fingerprint = _fingerprint(
      kind: kind,
      invoiceId: invoiceId,
      amountMinor: amountMinor,
      currency: currency,
      channel: channel,
      accountCode: accountCode,
      reason: reason,
    );
    return _serialized(() async {
      final preferences = await SharedPreferences.getInstance();
      final pending = _readPending(preferences);
      final existing = pending[fingerprint];
      if (existing is Map) {
        final key = existing['idempotency_key']?.toString().trim() ?? '';
        if (key.isNotEmpty) {
          return SettlementIdempotencyClaim(
            fingerprint: fingerprint,
            idempotencyKey: key,
          );
        }
      } else if (existing is String && existing.trim().isNotEmpty) {
        // Accept the compact shape if an earlier build wrote it.
        return SettlementIdempotencyClaim(
          fingerprint: fingerprint,
          idempotencyKey: existing.trim(),
        );
      }

      final idempotencyKey = const Uuid().v4();
      pending[fingerprint] = <String, Object?>{
        'idempotency_key': idempotencyKey,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      final saved = await preferences.setString(
        _storageKey,
        jsonEncode(pending),
      );
      if (!saved) {
        throw StateError('تعذر حفظ معرّف إعادة المحاولة للسند.');
      }
      return SettlementIdempotencyClaim(
        fingerprint: fingerprint,
        idempotencyKey: idempotencyKey,
      );
    });
  }

  Future<void> acknowledge(SettlementIdempotencyClaim claim) =>
      _serialized(() async {
        final preferences = await SharedPreferences.getInstance();
        final pending = _readPending(preferences);
        final current = pending[claim.fingerprint];
        final currentKey = current is Map
            ? current['idempotency_key']?.toString()
            : current?.toString();
        if (currentKey != claim.idempotencyKey) return;
        pending.remove(claim.fingerprint);
        final saved = pending.isEmpty
            ? await preferences.remove(_storageKey)
            : await preferences.setString(_storageKey, jsonEncode(pending));
        if (!saved) {
          throw StateError('تعذر تأكيد إغلاق معرّف إعادة المحاولة للسند.');
        }
      });

  String _fingerprint({
    required SettlementOperationKind kind,
    required String invoiceId,
    required int amountMinor,
    required String currency,
    required String channel,
    String accountCode = '',
    required String reason,
  }) {
    final canonicalPayload = jsonEncode(<String, Object?>{
      'tenant_scope': tenantScope.trim(),
      'branch_id': branchId.trim(),
      'kind': kind.name,
      'invoice_id': invoiceId.trim(),
      'amount_minor': amountMinor,
      'currency': currency.trim().toUpperCase(),
      'channel': channel.trim().toLowerCase(),
      'account_code': accountCode.trim().toUpperCase(),
      'reason': canonicalSettlementReason(kind, reason),
    });
    return sha256.convert(utf8.encode(canonicalPayload)).toString();
  }

  static Map<String, dynamic> _readPending(SharedPreferences preferences) {
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      // Never reuse a malformed key for a financial request. Retain no
      // in-memory guess; the next claim writes a fresh, valid durable map.
      return <String, dynamic>{};
    }
  }

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _serializationTail = _serializationTail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
