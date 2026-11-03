import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../accounting/accounting_api.dart';
import '../purchases/purchase_invoice_store.dart';
import 'quarantined_operation_store.dart';

enum PurchaseOutboxState { queued, needsReview }

class PurchaseOutboxEntry {
  const PurchaseOutboxEntry({
    required this.operationId,
    required this.restoreGeneration,
    required this.operationCreatedAt,
    required this.requestBody,
    this.state = PurchaseOutboxState.queued,
    this.rejectionStatus,
    this.rejectionMessage,
  });

  final String operationId;
  final int restoreGeneration;
  final DateTime operationCreatedAt;
  final String requestBody;
  final PurchaseOutboxState state;
  final int? rejectionStatus;
  final String? rejectionMessage;

  Map<String, dynamic> get request {
    final decoded = jsonDecode(requestBody);
    if (decoded is! Map) {
      throw const FormatException('Purchase request is not an object');
    }
    return Map<String, dynamic>.from(decoded);
  }

  factory PurchaseOutboxEntry.fromRequest(
    Map<String, dynamic> request, {
    required String branchId,
  }) {
    final operationId = request['local_operation_id']?.toString() ?? '';
    final generation = request['restore_generation'];
    final createdAt = DateTime.tryParse(
      request['operation_created_at']?.toString() ?? '',
    )?.toUtc();
    if (operationId.isEmpty ||
        (request['device_id']?.toString() ?? '').isEmpty ||
        request['branch_id']?.toString() != branchId ||
        generation is! int ||
        generation < 0 ||
        createdAt == null ||
        request['items'] is! List ||
        (request['items'] as List).isEmpty) {
      throw const FormatException('Incomplete immutable purchase request');
    }
    return PurchaseOutboxEntry(
      operationId: operationId,
      restoreGeneration: generation,
      operationCreatedAt: createdAt,
      requestBody: jsonEncode(request),
    );
  }

  factory PurchaseOutboxEntry.fromJson(
    Map<String, dynamic> json, {
    required String branchId,
  }) {
    final operationId = json['operation_id']?.toString() ?? '';
    final generation = json['restore_generation'];
    final createdAt = DateTime.tryParse(
      json['operation_created_at']?.toString() ?? '',
    )?.toUtc();
    final requestBody = json['request_body'];
    final rawState = json['state']?.toString() ?? '';
    final state = switch (rawState) {
      'queued' => PurchaseOutboxState.queued,
      'needs_review' => PurchaseOutboxState.needsReview,
      _ => throw const FormatException('Invalid purchase outbox state'),
    };
    final rawStatus = json['rejection_status'];
    if (operationId.isEmpty ||
        generation is! int ||
        generation < 0 ||
        createdAt == null ||
        requestBody is! String ||
        requestBody.isEmpty ||
        (rawStatus != null && rawStatus is! int)) {
      throw const FormatException('Invalid purchase outbox entry');
    }
    final entry = PurchaseOutboxEntry(
      operationId: operationId,
      restoreGeneration: generation,
      operationCreatedAt: createdAt,
      requestBody: requestBody,
      state: state,
      rejectionStatus: rawStatus as int?,
      rejectionMessage: json['rejection_message']?.toString(),
    );
    final request = entry.request;
    final requestCreatedAt = DateTime.tryParse(
      request['operation_created_at']?.toString() ?? '',
    )?.toUtc();
    if (request['local_operation_id']?.toString() != operationId ||
        request['restore_generation'] != generation ||
        request['branch_id']?.toString() != branchId ||
        (request['device_id']?.toString() ?? '').isEmpty ||
        requestCreatedAt == null ||
        !requestCreatedAt.isAtSameMomentAs(createdAt) ||
        request['items'] is! List ||
        (request['items'] as List).isEmpty) {
      throw const FormatException('Purchase outbox identity mismatch');
    }
    return entry;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'operation_id': operationId,
    'restore_generation': restoreGeneration,
    'operation_created_at': operationCreatedAt.toUtc().toIso8601String(),
    'request_body': requestBody,
    'state': state == PurchaseOutboxState.queued ? 'queued' : 'needs_review',
    if (rejectionStatus != null) 'rejection_status': rejectionStatus,
    if (rejectionMessage != null) 'rejection_message': rejectionMessage,
  };

  PurchaseOutboxEntry reject(AccountingApiError failure) => PurchaseOutboxEntry(
    operationId: operationId,
    restoreGeneration: restoreGeneration,
    operationCreatedAt: operationCreatedAt,
    requestBody: requestBody,
    state: PurchaseOutboxState.needsReview,
    rejectionStatus: failure.statusCode,
    rejectionMessage: failure.message,
  );

  PurchaseOutboxEntry rebaseRestoreGeneration(int generation) {
    final rebasedRequest = request
      ..['restore_generation'] = generation
      ..['operation_created_at'] = operationCreatedAt.toUtc().toIso8601String();
    return PurchaseOutboxEntry(
      operationId: operationId,
      restoreGeneration: generation,
      operationCreatedAt: operationCreatedAt,
      requestBody: jsonEncode(rebasedRequest),
    );
  }

  PurchaseOutboxEntry rebaseAfterRestore(
    int generation,
    DateTime? restoreEpoch,
  ) {
    final now = DateTime.now().toUtc();
    final minimum = restoreEpoch?.toUtc().add(const Duration(seconds: 1));
    final createdAt = minimum != null && minimum.isAfter(now) ? minimum : now;
    final rebasedRequest = request
      ..['restore_generation'] = generation
      ..['operation_created_at'] = createdAt.toIso8601String();
    return PurchaseOutboxEntry(
      operationId: operationId,
      restoreGeneration: generation,
      operationCreatedAt: createdAt,
      requestBody: jsonEncode(rebasedRequest),
    );
  }
}

bool canSendPurchaseOutbox({
  required String roleCode,
  required Iterable<String> permissions,
}) {
  if (roleCode == 'owner') return true;
  final granted = permissions.toSet();
  return granted.contains('invoices.create') &&
      granted.contains('invoices.read');
}

/// Immutable identity/ACL snapshot for one interactive purchase save.
///
/// The widget can remain mounted while its authenticated session changes, so
/// `mounted` alone is not a safe post-response guard.
class PurchaseDeliverySession {
  const PurchaseDeliverySession({
    required this.tenantId,
    required this.token,
    required this.branchId,
    required this.roleCode,
    required this.permissions,
  });

  final String tenantId;
  final String token;
  final String branchId;
  final String roleCode;
  final List<String> permissions;

  bool matches({
    required String tenantId,
    required String token,
    required String branchId,
    required String roleCode,
    required Iterable<String> permissions,
  }) {
    final capturedPermissions = this.permissions.toSet();
    final currentPermissions = permissions.toSet();
    return this.tenantId == tenantId &&
        this.token == token &&
        this.branchId == branchId &&
        this.roleCode == roleCode &&
        capturedPermissions.length == currentPermissions.length &&
        capturedPermissions.containsAll(currentPermissions) &&
        canSendPurchaseOutbox(
          roleCode: roleCode,
          permissions: currentPermissions,
        );
  }
}

/// Durable source of truth for finalized, unacknowledged purchases.
class PurchaseOutbox {
  PurchaseOutbox(
    this.tenantId,
    this.branchId, {
    PurchaseInvoiceStore? invoiceStore,
  }) : _invoiceStore = invoiceStore ?? PurchaseInvoiceStore() {
    if (tenantId.trim().isEmpty || branchId.trim().isEmpty) {
      throw ArgumentError('Purchase outbox scope must be complete');
    }
  }

  final String tenantId;
  final String branchId;
  final PurchaseInvoiceStore _invoiceStore;

  String get _key => 'ninesoft.purchase.outbox.v1.$tenantId.$branchId';
  String get _tenantPrefix => 'ninesoft.purchase.outbox.v1.$tenantId.';
  String get _tenantWriterKey => 'purchase.$tenantId';

  static final Map<String, Future<void>> _writers = <String, Future<void>>{};
  static final Set<String> _flushing = <String>{};

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

  String _branchFromKey(String key) {
    if (!key.startsWith(_tenantPrefix)) {
      throw const FormatException('Purchase outbox key is outside tenant');
    }
    final value = key.substring(_tenantPrefix.length);
    if (value.isEmpty) {
      throw const FormatException('Purchase outbox branch is missing');
    }
    return value;
  }

  Future<List<PurchaseOutboxEntry>> _readKey(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(key);
    if (raw == null || raw.isEmpty) return <PurchaseOutboxEntry>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Purchase outbox is not a list');
    }
    final entries = <PurchaseOutboxEntry>[];
    var migratedLegacy = false;
    final keyBranch = _branchFromKey(key);
    for (final value in decoded) {
      if (value is! Map) {
        throw const FormatException('Invalid purchase outbox row');
      }
      final row = Map<String, dynamic>.from(value);
      if (row.containsKey('request_body')) {
        entries.add(PurchaseOutboxEntry.fromJson(row, branchId: keyBranch));
        continue;
      }
      final legacyRequest = row['request'];
      final enqueuedAt = DateTime.tryParse(
        row['enqueued_at']?.toString() ?? '',
      );
      if (legacyRequest is! Map || enqueuedAt == null) {
        throw const FormatException('Invalid legacy pending purchase');
      }
      entries.add(
        PurchaseOutboxEntry.fromRequest(
          Map<String, dynamic>.from(legacyRequest),
          branchId: keyBranch,
        ),
      );
      migratedLegacy = true;
    }
    if (migratedLegacy) {
      final saved = await preferences.setString(
        key,
        jsonEncode(entries.map((entry) => entry.toJson()).toList()),
      );
      if (!saved) {
        throw StateError('Unable to migrate purchase outbox');
      }
    }
    return entries;
  }

  Future<List<PurchaseOutboxEntry>> _listUnlocked() => _readKey(_key);

  Future<List<PurchaseOutboxEntry>> list() => _serial(_listUnlocked);

  Future<int> count() async => (await list()).length;

  Future<PurchaseOutboxSummary> summary() => _serial(() async {
    final entries = await _listUnlocked();
    return PurchaseOutboxSummary(
      queued: entries
          .where((entry) => entry.state == PurchaseOutboxState.queued)
          .length,
      needsReview: entries
          .where((entry) => entry.state == PurchaseOutboxState.needsReview)
          .length,
    );
  });

  Future<PurchaseOutboxEntry?> find(String operationId) => _serial(() async {
    for (final entry in await _listUnlocked()) {
      if (entry.operationId == operationId) return entry;
    }
    return null;
  });

  Future<void> _saveUnlocked(Iterable<PurchaseOutboxEntry> entries) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
    if (!saved) throw StateError('Unable to persist purchase outbox');
  }

  Future<({String key, PurchaseOutboxEntry entry})?> _findTenantOperation(
    String operationId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in preferences.getKeys().where(
      (candidate) => candidate.startsWith(_tenantPrefix),
    )) {
      for (final entry in await _readKey(key)) {
        if (entry.operationId == operationId) {
          return (key: key, entry: entry);
        }
      }
    }
    return null;
  }

  Future<void> enqueue(
    Map<String, dynamic> request, {
    bool Function()? isValid,
  }) => _serial(() async {
    if (isValid != null && !isValid()) {
      throw const PurchaseOutboxResponseInvalidated();
    }
    PurchaseOutboxEntry candidate;
    try {
      candidate = PurchaseOutboxEntry.fromRequest(request, branchId: branchId);
    } on FormatException catch (failure) {
      throw ArgumentError(failure.message);
    }
    final existing = await _findTenantOperation(candidate.operationId);
    if (existing != null) {
      if (existing.entry.requestBody != candidate.requestBody) {
        throw StateError(
          'Purchase operation is already used for different content',
        );
      }
      return;
    }
    final entries = await _listUnlocked()
      ..add(candidate);
    if (isValid != null && !isValid()) {
      throw const PurchaseOutboxResponseInvalidated();
    }
    await _saveUnlocked(entries);
  });

  Future<void> _remove(String operationId, bool Function() isValid) =>
      _serial(() async {
        if (!isValid()) throw const PurchaseOutboxResponseInvalidated();
        final entries = await _listUnlocked()
          ..removeWhere((entry) => entry.operationId == operationId);
        if (!isValid()) throw const PurchaseOutboxResponseInvalidated();
        await _saveUnlocked(entries);
      });

  Future<bool> _markNeedsReview(
    String operationId,
    AccountingApiError failure,
    bool Function() isValid,
  ) => _serial(() async {
    if (!isValid()) return false;
    final entries = await _listUnlocked();
    final index = entries.indexWhere(
      (entry) => entry.operationId == operationId,
    );
    if (index < 0) return true;
    entries[index] = entries[index].reject(failure);
    if (!isValid()) return false;
    await _saveUnlocked(entries);
    return true;
  });

  Future<void> _replace(PurchaseOutboxEntry replacement) => _serial(() async {
    final entries = await _listUnlocked();
    final index = entries.indexWhere(
      (entry) => entry.operationId == replacement.operationId,
    );
    if (index < 0) {
      entries.add(replacement);
    } else {
      entries[index] = replacement;
    }
    await _saveUnlocked(entries);
  });

  bool _canRebaseAfterRestore(
    PurchaseOutboxEntry entry,
    DateTime? restoreEpoch,
  ) =>
      restoreEpoch != null &&
      entry.operationCreatedAt.isAfter(restoreEpoch.toUtc());

  bool _isRecoverablePostRestoreReason(Object? reason) {
    final normalized = reason?.toString().trim().toUpperCase() ?? '';
    return normalized == 'RESTORE_GENERATION_MISMATCH' ||
        normalized == 'RESTORE_GENERATION_REQUIRED' ||
        normalized == 'RESTORE_GENERATION_AT_CREATION_MISMATCH' ||
        normalized == 'OPERATION_CREATION_TIME_REQUIRED_AFTER_RESTORE' ||
        normalized == 'OPERATION_CREATED_BEFORE_RESTORE' ||
        normalized == 'CREATED_BEFORE_RESTORE';
  }

  Future<void> _recoverSafeGenerationMismatch({
    required int currentRestoreGeneration,
    required DateTime? restoreEpoch,
    required bool Function() isValid,
  }) async {
    if (!isValid()) return;
    final quarantine = QuarantinedOperationStore(tenantId);
    for (final item in await quarantine.list()) {
      if (!isValid() ||
          item['kind'] != 'purchase' ||
          !_isRecoverablePostRestoreReason(item['reason'])) {
        continue;
      }
      final payload = item['payload'];
      if (payload is! Map) continue;
      PurchaseOutboxEntry stored;
      try {
        stored = PurchaseOutboxEntry.fromJson(
          Map<String, dynamic>.from(payload),
          branchId: branchId,
        );
      } on FormatException {
        continue;
      }
      await _replace(stored);
      await quarantine.remove(stored.operationId);
    }
  }

  Map<String, dynamic> _validateCanonicalInvoice(
    Map<String, dynamic> response,
    PurchaseOutboxEntry entry,
    String acknowledgedId,
  ) {
    final request = entry.request;
    for (final field in const <String>['id', 'number', 'branch_id']) {
      if (response[field] is! String ||
          (response[field] as String).trim().isEmpty) {
        throw FormatException('Incomplete purchase acknowledgement: $field');
      }
    }
    if (response['id'] != acknowledgedId ||
        response['branch_id'] != branchId ||
        response['type'] != 'purchase' ||
        response['status'] != 'posted' ||
        response['device_id'] != request['device_id'] ||
        response['local_operation_id'] != entry.operationId) {
      throw const FormatException('Purchase acknowledgement identity mismatch');
    }
    for (final field in const <String>[
      'total_minor',
      'paid_minor',
      'due_minor',
    ]) {
      if (response[field] is! int) {
        throw FormatException('Incomplete purchase acknowledgement: $field');
      }
    }
    final rawItems = response['items'];
    final requestItems = request['items'];
    if (rawItems is! List ||
        rawItems.isEmpty ||
        requestItems is! List ||
        rawItems.length != requestItems.length) {
      throw const FormatException('Purchase acknowledgement line mismatch');
    }
    final unmatchedRequests = <Map<String, dynamic>>[];
    for (final rawRequest in requestItems) {
      if (rawRequest is! Map) {
        throw const FormatException('Invalid immutable purchase line');
      }
      unmatchedRequests.add(Map<String, dynamic>.from(rawRequest));
    }
    final canonicalItems = <Map<String, dynamic>>[];
    for (var index = 0; index < rawItems.length; index++) {
      final raw = rawItems[index];
      if (raw is! Map) {
        throw const FormatException('Invalid purchase acknowledgement line');
      }
      final item = Map<String, dynamic>.from(raw);
      final productId = item['product_id'];
      final name = item['product_name_snapshot'];
      if (productId is! String ||
          productId.isEmpty ||
          name is! String ||
          name.isEmpty ||
          item['quantity_milli'] is! int ||
          (item['quantity_milli'] as int) <= 0 ||
          item['stock_quantity_milli'] is! int ||
          (item['stock_quantity_milli'] as int) < 0 ||
          item['unit_price_minor'] is! int ||
          (item['unit_price_minor'] as int) < 0 ||
          item['line_total_minor'] is! int ||
          (item['line_total_minor'] as int) < 0 ||
          item['discount_minor'] is! int ||
          (item['discount_minor'] as int) < 0 ||
          item['tax_minor'] is! int ||
          (item['tax_minor'] as int) < 0) {
        throw FormatException(
          'Incomplete canonical purchase line at index $index',
        );
      }
      final requestIndex = unmatchedRequests.indexWhere(
        (requested) => _canonicalLineMatchesRequest(item, requested),
      );
      if (requestIndex < 0) {
        throw FormatException(
          'Canonical purchase line has no immutable request match at index $index',
        );
      }
      final requested = unmatchedRequests.removeAt(requestIndex);
      final optionId = requested['sale_option_id']?.toString() ?? '';
      if (optionId.isNotEmpty) {
        if (item['sale_option_id'] != optionId ||
            !_nonEmptyString(item['option_unit_code_snapshot']) ||
            !_nonEmptyString(item['transaction_unit_name_snapshot']) ||
            !_nonEmptyString(item['purchase_unit_name_snapshot']) ||
            !_nonEmptyString(item['stock_unit_name_snapshot']) ||
            !_validOptionDimensions(item) ||
            !_positiveInt(item['stock_factor_milli_snapshot']) ||
            !_positiveInt(item['stock_factor_milli']) ||
            !_positiveInt(item['units_per_package_milli']) ||
            !_positiveInt(item['price_numerator_minor_snapshot']) ||
            !_positiveInt(item['price_denominator_snapshot'])) {
          throw FormatException(
            'Incomplete selected-option snapshot at index $index',
          );
        }
        if (item['stock_factor_milli'] != item['stock_factor_milli_snapshot'] ||
            item['units_per_package_milli'] !=
                item['stock_factor_milli_snapshot']) {
          throw FormatException(
            'Inconsistent selected-option factor at index $index',
          );
        }
        final requestedNumerator = requested['price_numerator_minor'];
        final requestedDenominator = requested['price_denominator'];
        if ((requestedNumerator != null &&
                item['price_numerator_minor_snapshot'] != requestedNumerator) ||
            (requestedDenominator != null &&
                item['price_denominator_snapshot'] != requestedDenominator)) {
          throw FormatException(
            'Selected-option exact price differs at index $index',
          );
        }
      } else {
        for (final field in const <String>[
          'sale_option_id',
          'option_unit_code_snapshot',
          'option_quantity_snapshot',
          'option_mass_g_snapshot',
          'price_numerator_minor_snapshot',
          'price_denominator_snapshot',
        ]) {
          if (!item.containsKey(field)) {
            throw FormatException(
              'Missing legacy snapshot field $field at index $index',
            );
          }
        }
      }
      canonicalItems.add(item);
    }
    if (unmatchedRequests.isNotEmpty) {
      throw const FormatException('Purchase acknowledgement omitted lines');
    }
    return <String, dynamic>{...response, 'items': canonicalItems};
  }

  bool _canonicalLineMatchesRequest(
    Map<String, dynamic> item,
    Map<String, dynamic> requested,
  ) {
    if (item['quantity_milli'] != requested['quantity_milli'] ||
        item['unit_price_minor'] != requested['unit_price_minor'] ||
        item['discount_minor'] != (requested['discount_minor'] ?? 0) ||
        item['tax_minor'] != (requested['tax_minor'] ?? 0)) {
      return false;
    }
    final requestedProduct = requested['product_id']?.toString() ?? '';
    if (requestedProduct.isNotEmpty) {
      if (item['product_id'] != requestedProduct) return false;
    } else {
      final requestedName = _normalizeName(requested['name']?.toString() ?? '');
      final canonicalName = _normalizeName(
        item['product_name_snapshot']?.toString() ?? '',
      );
      if (requestedName.isEmpty || requestedName != canonicalName) return false;
    }
    final requestedOption = requested['sale_option_id']?.toString() ?? '';
    final canonicalOption = item['sale_option_id']?.toString() ?? '';
    if (requestedOption != canonicalOption) return false;
    final requestedNumerator = requested['price_numerator_minor'];
    final requestedDenominator = requested['price_denominator'];
    if ((requestedNumerator != null &&
            item['price_numerator_minor_snapshot'] != requestedNumerator) ||
        (requestedDenominator != null &&
            item['price_denominator_snapshot'] != requestedDenominator)) {
      return false;
    }
    return true;
  }

  String _normalizeName(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  bool _nonEmptyString(Object? value) =>
      value is String && value.trim().isNotEmpty;

  bool _positiveInt(Object? value) => value is int && value > 0;

  bool _validOptionDimensions(Map<String, dynamic> item) {
    if (!item.containsKey('option_quantity_snapshot') ||
        !item.containsKey('option_mass_g_snapshot')) {
      return false;
    }
    final quantity = item['option_quantity_snapshot'];
    final mass = item['option_mass_g_snapshot'];
    bool valid(Object? value) =>
        value == null ||
        (value is String && RegExp(r'^\d+\.\d{6}$').hasMatch(value));
    return valid(quantity) && valid(mass) && (quantity != null || mass != null);
  }

  Future<PurchaseFlushResult> flush({
    required AccountingApi api,
    required int currentRestoreGeneration,
    DateTime? restoreEpoch,
    int maxPerCycle = 4,
    bool Function()? isResponseValid,
    bool Function(PurchaseOutboxEntry entry)? canSend,
  }) async {
    if (!_flushing.add(_tenantWriterKey)) {
      return const PurchaseFlushResult();
    }
    final responseStillValid = isResponseValid ?? () => true;
    var sent = 0;
    var quarantined = 0;
    var needsReview = 0;
    var invalidated = 0;
    var attempted = 0;
    final sentOperationIds = <String>{};
    final quarantinedOperationIds = <String>{};
    final needsReviewOperationIds = <String>{};
    String? error;
    try {
      await _recoverSafeGenerationMismatch(
        currentRestoreGeneration: currentRestoreGeneration,
        restoreEpoch: restoreEpoch,
        isValid: responseStillValid,
      );
      for (final storedEntry in await list()) {
        var entry = storedEntry;
        if (attempted >= maxPerCycle) break;
        if (!responseStillValid()) {
          invalidated++;
          break;
        }
        if (entry.state == PurchaseOutboxState.needsReview) continue;
        final quarantine = QuarantinedOperationStore(tenantId);
        if (await quarantine.isDiscarded(entry.operationId, 'purchase')) {
          await _remove(entry.operationId, responseStillValid);
          quarantined++;
          quarantinedOperationIds.add(entry.operationId);
          continue;
        }
        if (entry.restoreGeneration != currentRestoreGeneration &&
            _canRebaseAfterRestore(entry, restoreEpoch)) {
          entry = entry.rebaseRestoreGeneration(currentRestoreGeneration);
          await _replace(entry);
        }
        if (canSend != null && !canSend(entry)) break;
        attempted++;
        try {
          final summary = await api.postPurchaseRequestBody(entry.requestBody);
          if (!responseStillValid()) {
            invalidated++;
            break;
          }
          final acknowledgedId = summary['id']?.toString() ?? '';
          if (acknowledgedId.isEmpty) {
            throw const FormatException(
              'Purchase acknowledgement has no invoice ID',
            );
          }
          final detail = await api.invoice(acknowledgedId);
          if (!responseStillValid()) {
            invalidated++;
            break;
          }
          final canonical = _validateCanonicalInvoice(
            detail,
            entry,
            acknowledgedId,
          );
          if (!responseStillValid()) {
            invalidated++;
            break;
          }
          await _invoiceStore.save(
            tenantId,
            branchId,
            canonical,
            isValid: responseStillValid,
          );
          await _remove(entry.operationId, responseStillValid);
          sent++;
          sentOperationIds.add(entry.operationId);
        } on PurchaseInvoiceWriteInvalidated {
          invalidated++;
          break;
        } on PurchaseOutboxResponseInvalidated {
          invalidated++;
          break;
        } on AccountingApiError catch (failure) {
          if (!responseStillValid()) {
            invalidated++;
            break;
          }
          if (failure.restoreBoundaryViolation) {
            await _replace(
              entry.rebaseAfterRestore(currentRestoreGeneration, restoreEpoch),
            );
            error = failure.toString();
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
            needsReviewOperationIds.add(entry.operationId);
            error = failure.toString();
            continue;
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
      _flushing.remove(_tenantWriterKey);
    }
    return PurchaseFlushResult(
      sent: sent,
      quarantined: quarantined,
      needsReview: needsReview,
      invalidated: invalidated,
      sentOperationIds: Set<String>.unmodifiable(sentOperationIds),
      quarantinedOperationIds: Set<String>.unmodifiable(
        quarantinedOperationIds,
      ),
      needsReviewOperationIds: Set<String>.unmodifiable(
        needsReviewOperationIds,
      ),
      error: error,
    );
  }
}

class PurchaseOutboxResponseInvalidated implements Exception {
  const PurchaseOutboxResponseInvalidated();
}

class PurchaseOutboxSummary {
  const PurchaseOutboxSummary({
    required this.queued,
    required this.needsReview,
  });

  final int queued;
  final int needsReview;

  int get total => queued + needsReview;
}

class PurchaseFlushResult {
  const PurchaseFlushResult({
    this.sent = 0,
    this.quarantined = 0,
    this.needsReview = 0,
    this.invalidated = 0,
    this.sentOperationIds = const <String>{},
    this.quarantinedOperationIds = const <String>{},
    this.needsReviewOperationIds = const <String>{},
    this.error,
  });

  final int sent;
  final int quarantined;
  final int needsReview;
  final int invalidated;
  final Set<String> sentOperationIds;
  final Set<String> quarantinedOperationIds;
  final Set<String> needsReviewOperationIds;
  final String? error;

  int get blocked => quarantined;
}
