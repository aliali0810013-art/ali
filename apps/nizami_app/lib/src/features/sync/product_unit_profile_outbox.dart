import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../modules/catalog_sync_api.dart';
import '../products/product_sale_option_store.dart';
import 'quarantined_operation_store.dart';

enum ProductUnitProfileState { queued, needsReview }

class ProductUnitProfileEntry {
  const ProductUnitProfileEntry({
    required this.localProductKey,
    required this.productId,
    required this.operationId,
    required this.restoreGeneration,
    required this.operationCreatedAt,
    required this.requestBody,
    this.state = ProductUnitProfileState.queued,
    this.rejectionStatus,
    this.rejectionMessage,
  });

  final String localProductKey;
  final String productId;
  final String operationId;
  final int restoreGeneration;
  final DateTime operationCreatedAt;
  final String requestBody;
  final ProductUnitProfileState state;
  final int? rejectionStatus;
  final String? rejectionMessage;

  bool get awaitingCanonicalProduct => productId.isEmpty;

  /// A local stock draft is not a service. It remains blocked until catalog
  /// synchronization supplies the canonical product ID.
  bool get canCreateServerStockLine => productId.isNotEmpty;

  factory ProductUnitProfileEntry.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(
      json['operation_created_at']?.toString() ?? '',
    )?.toUtc();
    if (createdAt == null) {
      throw const FormatException('Invalid unit profile creation time');
    }
    final rawGeneration = json['restore_generation'];
    if (rawGeneration is! int || rawGeneration < 0) {
      throw const FormatException('Invalid unit profile restore generation');
    }
    final rawState = json['state']?.toString() ?? 'queued';
    final state = switch (rawState) {
      'queued' => ProductUnitProfileState.queued,
      'needs_review' => ProductUnitProfileState.needsReview,
      _ => throw const FormatException('Invalid unit profile state'),
    };
    final rawStatus = json['rejection_status'];
    if (rawStatus != null && rawStatus is! int) {
      throw const FormatException('Invalid unit profile rejection status');
    }
    final entry = ProductUnitProfileEntry(
      localProductKey: json['local_product_key']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      operationId: json['operation_id']?.toString() ?? '',
      restoreGeneration: rawGeneration,
      operationCreatedAt: createdAt,
      requestBody: json['request_body']?.toString() ?? '',
      state: state,
      rejectionStatus: rawStatus as int?,
      rejectionMessage: json['rejection_message']?.toString(),
    );
    if (entry.localProductKey.isEmpty ||
        entry.operationId.isEmpty ||
        entry.requestBody.isEmpty) {
      throw const FormatException('Invalid pending unit profile');
    }
    final decoded = jsonDecode(entry.requestBody);
    if (decoded is! Map ||
        decoded['client_operation_id'] is! String ||
        decoded['client_operation_id'] != entry.operationId) {
      throw const FormatException('Unit profile operation body mismatch');
    }
    return entry;
  }

  Map<String, dynamic> toJson() => {
    'local_product_key': localProductKey,
    'product_id': productId,
    'operation_id': operationId,
    'restore_generation': restoreGeneration,
    'operation_created_at': operationCreatedAt.toUtc().toIso8601String(),
    'request_body': requestBody,
    'state': state == ProductUnitProfileState.queued
        ? 'queued'
        : 'needs_review',
    if (rejectionStatus != null) 'rejection_status': rejectionStatus,
    if (rejectionMessage != null) 'rejection_message': rejectionMessage,
  };

  ProductUnitProfileEntry attach(String canonicalProductId) =>
      ProductUnitProfileEntry(
        localProductKey: localProductKey,
        productId: canonicalProductId,
        operationId: operationId,
        restoreGeneration: restoreGeneration,
        operationCreatedAt: operationCreatedAt,
        requestBody: requestBody,
      );

  ProductUnitProfileEntry reject(CatalogApiException error) =>
      ProductUnitProfileEntry(
        localProductKey: localProductKey,
        productId: productId,
        operationId: operationId,
        restoreGeneration: restoreGeneration,
        operationCreatedAt: operationCreatedAt,
        requestBody: requestBody,
        state: ProductUnitProfileState.needsReview,
        rejectionStatus: error.statusCode,
        rejectionMessage: error.message,
      );
}

/// Durable immutable profile delivery. ID-less profiles live in a separate
/// pending-catalog store and enter the network outbox only after canonical
/// product binding.
class ProductUnitProfileOutbox {
  ProductUnitProfileOutbox(this.tenantId, this.branchId) {
    if (tenantId.trim().isEmpty || branchId.trim().isEmpty) {
      throw ArgumentError('Product unit profile scope must be complete');
    }
  }

  final String tenantId;
  final String branchId;

  String get _queueKey =>
      'ninesoft.product_unit_profile.outbox.v1.$tenantId.$branchId';
  String get _pendingKey =>
      'ninesoft.product_unit_profile.pending.v1.$tenantId.$branchId';
  String get _queuePrefix =>
      'ninesoft.product_unit_profile.outbox.v1.$tenantId.';
  String get _pendingPrefix =>
      'ninesoft.product_unit_profile.pending.v1.$tenantId.';
  String get _tenantWriterKey => 'product_unit_profile.$tenantId';

  static final Map<String, Future<void>> _writers = {};
  static final Set<String> _flushing = {};

  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _writers[_tenantWriterKey] ?? Future<void>.value();
    final gate = Completer<void>();
    _writers[_tenantWriterKey] = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
      if (identical(_writers[_tenantWriterKey], gate.future)) {
        _writers.remove(_tenantWriterKey);
      }
    }
  }

  Future<List<ProductUnitProfileEntry>> _readKey(String key) async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Product unit profile outbox is not a list');
    }
    return decoded
        .map((value) {
          if (value is! Map) {
            throw const FormatException('Invalid product unit profile entry');
          }
          return ProductUnitProfileEntry.fromJson(
            Map<String, dynamic>.from(value),
          );
        })
        .toList(growable: true);
  }

  Future<List<ProductUnitProfileEntry>> list() => _readKey(_queueKey);

  Future<List<ProductUnitProfileEntry>> listPendingCatalogEdits() =>
      _readKey(_pendingKey);

  Future<int> count() async => (await list()).length;

  Future<void> _saveKey(
    String key,
    Iterable<ProductUnitProfileEntry> entries,
  ) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
    if (!saved) throw StateError('Unable to persist product unit profile');
  }

  bool _sameContent(
    ProductUnitProfileEntry existing,
    ProductUnitProfileEntry candidate,
  ) =>
      existing.localProductKey == candidate.localProductKey &&
      existing.requestBody == candidate.requestBody &&
      existing.restoreGeneration == candidate.restoreGeneration &&
      existing.operationCreatedAt == candidate.operationCreatedAt &&
      (existing.productId.isEmpty ||
          candidate.productId.isEmpty ||
          existing.productId == candidate.productId);

  Future<({String key, ProductUnitProfileEntry entry})?> _findTenantOperation(
    String operationId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final keys = preferences.getKeys().where(
      (key) => key.startsWith(_queuePrefix) || key.startsWith(_pendingPrefix),
    );
    for (final key in keys) {
      for (final entry in await _readKey(key)) {
        if (entry.operationId == operationId) return (key: key, entry: entry);
      }
    }
    return null;
  }

  Future<void> stage({
    required String localProductKey,
    required String productId,
    required String operationId,
    required int restoreGeneration,
    required DateTime operationCreatedAt,
    required Map<String, dynamic> profile,
  }) => _serial(() async {
    if (localProductKey.trim().isEmpty ||
        operationId.trim().isEmpty ||
        restoreGeneration < 0) {
      throw ArgumentError('Incomplete product unit profile operation');
    }
    final requestedBranch = profile['branch_id']?.toString() ?? '';
    if (requestedBranch.isNotEmpty && requestedBranch != branchId) {
      throw StateError('Product unit profile belongs to another branch');
    }
    final suppliedOperation = profile['client_operation_id']?.toString() ?? '';
    if (suppliedOperation.isNotEmpty && suppliedOperation != operationId) {
      throw StateError('Product unit profile operation identifier changed');
    }
    final body = jsonEncode({
      'client_operation_id': operationId,
      'restore_generation': restoreGeneration,
      'operation_created_at': operationCreatedAt.toUtc().toIso8601String(),
      ...Map<String, dynamic>.from(profile)..remove('client_operation_id'),
    });
    final candidate = ProductUnitProfileEntry(
      localProductKey: localProductKey,
      productId: productId.trim(),
      operationId: operationId,
      restoreGeneration: restoreGeneration,
      operationCreatedAt: operationCreatedAt.toUtc(),
      requestBody: body,
    );
    final found = await _findTenantOperation(operationId);
    if (found != null) {
      if (!_sameContent(found.entry, candidate)) {
        throw StateError(
          'Product unit profile operation is used for different content',
        );
      }
      if (found.entry.productId.isEmpty && candidate.productId.isNotEmpty) {
        await _movePendingToQueue(found, candidate.productId);
      }
      return;
    }
    final key = candidate.awaitingCanonicalProduct ? _pendingKey : _queueKey;
    final entries = await _readKey(key)
      ..add(candidate);
    await _saveKey(key, entries);
  });

  Future<void> _movePendingToQueue(
    ({String key, ProductUnitProfileEntry entry}) found,
    String canonicalProductId,
  ) async {
    if (!found.key.startsWith(_pendingPrefix)) {
      throw StateError('Pending unit profile already has a canonical product');
    }
    final pending = await _readKey(found.key)
      ..removeWhere((entry) => entry.operationId == found.entry.operationId);
    final queue = await list()
      ..add(found.entry.attach(canonicalProductId));
    // Persist the sendable copy first: a partial storage failure may leave a
    // duplicate draft marker, but it must never lose the user's profile.
    await _saveKey(_queueKey, queue);
    await _saveKey(found.key, pending);
  }

  Future<void> attachCanonicalProduct(String operationId, String productId) =>
      _serial(() async {
        if (operationId.isEmpty || productId.trim().isEmpty) {
          throw ArgumentError('Canonical product binding is incomplete');
        }
        final found = await _findTenantOperation(operationId);
        if (found == null) {
          throw StateError('Pending unit profile was not found');
        }
        if (found.entry.productId.isNotEmpty) {
          if (found.entry.productId != productId) {
            throw StateError(
              'Pending unit profile already has another product',
            );
          }
          return;
        }
        await _movePendingToQueue(found, productId.trim());
      });

  Future<void> _removeFrom(
    String key,
    String operationId, {
    bool Function()? isValid,
  }) => _serial(() async {
    final entries = await _readKey(key);
    if (isValid != null && !isValid()) {
      throw const ProductUnitProfileResponseInvalidated();
    }
    entries.removeWhere((entry) => entry.operationId == operationId);
    await _saveKey(key, entries);
  });

  Future<bool> _markNeedsReview(
    String operationId,
    CatalogApiException error,
    bool Function() isValid,
  ) => _serial(() async {
    if (!isValid()) return false;
    final entries = await list();
    final index = entries.indexWhere(
      (entry) => entry.operationId == operationId,
    );
    if (index < 0) return true;
    entries[index] = entries[index].reject(error);
    if (!isValid()) return false;
    await _saveKey(_queueKey, entries);
    return true;
  });

  bool _invalidRestore(
    ProductUnitProfileEntry entry,
    int currentRestoreGeneration,
    DateTime? restoreEpoch,
  ) =>
      entry.restoreGeneration != currentRestoreGeneration ||
      (restoreEpoch != null &&
          !entry.operationCreatedAt.isAfter(restoreEpoch.toUtc()));

  void _requireCanonicalPositiveInteger(
    Map<String, dynamic> payload,
    String field,
  ) {
    final value = payload[field];
    int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is String && RegExp(r'^[1-9][0-9]*$').hasMatch(value)) {
      parsed = int.tryParse(value);
    }
    if (parsed == null || parsed <= 0 || parsed > 9007199254740991) {
      throw FormatException('Invalid sale option $field');
    }
  }

  Future<List<ProductSaleOption>> _validateAcknowledgement(
    Map<String, dynamic> response,
    ProductUnitProfileEntry entry,
  ) async {
    final product = response['product'];
    final rawOptions = response['sale_options'];
    if (product is! Map ||
        product['id'] is! String ||
        product['id'] != entry.productId ||
        rawOptions is! List ||
        rawOptions.isEmpty) {
      throw const FormatException(
        'Invalid product unit profile acknowledgement',
      );
    }
    if (product.containsKey('tenant_id') &&
        (product['tenant_id'] is! String || product['tenant_id'] != tenantId)) {
      throw const FormatException('Acknowledged product tenant mismatch');
    }
    final options = <ProductSaleOption>[];
    final ids = <String>{};
    for (final raw in rawOptions) {
      if (raw is! Map) {
        throw const FormatException('Invalid unit profile sale option row');
      }
      final payload = Map<String, dynamic>.from(raw);
      for (final field in const [
        'id',
        'tenant_id',
        'product_id',
        'identity_key',
        'unit_code',
      ]) {
        if (payload[field] is! String || (payload[field] as String).isEmpty) {
          throw FormatException('Invalid sale option $field');
        }
      }
      if (payload['branch_id'] != null && payload['branch_id'] is! String) {
        throw const FormatException('Invalid sale option branch_id');
      }
      for (final field in const [
        'quantity_per_option',
        'option_price_minor',
        'is_derived',
      ]) {
        if (!payload.containsKey(field)) {
          throw FormatException('Missing sale option $field');
        }
      }
      _requireCanonicalPositiveInteger(payload, 'price_numerator_minor');
      _requireCanonicalPositiveInteger(payload, 'price_denominator');
      _requireCanonicalPositiveInteger(payload, 'version');
      final option = ProductSaleOption.fromJson(payload);
      if (option.tenantId != tenantId ||
          option.productId != entry.productId ||
          (option.branchId != null && option.branchId != branchId) ||
          option.quantity <= 0 ||
          !ids.add(option.id)) {
        throw const FormatException('Sale option acknowledgement mismatch');
      }
      options.add(option);
    }
    return options;
  }

  Future<ProductUnitProfileFlushResult> flush({
    required CatalogSyncApi api,
    required int currentRestoreGeneration,
    DateTime? restoreEpoch,
    int maxPerCycle = 4,
    bool Function()? isResponseValid,
  }) async {
    if (!_flushing.add(_queueKey)) {
      return const ProductUnitProfileFlushResult();
    }
    final responseStillValid = isResponseValid ?? () => true;
    var sent = 0;
    var quarantined = 0;
    var needsReview = 0;
    var invalidated = 0;
    String? error;
    try {
      for (final entry in await listPendingCatalogEdits()) {
        final quarantine = QuarantinedOperationStore(tenantId);
        if (await quarantine.isDiscarded(
          entry.operationId,
          'product_unit_profile',
        )) {
          await _removeFrom(_pendingKey, entry.operationId);
          quarantined++;
          continue;
        }
        if (_invalidRestore(entry, currentRestoreGeneration, restoreEpoch)) {
          await quarantine.quarantine(
            operationId: entry.operationId,
            kind: 'product_unit_profile',
            reason: entry.restoreGeneration != currentRestoreGeneration
                ? 'restore_generation_mismatch'
                : 'created_before_restore',
            payload: entry.toJson(),
          );
          await _removeFrom(_pendingKey, entry.operationId);
          quarantined++;
        }
      }
      for (final entry in await list()) {
        if (sent >= maxPerCycle) break;
        if (entry.state == ProductUnitProfileState.needsReview) continue;
        final quarantine = QuarantinedOperationStore(tenantId);
        if (await quarantine.isDiscarded(
          entry.operationId,
          'product_unit_profile',
        )) {
          await _removeFrom(_queueKey, entry.operationId);
          quarantined++;
          continue;
        }
        if (_invalidRestore(entry, currentRestoreGeneration, restoreEpoch)) {
          await quarantine.quarantine(
            operationId: entry.operationId,
            kind: 'product_unit_profile',
            reason: entry.restoreGeneration != currentRestoreGeneration
                ? 'restore_generation_mismatch'
                : 'created_before_restore',
            payload: entry.toJson(),
          );
          await _removeFrom(_queueKey, entry.operationId);
          quarantined++;
          continue;
        }
        try {
          final response = await api.putUnitProfileRequest(
            productId: entry.productId,
            requestBody: entry.requestBody,
          );
          if (!responseStillValid()) {
            invalidated++;
            break;
          }
          final options = await _validateAcknowledgement(response, entry);
          if (!responseStillValid()) {
            invalidated++;
            break;
          }
          await ProductSaleOptionStore(
            tenantId,
            branchId,
          ).upsertAll(options, isValid: responseStillValid);
          await _removeFrom(
            _queueKey,
            entry.operationId,
            isValid: responseStillValid,
          );
          sent++;
        } on ProductSaleOptionWriteInvalidated {
          invalidated++;
          break;
        } on ProductUnitProfileResponseInvalidated {
          invalidated++;
          break;
        } on CatalogApiException catch (failure) {
          if (!responseStillValid()) {
            invalidated++;
            break;
          }
          if (failure.definitelyRejected) {
            final marked = await _markNeedsReview(
              entry.operationId,
              failure,
              responseStillValid,
            );
            if (!marked) {
              invalidated++;
              break;
            }
            needsReview++;
          }
          error = failure.toString();
          break;
        } catch (failure) {
          if (!responseStillValid()) {
            invalidated++;
            break;
          }
          error = failure.toString();
          break;
        }
      }
    } finally {
      _flushing.remove(_queueKey);
    }
    return ProductUnitProfileFlushResult(
      sent: sent,
      quarantined: quarantined,
      needsReview: needsReview,
      invalidated: invalidated,
      error: error,
    );
  }
}

class ProductUnitProfileResponseInvalidated implements Exception {
  const ProductUnitProfileResponseInvalidated();
}

class ProductUnitProfileFlushResult {
  const ProductUnitProfileFlushResult({
    this.sent = 0,
    this.quarantined = 0,
    this.needsReview = 0,
    this.invalidated = 0,
    this.error,
  });

  final int sent;
  final int quarantined;
  final int needsReview;
  final int invalidated;
  final String? error;
}
