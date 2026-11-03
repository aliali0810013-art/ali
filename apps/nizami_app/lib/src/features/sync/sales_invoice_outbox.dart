import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../accounting/accounting_api.dart';
import '../invoices/invoice_history_store.dart';
import '../invoices/invoice_pdf_service.dart';
import 'quarantined_operation_store.dart';

enum SalesInvoiceOutboxState { queued, needsReview }

class SalesInvoiceOutboxEntry {
  const SalesInvoiceOutboxEntry({
    required this.operationId,
    required this.restoreGeneration,
    required this.operationCreatedAt,
    required this.endpointPath,
    required this.requestBody,
    this.documentSnapshot,
    this.state = SalesInvoiceOutboxState.queued,
    this.rejectionStatus,
    this.rejectionMessage,
  });

  final String operationId;
  final int restoreGeneration;
  final DateTime operationCreatedAt;
  final String endpointPath;
  final String requestBody;
  final InvoiceDocument? documentSnapshot;
  final SalesInvoiceOutboxState state;
  final int? rejectionStatus;
  final String? rejectionMessage;

  Map<String, dynamic> get request {
    final decoded = jsonDecode(requestBody);
    if (decoded is! Map) {
      throw const FormatException('Sales invoice request is not an object');
    }
    return Map<String, dynamic>.from(decoded);
  }

  factory SalesInvoiceOutboxEntry.fromJson(Map<String, dynamic> json) {
    final operationId = json['operation_id']?.toString() ?? '';
    final generation = json['restore_generation'];
    final createdAt = DateTime.tryParse(
      json['operation_created_at']?.toString() ?? '',
    )?.toUtc();
    final endpoint = json['endpoint_path']?.toString() ?? '';
    final body = json['request_body']?.toString() ?? '';
    final rawState = json['state']?.toString() ?? 'queued';
    final rawSnapshot = json['document_snapshot'];
    final snapshot = rawSnapshot is Map
        ? InvoiceDocument.fromJson(Map<String, dynamic>.from(rawSnapshot))
        : null;
    final state = switch (rawState) {
      'queued' => SalesInvoiceOutboxState.queued,
      'needs_review' => SalesInvoiceOutboxState.needsReview,
      _ => throw const FormatException('Invalid sales invoice outbox state'),
    };
    if (operationId.isEmpty ||
        generation is! int ||
        generation < 0 ||
        createdAt == null ||
        endpoint.isEmpty ||
        body.isEmpty) {
      throw const FormatException('Invalid sales invoice outbox entry');
    }
    final entry = SalesInvoiceOutboxEntry(
      operationId: operationId,
      restoreGeneration: generation,
      operationCreatedAt: createdAt,
      endpointPath: endpoint,
      requestBody: body,
      documentSnapshot: snapshot,
      state: state,
      rejectionStatus: (json['rejection_status'] as num?)?.toInt(),
      rejectionMessage: json['rejection_message']?.toString(),
    );
    final request = entry.request;
    if (request['local_operation_id'] != operationId ||
        request['restore_generation'] != generation ||
        _endpointFor(request) != endpoint) {
      throw const FormatException('Sales invoice outbox identity mismatch');
    }
    if (snapshot != null &&
        (snapshot.localOperationId != operationId ||
            snapshot.restoreGenerationAtCreation != generation)) {
      throw const FormatException('Sales invoice snapshot identity mismatch');
    }
    return entry;
  }

  Map<String, dynamic> toJson() => {
    'operation_id': operationId,
    'restore_generation': restoreGeneration,
    'operation_created_at': operationCreatedAt.toUtc().toIso8601String(),
    'endpoint_path': endpointPath,
    'request_body': requestBody,
    if (documentSnapshot != null)
      'document_snapshot': documentSnapshot!.toJson(),
    'state': state == SalesInvoiceOutboxState.queued
        ? 'queued'
        : 'needs_review',
    if (rejectionStatus != null) 'rejection_status': rejectionStatus,
    if (rejectionMessage != null) 'rejection_message': rejectionMessage,
  };

  SalesInvoiceOutboxEntry reject(AccountingApiError failure) =>
      SalesInvoiceOutboxEntry(
        operationId: operationId,
        restoreGeneration: restoreGeneration,
        operationCreatedAt: operationCreatedAt,
        endpointPath: endpointPath,
        requestBody: requestBody,
        documentSnapshot: documentSnapshot,
        state: SalesInvoiceOutboxState.needsReview,
        rejectionStatus: failure.statusCode,
        rejectionMessage: failure.message,
      );

  SalesInvoiceOutboxEntry rebaseRestoreGeneration(int generation) {
    final rebasedRequest = request
      ..['restore_generation'] = generation
      ..['operation_created_at'] = operationCreatedAt.toUtc().toIso8601String();
    return SalesInvoiceOutboxEntry(
      operationId: operationId,
      restoreGeneration: generation,
      operationCreatedAt: operationCreatedAt,
      endpointPath: endpointPath,
      requestBody: jsonEncode(rebasedRequest),
      documentSnapshot: documentSnapshot?.rebasedToRestoreGeneration(
        generation,
      ),
    );
  }

  SalesInvoiceOutboxEntry rebaseAfterRestore(
    int generation,
    DateTime? restoreEpoch,
  ) {
    final now = DateTime.now().toUtc();
    final minimum = restoreEpoch?.toUtc().add(const Duration(seconds: 1));
    final createdAt = minimum != null && minimum.isAfter(now) ? minimum : now;
    final rebasedRequest = request
      ..['restore_generation'] = generation
      ..['operation_created_at'] = createdAt.toIso8601String();
    return SalesInvoiceOutboxEntry(
      operationId: operationId,
      restoreGeneration: generation,
      operationCreatedAt: createdAt,
      endpointPath: endpointPath,
      requestBody: jsonEncode(rebasedRequest),
      documentSnapshot: documentSnapshot?.rebasedToRestoreGeneration(
        generation,
      ),
    );
  }

  static String _endpointFor(Map<String, dynamic> request) {
    final replacement = request['replacement_invoice_id']?.toString() ?? '';
    return replacement.isEmpty
        ? 'accounting/invoices'
        : 'accounting/invoices/$replacement/replace';
  }
}

/// Durable source of truth for finalized, unacknowledged sales invoices.
class SalesInvoiceOutbox {
  SalesInvoiceOutbox(this.tenantId, this.branchId) {
    if (tenantId.trim().isEmpty || branchId.trim().isEmpty) {
      throw ArgumentError('Sales invoice outbox scope must be complete');
    }
  }

  final String tenantId;
  final String branchId;

  String get _key => 'ninesoft.sales_invoice.outbox.v1.$tenantId.$branchId';
  String get _tenantPrefix => 'ninesoft.sales_invoice.outbox.v1.$tenantId.';
  String get _tenantWriterKey => 'sales_invoice.$tenantId';

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

  Future<List<SalesInvoiceOutboxEntry>> _readKey(String key) async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Sales invoice outbox is not a list');
    }
    return decoded
        .map((value) {
          if (value is! Map) {
            throw const FormatException('Invalid sales invoice outbox row');
          }
          return SalesInvoiceOutboxEntry.fromJson(
            Map<String, dynamic>.from(value),
          );
        })
        .toList(growable: true);
  }

  Future<List<SalesInvoiceOutboxEntry>> list() => _readKey(_key);

  Future<int> count() async => (await list()).length;

  Future<void> discardLocal(String operationId) => _serial(() async {
    final entries = await list()
      ..removeWhere((entry) => entry.operationId == operationId);
    await _save(entries);
  });

  Future<void> _save(Iterable<SalesInvoiceOutboxEntry> entries) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
    if (!saved) throw StateError('Unable to persist sales invoice outbox');
  }

  Future<({String key, SalesInvoiceOutboxEntry entry})?> _findTenantOperation(
    String operationId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final keys = preferences.getKeys().where(
      (candidate) => candidate.startsWith(_tenantPrefix),
    );
    for (final key in keys) {
      for (final entry in await _readKey(key)) {
        if (entry.operationId == operationId) return (key: key, entry: entry);
      }
    }
    return null;
  }

  Future<bool> contains(String operationId) async =>
      operationId.isNotEmpty && await _findTenantOperation(operationId) != null;

  void _validateDocumentSnapshot(
    Map<String, dynamic> request,
    InvoiceDocument snapshot,
  ) {
    final operationId = request['local_operation_id']?.toString() ?? '';
    final generation = request['restore_generation'];
    final createdAt = DateTime.tryParse(
      request['operation_created_at']?.toString() ?? '',
    );
    final rawItems = request['items'];
    if (snapshot.localOperationId != operationId ||
        snapshot.restoreGenerationAtCreation != generation ||
        createdAt == null ||
        !snapshot.createdAt.toUtc().isAtSameMomentAs(createdAt.toUtc()) ||
        rawItems is! List ||
        snapshot.lines.length != rawItems.length) {
      throw ArgumentError('Sales invoice snapshot does not match request');
    }
    for (var index = 0; index < rawItems.length; index++) {
      final raw = rawItems[index];
      if (raw is! Map) {
        throw ArgumentError('Sales invoice snapshot line is invalid');
      }
      final item = Map<String, dynamic>.from(raw);
      final line = snapshot.lines[index];
      final numerator = item['price_numerator_minor'];
      final denominator = item['price_denominator'];
      if (item['name']?.toString() != line.name ||
          (item['product_id']?.toString() ?? '') != line.productId ||
          (item['sale_option_id']?.toString() ?? '') != line.saleOptionId ||
          item['quantity_milli'] !=
              (line.exactQuantityMilli ?? (line.quantity * 1000).round()) ||
          item['unit_price_minor'] != (line.unitPrice * 100).round() ||
          numerator != line.priceNumeratorMinor ||
          denominator != line.priceDenominator ||
          (item['price_overridden'] == true) != line.priceOverridden) {
        throw ArgumentError(
          'Sales invoice snapshot line does not match request',
        );
      }
    }
  }

  Future<void> enqueue(
    Map<String, dynamic> request, {
    InvoiceDocument? snapshot,
  }) => _serial(() async {
    final operationId = request['local_operation_id']?.toString() ?? '';
    final generation = request['restore_generation'];
    final createdAt = DateTime.tryParse(
      request['operation_created_at']?.toString() ?? '',
    )?.toUtc();
    final rawItems = request['items'];
    if (operationId.isEmpty ||
        (request['device_id']?.toString() ?? '').isEmpty ||
        request['branch_id']?.toString() != branchId ||
        generation is! int ||
        generation < 0 ||
        createdAt == null ||
        rawItems is! List ||
        rawItems.isEmpty) {
      throw ArgumentError('Incomplete immutable sales invoice request');
    }
    for (final raw in rawItems) {
      if (raw is! Map) {
        throw ArgumentError('Invalid immutable sales invoice line');
      }
      final item = Map<String, dynamic>.from(raw);
      if (item.containsKey('price_overridden') &&
          item['price_overridden'] is! bool) {
        throw ArgumentError('Invalid manual price intent marker');
      }
      if (item['price_overridden'] == true &&
          ((item['sale_option_id']?.toString() ?? '').isEmpty ||
              item['price_numerator_minor'] != item['unit_price_minor'] ||
              item['price_denominator'] != 1)) {
        throw ArgumentError('Manual price intent does not match line price');
      }
    }
    if (snapshot != null) _validateDocumentSnapshot(request, snapshot);
    final requestBody = jsonEncode(request);
    final candidate = SalesInvoiceOutboxEntry(
      operationId: operationId,
      restoreGeneration: generation,
      operationCreatedAt: createdAt,
      endpointPath: SalesInvoiceOutboxEntry._endpointFor(request),
      requestBody: requestBody,
      documentSnapshot: snapshot,
    );
    final existing = await _findTenantOperation(operationId);
    if (existing != null) {
      if (existing.entry.requestBody != candidate.requestBody ||
          existing.entry.endpointPath != candidate.endpointPath ||
          (existing.entry.documentSnapshot != null &&
              snapshot != null &&
              jsonEncode(existing.entry.documentSnapshot!.toJson()) !=
                  jsonEncode(snapshot.toJson()))) {
        throw StateError(
          'Sales invoice operation is used for different content',
        );
      }
      return;
    }
    final entries = await list()
      ..add(candidate);
    await _save(entries);
  });

  Future<void> _remove(String operationId, bool Function() isValid) =>
      _serial(() async {
        if (!isValid()) throw const SalesInvoiceResponseInvalidated();
        final entries = await list()
          ..removeWhere((entry) => entry.operationId == operationId);
        if (!isValid()) throw const SalesInvoiceResponseInvalidated();
        await _save(entries);
      });

  Future<bool> _markNeedsReview(
    String operationId,
    AccountingApiError failure,
    bool Function() isValid,
  ) => _serial(() async {
    if (!isValid()) return false;
    final entries = await list();
    final index = entries.indexWhere(
      (entry) => entry.operationId == operationId,
    );
    if (index < 0) return true;
    entries[index] = entries[index].reject(failure);
    if (!isValid()) return false;
    await _save(entries);
    return true;
  });

  Future<void> _replace(SalesInvoiceOutboxEntry replacement) =>
      _serial(() async {
        final entries = await list();
        final index = entries.indexWhere(
          (entry) => entry.operationId == replacement.operationId,
        );
        if (index < 0) {
          entries.add(replacement);
        } else {
          entries[index] = replacement;
        }
        await _save(entries);
      });

  bool _canRebaseAfterRestore(
    SalesInvoiceOutboxEntry entry,
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
          item['kind'] != 'sales_invoice' ||
          !_isRecoverablePostRestoreReason(item['reason'])) {
        continue;
      }
      final payload = item['payload'];
      if (payload is! Map) continue;
      SalesInvoiceOutboxEntry stored;
      try {
        stored = SalesInvoiceOutboxEntry.fromJson(
          Map<String, dynamic>.from(payload),
        );
      } on FormatException {
        continue;
      }
      if (stored.request['branch_id']?.toString() != branchId) {
        continue;
      }
      await _replace(stored);
      if (stored.documentSnapshot != null) {
        await InvoiceHistoryStore().save(
          tenantId,
          branchId,
          stored.documentSnapshot!,
          isValid: isValid,
        );
      }
      await quarantine.remove(stored.operationId);
    }
  }

  InvoiceDocument _validateAndBuildHistory(
    Map<String, dynamic> response,
    SalesInvoiceOutboxEntry entry,
  ) {
    final request = entry.request;
    for (final field in const ['id', 'number', 'branch_id']) {
      if (response[field] is! String || (response[field] as String).isEmpty) {
        throw FormatException('Incomplete sales acknowledgement: $field');
      }
    }
    if (response['payment_account_code'] is! String) {
      throw const FormatException(
        'Incomplete sales acknowledgement: payment_account_code',
      );
    }
    if (response['branch_id'] != branchId) {
      throw const FormatException('Sales acknowledgement branch mismatch');
    }
    for (final field in const [
      'total_minor',
      'paid_minor',
      'due_minor',
      'amount_tendered_minor',
    ]) {
      if (response[field] is! int) {
        throw FormatException('Incomplete sales acknowledgement: $field');
      }
    }
    final rawItems = request['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      throw const FormatException('Immutable sales request has no lines');
    }
    final rawAcknowledgedItems = response['items'];
    final acknowledgedItems = <Map<String, dynamic>>[];
    if (rawAcknowledgedItems != null) {
      if (rawAcknowledgedItems is! List ||
          rawAcknowledgedItems.length != rawItems.length) {
        throw const FormatException('Sales acknowledgement line mismatch');
      }
      for (final raw in rawAcknowledgedItems) {
        if (raw is! Map) {
          throw const FormatException('Sales acknowledgement line mismatch');
        }
        acknowledgedItems.add(Map<String, dynamic>.from(raw));
      }
    }
    final items = <Map<String, dynamic>>[];
    for (var index = 0; index < rawItems.length; index++) {
      final raw = rawItems[index];
      if (raw is! Map) {
        throw const FormatException('Invalid immutable sales line');
      }
      final line = Map<String, dynamic>.from(raw);
      final acknowledged = acknowledgedItems.isEmpty
          ? null
          : acknowledgedItems[index];
      final snapshotLine = entry.documentSnapshot?.lines[index];
      final quantity = line['quantity_milli'];
      final unitPrice = line['unit_price_minor'];
      final numerator = line['price_numerator_minor'];
      final denominator = line['price_denominator'];
      if (line['name'] is! String ||
          (line['name'] as String).isEmpty ||
          quantity is! int ||
          quantity <= 0 ||
          unitPrice is! int ||
          unitPrice < 0 ||
          ((numerator == null) != (denominator == null)) ||
          (numerator != null && (numerator is! int || numerator <= 0)) ||
          (denominator != null && (denominator is! int || denominator <= 0))) {
        throw const FormatException('Invalid immutable sales line snapshot');
      }
      if (acknowledged != null) {
        final acknowledgedNumerator =
            acknowledged['price_numerator_minor_snapshot'];
        final acknowledgedDenominator =
            acknowledged['price_denominator_snapshot'];
        if (acknowledged['quantity_milli'] != quantity ||
            acknowledged['unit_price_minor'] != unitPrice ||
            (acknowledged['product_id']?.toString() ?? '') !=
                (line['product_id']?.toString() ?? '') ||
            (acknowledged['sale_option_id']?.toString() ?? '') !=
                (line['sale_option_id']?.toString() ?? '') ||
            (acknowledged['price_overridden'] == true) !=
                (line['price_overridden'] == true) ||
            (numerator != null && acknowledgedNumerator != numerator) ||
            (denominator != null && acknowledgedDenominator != denominator)) {
          throw FormatException(
            'Sales acknowledgement line mismatch at index $index',
          );
        }
      }
      items.add({
        'product_name_snapshot':
            acknowledged?['product_name_snapshot'] ?? line['name'],
        'product_id': acknowledged?['product_id'] ?? line['product_id'],
        'sale_option_id':
            acknowledged?['sale_option_id'] ?? line['sale_option_id'],
        'quantity_milli': quantity,
        'unit_price_minor': unitPrice,
        'discount_minor':
            acknowledged?['discount_minor'] ?? line['discount_minor'] ?? 0,
        'price_numerator_minor_snapshot':
            acknowledged?['price_numerator_minor_snapshot'] ?? numerator,
        'price_denominator_snapshot':
            acknowledged?['price_denominator_snapshot'] ?? denominator,
        'price_overridden': acknowledged == null
            ? line['price_overridden'] == true
            : acknowledged['price_overridden'] == true,
        'option_unit_code_snapshot':
            acknowledged?['option_unit_code_snapshot'] ??
            snapshotLine?.optionUnitCode,
        'option_quantity_snapshot':
            acknowledged?['option_quantity_snapshot'] ??
            snapshotLine?.optionQuantity,
        'option_mass_g_snapshot':
            acknowledged?['option_mass_g_snapshot'] ??
            snapshotLine?.optionMassG,
        'display_unit_snapshot':
            acknowledged?['display_unit_snapshot'] ?? snapshotLine?.displayUnit,
        'weight_grams_milli_snapshot':
            acknowledged?['weight_grams_milli_snapshot'] ??
            snapshotLine?.weightGramsMilli,
      });
    }
    final merged = <String, dynamic>{
      ...response,
      'customer_name': request['customer_name'] ?? '',
      'customer_phone': request['customer_phone'] ?? '',
      'contact_id': request['contact_id'] ?? '',
      'items': items,
      'local_operation_id': entry.operationId,
      'restore_generation': entry.restoreGeneration,
      'occurred_at': entry.operationCreatedAt.toIso8601String(),
      'payment_channel':
          response['payment_channel'] ?? request['payment_channel'] ?? '',
      'payment_account_code':
          response['payment_account_code'] ??
          request['payment_account_code'] ??
          '',
      'notes': request['notes'] ?? '',
      'creator_display_name':
          response['creator_display_name'] ??
          entry.documentSnapshot?.employeeName ??
          '',
      'branch_label_snapshot': entry.documentSnapshot?.branchLabel ?? '',
    };
    final document = InvoiceDocument.fromServer(merged);
    if (document.serverInvoiceId.isEmpty ||
        document.serverNumber.isEmpty ||
        document.lines.length != items.length) {
      throw const FormatException('Incomplete cached sales acknowledgement');
    }
    return document;
  }

  Future<SalesInvoiceFlushResult> flush({
    required AccountingApi api,
    required int currentRestoreGeneration,
    DateTime? restoreEpoch,
    int maxPerCycle = 4,
    bool Function()? isResponseValid,
    bool Function(SalesInvoiceOutboxEntry entry)? canSend,
  }) async {
    if (!_flushing.add(_key)) return const SalesInvoiceFlushResult();
    final responseStillValid = isResponseValid ?? () => true;
    var sent = 0;
    var quarantined = 0;
    var needsReview = 0;
    var invalidated = 0;
    String? error;
    try {
      await _recoverSafeGenerationMismatch(
        currentRestoreGeneration: currentRestoreGeneration,
        restoreEpoch: restoreEpoch,
        isValid: responseStillValid,
      );
      for (final storedEntry in await list()) {
        var entry = storedEntry;
        if (sent >= maxPerCycle) break;
        if (!responseStillValid()) {
          invalidated++;
          break;
        }
        if (entry.state == SalesInvoiceOutboxState.needsReview) continue;
        final quarantine = QuarantinedOperationStore(tenantId);
        if (await quarantine.isDiscarded(entry.operationId, 'sales_invoice')) {
          await _remove(entry.operationId, responseStillValid);
          quarantined++;
          continue;
        }
        if (entry.restoreGeneration != currentRestoreGeneration &&
            _canRebaseAfterRestore(entry, restoreEpoch)) {
          entry = entry.rebaseRestoreGeneration(currentRestoreGeneration);
          await _replace(entry);
        }
        if (canSend != null && !canSend(entry)) break;
        try {
          final response = await api.postInvoiceRequest(entry.request);
          if (!responseStillValid()) {
            invalidated++;
            break;
          }
          final posted = _validateAndBuildHistory(response, entry);
          if (!responseStillValid()) {
            invalidated++;
            break;
          }
          await InvoiceHistoryStore().save(
            tenantId,
            branchId,
            posted,
            isValid: responseStillValid,
          );
          await _remove(entry.operationId, responseStillValid);
          sent++;
        } on InvoiceHistoryWriteInvalidated {
          invalidated++;
          break;
        } on SalesInvoiceResponseInvalidated {
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
      _flushing.remove(_key);
    }
    return SalesInvoiceFlushResult(
      sent: sent,
      quarantined: quarantined,
      needsReview: needsReview,
      invalidated: invalidated,
      error: error,
    );
  }
}

class SalesInvoiceResponseInvalidated implements Exception {
  const SalesInvoiceResponseInvalidated();
}

class SalesInvoiceFlushResult {
  const SalesInvoiceFlushResult({
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
