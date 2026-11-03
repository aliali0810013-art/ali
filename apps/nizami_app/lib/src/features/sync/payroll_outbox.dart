import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../accounting/accounting_api.dart';
import '../payroll/payroll_api.dart';
import '../payroll/payroll_cache.dart';
import '../payroll/payroll_models.dart';
import 'quarantined_operation_store.dart';

enum PayrollOperationKind {
  employeeCreate,
  employeeUpdate,
  employeeDeactivate,
  advancePost,
  advanceReversal,
  payrollRunApproval,
  payrollRunReversal,
  payrollPaymentPost,
  payrollPaymentReversal,
}

enum PayrollOutboxState { queued, needsReview }

extension PayrollOperationKindContract on PayrollOperationKind {
  String get wireName => switch (this) {
    PayrollOperationKind.employeeCreate => 'employee_create',
    PayrollOperationKind.employeeUpdate => 'employee_update',
    PayrollOperationKind.employeeDeactivate => 'employee_deactivate',
    PayrollOperationKind.advancePost => 'advance_post',
    PayrollOperationKind.advanceReversal => 'advance_reversal',
    PayrollOperationKind.payrollRunApproval => 'payroll_run_approval',
    PayrollOperationKind.payrollRunReversal => 'payroll_run_reversal',
    PayrollOperationKind.payrollPaymentPost => 'payroll_payment_post',
    PayrollOperationKind.payrollPaymentReversal => 'payroll_payment_reversal',
  };

  String method(String aggregateId) =>
      this == PayrollOperationKind.employeeUpdate ? 'PUT' : 'POST';

  String path(String aggregateId) => switch (this) {
    PayrollOperationKind.employeeCreate => 'accounting/employees',
    PayrollOperationKind.employeeUpdate => 'accounting/employees/$aggregateId',
    PayrollOperationKind.employeeDeactivate =>
      'accounting/employees/$aggregateId/deactivate',
    PayrollOperationKind.advancePost => 'accounting/employee-advances',
    PayrollOperationKind.advanceReversal =>
      'accounting/employee-advances/$aggregateId/reversals',
    PayrollOperationKind.payrollRunApproval => 'accounting/payroll-runs',
    PayrollOperationKind.payrollRunReversal =>
      'accounting/payroll-runs/$aggregateId/reversals',
    PayrollOperationKind.payrollPaymentPost =>
      'accounting/payroll-runs/$aggregateId/payments',
    PayrollOperationKind.payrollPaymentReversal =>
      'accounting/payroll-payments/$aggregateId/reversals',
  };

  String get aggregateType => switch (this) {
    PayrollOperationKind.employeeCreate ||
    PayrollOperationKind.employeeUpdate ||
    PayrollOperationKind.employeeDeactivate => 'employee',
    PayrollOperationKind.advancePost ||
    PayrollOperationKind.advanceReversal => 'employee_advance',
    PayrollOperationKind.payrollRunApproval ||
    PayrollOperationKind.payrollRunReversal => 'payroll_run',
    PayrollOperationKind.payrollPaymentPost ||
    PayrollOperationKind.payrollPaymentReversal => 'payroll_payment',
  };

  static PayrollOperationKind parse(String value) =>
      PayrollOperationKind.values.firstWhere(
        (kind) => kind.wireName == value,
        orElse: () =>
            throw const FormatException('Invalid payroll operation kind'),
      );
}

class PayrollOutboxEntry {
  const PayrollOutboxEntry({
    required this.operationId,
    required this.kind,
    required this.aggregateId,
    required this.restoreGeneration,
    required this.operationCreatedAt,
    required this.requestBody,
    this.state = PayrollOutboxState.queued,
    this.rejectionStatus,
    this.rejectionMessage,
  });

  final String operationId;
  final PayrollOperationKind kind;
  final String aggregateId;
  final int restoreGeneration;
  final DateTime operationCreatedAt;
  final String requestBody;
  final PayrollOutboxState state;
  final int? rejectionStatus;
  final String? rejectionMessage;

  String get method => kind.method(aggregateId);
  String get path => kind.path(aggregateId);

  Map<String, dynamic> get request {
    final decoded = jsonDecode(requestBody);
    if (decoded is! Map) {
      throw const FormatException('Payroll request is not an object');
    }
    return Map<String, dynamic>.from(decoded);
  }

  factory PayrollOutboxEntry.fromRequest({
    required PayrollOperationKind kind,
    required String aggregateId,
    required String branchId,
    required Map<String, dynamic> request,
  }) {
    final operationId = request['local_operation_id']?.toString() ?? '';
    final generation = request['restore_generation'];
    final created = DateTime.tryParse(
      request['operation_created_at']?.toString() ?? '',
    )?.toUtc();
    if (aggregateId.isEmpty ||
        operationId.isEmpty ||
        (request['device_id']?.toString() ?? '').isEmpty ||
        generation is! int ||
        generation < 0 ||
        created == null) {
      throw const FormatException('Incomplete immutable payroll request');
    }
    _validatePathBodyIdentity(kind, aggregateId, branchId, request);
    return PayrollOutboxEntry(
      operationId: operationId,
      kind: kind,
      aggregateId: aggregateId,
      restoreGeneration: generation,
      operationCreatedAt: created,
      requestBody: jsonEncode(request),
    );
  }

  factory PayrollOutboxEntry.fromJson(
    Map<String, dynamic> json, {
    required String branchId,
  }) {
    final kind = PayrollOperationKindContract.parse(
      json['kind']?.toString() ?? '',
    );
    final aggregateId = json['aggregate_id']?.toString() ?? '';
    final operationId = json['operation_id']?.toString() ?? '';
    final generation = json['restore_generation'];
    final created = DateTime.tryParse(
      json['operation_created_at']?.toString() ?? '',
    )?.toUtc();
    final body = json['request_body'];
    final state = switch (json['state']?.toString()) {
      'queued' => PayrollOutboxState.queued,
      'needs_review' => PayrollOutboxState.needsReview,
      _ => throw const FormatException('Invalid payroll outbox state'),
    };
    final status = json['rejection_status'];
    if (operationId.isEmpty ||
        aggregateId.isEmpty ||
        generation is! int ||
        generation < 0 ||
        created == null ||
        body is! String ||
        body.isEmpty ||
        (status != null && status is! int)) {
      throw const FormatException('Invalid payroll outbox entry');
    }
    final entry = PayrollOutboxEntry(
      operationId: operationId,
      kind: kind,
      aggregateId: aggregateId,
      restoreGeneration: generation,
      operationCreatedAt: created,
      requestBody: body,
      state: state,
      rejectionStatus: status as int?,
      rejectionMessage: json['rejection_message']?.toString(),
    );
    final request = entry.request;
    final bodyCreated = DateTime.tryParse(
      request['operation_created_at']?.toString() ?? '',
    )?.toUtc();
    if (request['local_operation_id'] != operationId ||
        request['restore_generation'] != generation ||
        request['device_id'] is! String ||
        bodyCreated == null ||
        !bodyCreated.isAtSameMomentAs(created) ||
        json['method'] != entry.method ||
        json['path'] != entry.path) {
      throw const FormatException('Payroll outbox identity mismatch');
    }
    _validatePathBodyIdentity(kind, aggregateId, branchId, request);
    return entry;
  }

  static void _validatePathBodyIdentity(
    PayrollOperationKind kind,
    String aggregateId,
    String branchId,
    Map<String, dynamic> request,
  ) {
    final bodyBranch = request['branch_id'];
    if (bodyBranch != null && bodyBranch != branchId) {
      throw const FormatException('Payroll request branch mismatch');
    }
    switch (kind) {
      case PayrollOperationKind.employeeCreate:
      case PayrollOperationKind.employeeUpdate:
      case PayrollOperationKind.employeeDeactivate:
        if (request['id'] != aggregateId || request['branch_id'] != branchId) {
          throw const FormatException('Employee request path/body mismatch');
        }
      case PayrollOperationKind.advancePost:
        if (request['employee_id'] is! String ||
            request['branch_id'] != branchId ||
            request['amount_minor'] is! int) {
          throw const FormatException('Invalid advance request identity');
        }
      case PayrollOperationKind.payrollRunApproval:
        if (request['branch_id'] != branchId ||
            request['employee_ids'] is! List) {
          throw const FormatException('Invalid payroll approval identity');
        }
      case PayrollOperationKind.payrollPaymentPost:
        if (request['items'] is! List || (request['items'] as List).isEmpty) {
          throw const FormatException('Invalid payroll payment identity');
        }
      case PayrollOperationKind.advanceReversal:
      case PayrollOperationKind.payrollRunReversal:
      case PayrollOperationKind.payrollPaymentReversal:
        if (request['reason'] is! String || request['occurred_at'] is! String) {
          throw const FormatException('Invalid payroll reversal identity');
        }
    }
  }

  Map<String, dynamic> toJson() => {
    'operation_id': operationId,
    'kind': kind.wireName,
    'aggregate_id': aggregateId,
    'method': method,
    'path': path,
    'restore_generation': restoreGeneration,
    'operation_created_at': operationCreatedAt.toUtc().toIso8601String(),
    'request_body': requestBody,
    'state': state == PayrollOutboxState.queued ? 'queued' : 'needs_review',
    if (rejectionStatus != null) 'rejection_status': rejectionStatus,
    if (rejectionMessage != null) 'rejection_message': rejectionMessage,
  };

  PayrollOutboxEntry reject(AccountingApiError error) => PayrollOutboxEntry(
    operationId: operationId,
    kind: kind,
    aggregateId: aggregateId,
    restoreGeneration: restoreGeneration,
    operationCreatedAt: operationCreatedAt,
    requestBody: requestBody,
    state: PayrollOutboxState.needsReview,
    rejectionStatus: error.statusCode,
    rejectionMessage: error.message,
  );
}

bool canSendPayrollOperation({
  required PayrollOperationKind kind,
  required String roleCode,
  required Iterable<String> permissions,
}) {
  if (roleCode == 'owner') return true;
  final permission = switch (kind) {
    PayrollOperationKind.employeeCreate ||
    PayrollOperationKind.employeeUpdate ||
    PayrollOperationKind.employeeDeactivate => 'payroll.manage',
    PayrollOperationKind.advancePost ||
    PayrollOperationKind.advanceReversal => 'payroll.advance',
    PayrollOperationKind.payrollRunApproval ||
    PayrollOperationKind.payrollRunReversal => 'payroll.approve',
    PayrollOperationKind.payrollPaymentPost ||
    PayrollOperationKind.payrollPaymentReversal => 'payroll.pay',
  };
  return permissions.contains(permission);
}

class PayrollOutbox {
  PayrollOutbox(this.tenantId, this.branchId, {PayrollCache? cache})
    : _cache = cache ?? PayrollCache(tenantId, branchId) {
    if (tenantId.trim().isEmpty || branchId.trim().isEmpty) {
      throw ArgumentError('Payroll outbox scope must be complete');
    }
  }

  final String tenantId;
  final String branchId;
  final PayrollCache _cache;

  String get _key => 'ninesoft.payroll.outbox.v1.$tenantId.$branchId';
  String get _tenantPrefix => 'ninesoft.payroll.outbox.v1.$tenantId.';
  String get _writerKey => 'payroll.$tenantId';
  static final Map<String, Future<void>> _writers = <String, Future<void>>{};
  static final Set<String> _flushing = <String>{};

  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _writers[_writerKey] ?? Future<void>.value();
    final gate = Completer<void>();
    _writers[_writerKey] = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
      if (identical(_writers[_writerKey], gate.future)) {
        _writers.remove(_writerKey);
      }
    }
  }

  Future<List<PayrollOutboxEntry>> _readKey(String key) async {
    if (!key.startsWith(_tenantPrefix)) {
      throw const FormatException('Payroll outbox key is outside tenant');
    }
    final keyBranch = key.substring(_tenantPrefix.length);
    if (keyBranch.isEmpty) {
      throw const FormatException('Payroll outbox branch missing');
    }
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Payroll outbox is not a list');
    }
    return decoded.map((row) {
      if (row is! Map) {
        throw const FormatException('Invalid payroll outbox row');
      }
      return PayrollOutboxEntry.fromJson(
        Map<String, dynamic>.from(row),
        branchId: keyBranch,
      );
    }).toList();
  }

  Future<List<PayrollOutboxEntry>> _listUnlocked() => _readKey(_key);
  Future<List<PayrollOutboxEntry>> list() => _serial(_listUnlocked);
  Future<int> count() async => (await list()).length;

  Future<void> _saveUnlocked(Iterable<PayrollOutboxEntry> entries) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    )) {
      throw StateError('Unable to persist payroll outbox');
    }
  }

  Future<PayrollOutboxEntry?> _findTenantOperation(String operationId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith(_tenantPrefix),
    )) {
      for (final entry in await _readKey(key)) {
        if (entry.operationId == operationId) return entry;
      }
    }
    return null;
  }

  Future<void> enqueue({
    required PayrollOperationKind kind,
    required String aggregateId,
    required Map<String, dynamic> request,
    bool Function()? isValid,
  }) => _serial(() async {
    if (isValid != null && !isValid()) throw const PayrollOutboxInvalidated();
    final candidate = PayrollOutboxEntry.fromRequest(
      kind: kind,
      aggregateId: aggregateId,
      branchId: branchId,
      request: request,
    );
    final existing = await _findTenantOperation(candidate.operationId);
    if (existing != null) {
      if (existing.kind != candidate.kind ||
          existing.aggregateId != candidate.aggregateId ||
          existing.requestBody != candidate.requestBody) {
        throw StateError(
          'Payroll operation is already used for different content',
        );
      }
      return;
    }
    final entries = await _listUnlocked()
      ..add(candidate);
    if (isValid != null && !isValid()) throw const PayrollOutboxInvalidated();
    await _saveUnlocked(entries);
  });

  Future<void> _remove(String operationId, bool Function() valid) =>
      _serial(() async {
        if (!valid()) throw const PayrollOutboxInvalidated();
        final entries = await _listUnlocked()
          ..removeWhere((entry) => entry.operationId == operationId);
        if (!valid()) throw const PayrollOutboxInvalidated();
        await _saveUnlocked(entries);
      });

  Future<bool> _markNeedsReview(
    String operationId,
    AccountingApiError error,
    bool Function() valid,
  ) => _serial(() async {
    if (!valid()) return false;
    final entries = await _listUnlocked();
    final index = entries.indexWhere(
      (entry) => entry.operationId == operationId,
    );
    if (index < 0) return true;
    entries[index] = entries[index].reject(error);
    if (!valid()) return false;
    await _saveUnlocked(entries);
    return true;
  });

  bool _invalidRestore(
    PayrollOutboxEntry entry,
    int generation,
    DateTime? epoch,
  ) =>
      entry.restoreGeneration != generation ||
      (epoch != null && !entry.operationCreatedAt.isAfter(epoch.toUtc()));

  Future<bool> _dependenciesSatisfied(
    PayrollOutboxEntry entry,
    List<PayrollOutboxEntry> pending,
  ) async {
    final envelope = await _cache.read();
    final request = entry.request;
    Employee? employeeById(String id) =>
        envelope.employees.where((row) => row.id == id).firstOrNull;
    EmployeeAdvance? advanceById(String id) =>
        envelope.employeeAdvances.where((row) => row.id == id).firstOrNull;
    PayrollRun? runById(String id) =>
        envelope.payrollRuns.where((row) => row.id == id).firstOrNull;
    PayrollPayment? paymentById(String id) =>
        envelope.payrollPayments.where((row) => row.id == id).firstOrNull;
    switch (entry.kind) {
      case PayrollOperationKind.employeeCreate:
        return true;
      case PayrollOperationKind.employeeUpdate:
        final employee = employeeById(entry.aggregateId);
        return employee != null &&
            employee.version == request['expected_version'];
      case PayrollOperationKind.employeeDeactivate:
        final id = entry.aggregateId;
        final pendingFinance = pending.any((candidate) {
          final body = candidate.request;
          if (candidate.kind == PayrollOperationKind.advancePost) {
            return body['employee_id'] == id;
          }
          if (candidate.kind == PayrollOperationKind.payrollRunApproval) {
            final ids = body['employee_ids'];
            return body['selection_mode'] == 'all' ||
                (ids is List && ids.contains(id));
          }
          return false;
        });
        final employee = employeeById(id);
        return employee != null &&
            employee.version == request['expected_version'] &&
            !pendingFinance;
      case PayrollOperationKind.advancePost:
        return employeeById(request['employee_id']?.toString() ?? '')?.active ==
            true;
      case PayrollOperationKind.advanceReversal:
        final advance = advanceById(entry.aggregateId);
        final consumingRuns = envelope.payrollAdvanceAllocations
            .where((row) => row.employeeAdvanceId == entry.aggregateId)
            .map((row) => runById(row.payrollRunId));
        return advance?.status == 'posted' &&
            consumingRuns.every((run) => run?.status == 'reversed');
      case PayrollOperationKind.payrollRunApproval:
        final ids = (request['employee_ids'] as List? ?? const [])
            .map((id) => id.toString())
            .toSet();
        final employeesReady = request['selection_mode'] == 'all'
            ? envelope.employees.any((employee) => employee.active)
            : ids.every((id) => employeeById(id)?.active == true);
        final pendingRelatedAdvanceReversal = pending.any((candidate) {
          if (candidate.kind != PayrollOperationKind.advanceReversal) {
            return false;
          }
          final employeeId = advanceById(candidate.aggregateId)?.employeeId;
          return employeeId != null &&
              (request['selection_mode'] == 'all' || ids.contains(employeeId));
        });
        return employeesReady &&
            !pendingRelatedAdvanceReversal &&
            !pending.any(
              (candidate) =>
                  candidate.kind == PayrollOperationKind.advancePost ||
                  candidate.kind == PayrollOperationKind.employeeCreate ||
                  candidate.kind == PayrollOperationKind.employeeUpdate,
            );
      case PayrollOperationKind.payrollPaymentPost:
        return runById(entry.aggregateId)?.status == 'approved';
      case PayrollOperationKind.payrollPaymentReversal:
        return paymentById(entry.aggregateId)?.status == 'posted';
      case PayrollOperationKind.payrollRunReversal:
        final run = runById(entry.aggregateId);
        final payments = envelope.payrollPayments.where(
          (payment) =>
              payment.payrollRunId == entry.aggregateId &&
              payment.documentKind == 'payroll_payment',
        );
        return run?.status == 'approved' &&
            payments.every((payment) => payment.status == 'reversed') &&
            !pending.any(
              (candidate) =>
                  candidate.kind == PayrollOperationKind.payrollPaymentPost ||
                  candidate.kind == PayrollOperationKind.payrollPaymentReversal,
            );
    }
  }

  Future<AccountingApiError?> _terminalDependencyFailure(
    PayrollOutboxEntry entry,
    List<PayrollOutboxEntry> pending,
    Set<String> dependencyReviewOperationIds,
  ) async {
    final envelope = await _cache.read();
    if (entry.kind == PayrollOperationKind.payrollRunApproval) {
      final request = entry.request;
      final ids = (request['employee_ids'] as List? ?? const [])
          .map((id) => id.toString())
          .toSet();
      final hasRejectedRelatedAdvanceReversal = pending.any((candidate) {
        if (candidate.kind != PayrollOperationKind.advanceReversal ||
            (candidate.state != PayrollOutboxState.needsReview &&
                !dependencyReviewOperationIds.contains(
                  candidate.operationId,
                ))) {
          return false;
        }
        final advance = envelope.employeeAdvances
            .where((row) => row.id == candidate.aggregateId)
            .firstOrNull;
        return advance != null &&
            (request['selection_mode'] == 'all' ||
                ids.contains(advance.employeeId));
      });
      if (hasRejectedRelatedAdvanceReversal) {
        return const AccountingApiError(
          'PAYROLL_RUN_APPROVAL_BLOCKED_BY_ADVANCE_REVERSAL_REVIEW',
          statusCode: 409,
        );
      }
    }
    if (entry.kind == PayrollOperationKind.payrollRunReversal) {
      final blockingPayments = envelope.payrollPayments.where(
        (payment) =>
            payment.payrollRunId == entry.aggregateId &&
            payment.documentKind == 'payroll_payment' &&
            payment.status != 'reversed',
      );
      final hasPendingResolution = pending.any((candidate) {
        if (candidate.kind == PayrollOperationKind.payrollPaymentPost) {
          return candidate.aggregateId == entry.aggregateId;
        }
        if (candidate.kind != PayrollOperationKind.payrollPaymentReversal) {
          return false;
        }
        return envelope.payrollPayments.any(
          (payment) =>
              payment.id == candidate.aggregateId &&
              payment.payrollRunId == entry.aggregateId,
        );
      });
      if (blockingPayments.isNotEmpty && !hasPendingResolution) {
        return const AccountingApiError(
          'PAYROLL_RUN_REVERSAL_REQUIRES_PAYMENT_REVERSAL',
          statusCode: 409,
        );
      }
    }
    if (entry.kind == PayrollOperationKind.advanceReversal) {
      final blockingRunIds = envelope.payrollAdvanceAllocations
          .where((row) => row.employeeAdvanceId == entry.aggregateId)
          .map((row) => row.payrollRunId)
          .where(
            (runId) => envelope.payrollRuns.any(
              (run) => run.id == runId && run.status != 'reversed',
            ),
          )
          .toSet();
      final pendingRunReversals = pending
          .where(
            (candidate) =>
                candidate.kind == PayrollOperationKind.payrollRunReversal,
          )
          .map((candidate) => candidate.aggregateId)
          .toSet();
      if (blockingRunIds.isNotEmpty &&
          !pendingRunReversals.containsAll(blockingRunIds)) {
        return const AccountingApiError(
          'ADVANCE_REVERSAL_REQUIRES_PAYROLL_RUN_REVERSAL',
          statusCode: 409,
        );
      }
    }
    return null;
  }

  Map<String, dynamic> _validateAcknowledgement(
    PayrollOutboxEntry entry,
    Map<String, dynamic> response,
  ) {
    final request = entry.request;
    final key = switch (entry.kind.aggregateType) {
      'employee' => 'employee',
      'employee_advance' => 'advance',
      'payroll_run' => 'run',
      _ => 'payment',
    };
    final raw = response[key];
    if (raw is! Map) throw FormatException('Missing canonical payroll $key');
    final canonical = Map<String, dynamic>.from(raw);
    if (canonical['branch_id'] != branchId ||
        (canonical['tenant_id'] != null &&
            canonical['tenant_id'] != tenantId)) {
      throw const FormatException('Payroll acknowledgement scope mismatch');
    }
    if (canonical['device_id'] != request['device_id'] ||
        canonical['local_operation_id'] != entry.operationId ||
        canonical['restore_generation'] != entry.restoreGeneration) {
      throw const FormatException('Payroll acknowledgement operation mismatch');
    }
    if (entry.kind.aggregateType == 'employee') {
      final employee = Employee.fromJson(
        canonical,
        tenantId: tenantId,
        branchId: branchId,
      );
      final expectedVersion = entry.kind == PayrollOperationKind.employeeCreate
          ? 1
          : (request['expected_version'] as int) + 1;
      if (employee.id != entry.aggregateId ||
          employee.version != expectedVersion) {
        throw const FormatException(
          'Employee acknowledgement identity mismatch',
        );
      }
      if (entry.kind == PayrollOperationKind.employeeDeactivate &&
          employee.active) {
        throw const FormatException(
          'Employee deactivation was not acknowledged',
        );
      }
      return response;
    }
    switch (entry.kind) {
      case PayrollOperationKind.advancePost:
        if (canonical['employee_id'] != request['employee_id'] ||
            canonical['amount_minor'] != request['amount_minor']) {
          throw const FormatException(
            'Advance acknowledgement content mismatch',
          );
        }
      case PayrollOperationKind.advanceReversal:
      case PayrollOperationKind.payrollRunReversal:
      case PayrollOperationKind.payrollPaymentReversal:
        if (canonical['reversal_of_id'] != entry.aggregateId ||
            response['original'] is! Map) {
          throw const FormatException(
            'Payroll reversal acknowledgement mismatch',
          );
        }
      case PayrollOperationKind.payrollPaymentPost:
        if (canonical['payroll_run_id'] != entry.aggregateId) {
          throw const FormatException('Payroll payment run mismatch');
        }
      case PayrollOperationKind.payrollRunApproval:
      case PayrollOperationKind.employeeCreate:
      case PayrollOperationKind.employeeUpdate:
      case PayrollOperationKind.employeeDeactivate:
        break;
    }
    return response;
  }

  Future<PayrollFlushResult> flush({
    required PayrollApi api,
    required int currentRestoreGeneration,
    DateTime? restoreEpoch,
    int maxPerCycle = 12,
    bool Function()? isResponseValid,
    bool Function(PayrollOutboxEntry entry)? canSend,
  }) async {
    if (!_flushing.add(_writerKey)) return const PayrollFlushResult();
    final valid = isResponseValid ?? () => true;
    var sent = 0;
    var quarantined = 0;
    var needsReview = 0;
    var invalidated = 0;
    final sentKinds = <PayrollOperationKind>{};
    final completedOperationIds = <String>{};
    final dependencyReviewOperationIds = <String>{};
    String? error;
    try {
      var attempted = 0;
      final entries = await list();
      bool remainsDependency(
        PayrollOutboxEntry candidate,
        String currentOperationId,
      ) {
        if (candidate.operationId == currentOperationId) return false;
        if (candidate.state == PayrollOutboxState.needsReview) {
          return candidate.kind == PayrollOperationKind.advanceReversal;
        }
        return candidate.state == PayrollOutboxState.queued &&
            (!completedOperationIds.contains(candidate.operationId) ||
                dependencyReviewOperationIds.contains(candidate.operationId));
      }

      var madeProgress = true;
      var stop = false;
      while (!stop && madeProgress && attempted < maxPerCycle) {
        madeProgress = false;
        for (var index = 0; index < entries.length; index++) {
          final entry = entries[index];
          if (completedOperationIds.contains(entry.operationId)) continue;
          if (!valid()) {
            invalidated++;
            stop = true;
            break;
          }
          if (entry.state == PayrollOutboxState.needsReview) continue;
          final quarantine = QuarantinedOperationStore(tenantId);
          if (await quarantine.isDiscarded(entry.operationId, 'payroll')) {
            await _remove(entry.operationId, valid);
            quarantined++;
            completedOperationIds.add(entry.operationId);
            madeProgress = true;
            continue;
          }
          if (_invalidRestore(entry, currentRestoreGeneration, restoreEpoch)) {
            await quarantine.quarantine(
              operationId: entry.operationId,
              kind: 'payroll',
              reason: entry.restoreGeneration != currentRestoreGeneration
                  ? 'restore_generation_mismatch'
                  : 'created_before_restore',
              payload: entry.toJson(),
            );
            await _remove(entry.operationId, valid);
            quarantined++;
            completedOperationIds.add(entry.operationId);
            madeProgress = true;
            continue;
          }
          final pending = entries
              .where(
                (candidate) => remainsDependency(candidate, entry.operationId),
              )
              .toList(growable: false);
          if (!await _dependenciesSatisfied(entry, pending)) continue;
          if (canSend != null && !canSend(entry)) continue;
          if (attempted >= maxPerCycle) {
            stop = true;
            break;
          }
          attempted++;
          try {
            final response = await api.postRequestBody(
              method: entry.method,
              path: entry.path,
              requestBody: entry.requestBody,
            );
            if (!valid()) {
              invalidated++;
              stop = true;
              break;
            }
            final canonical = _validateAcknowledgement(entry, response);
            final key = switch (entry.kind.aggregateType) {
              'employee' => 'employee',
              'employee_advance' => 'advance',
              'payroll_run' => 'run',
              _ => 'payment',
            };
            final aggregateId = (canonical[key] as Map)['id']?.toString() ?? '';
            if (aggregateId.isEmpty) {
              throw const FormatException('Payroll acknowledgement has no ID');
            }
            await _cache.mergeRemoteDetail(
              aggregateType: entry.kind.aggregateType,
              aggregateId: aggregateId,
              detail: canonical,
              isValid: valid,
            );
            await _remove(entry.operationId, valid);
            sent++;
            sentKinds.add(entry.kind);
            completedOperationIds.add(entry.operationId);
            madeProgress = true;
          } on PayrollCacheWriteInvalidated {
            invalidated++;
            stop = true;
            break;
          } on PayrollOutboxInvalidated {
            invalidated++;
            stop = true;
            break;
          } on AccountingApiError catch (failure) {
            if (!valid()) {
              invalidated++;
              stop = true;
              break;
            }
            if (failure.restoreBoundaryViolation) {
              await quarantine.quarantine(
                operationId: entry.operationId,
                kind: 'payroll',
                reason: failure.message,
                payload: entry.toJson(),
              );
              await _remove(entry.operationId, valid);
              quarantined++;
              completedOperationIds.add(entry.operationId);
              madeProgress = true;
              error = failure.toString();
              continue;
            }
            if (failure.definitelyRejected) {
              if (!await _markNeedsReview(entry.operationId, failure, valid)) {
                invalidated++;
                break;
              }
              needsReview++;
              completedOperationIds.add(entry.operationId);
              dependencyReviewOperationIds.add(entry.operationId);
              madeProgress = true;
              error = failure.toString();
              continue;
            }
            error = failure.toString();
            stop = true;
            break;
          } catch (failure) {
            if (!valid()) {
              invalidated++;
              break;
            }
            error = failure.toString();
            stop = true;
            break;
          }
        }
        if (!stop && !madeProgress) {
          for (final entry in entries.where(
            (candidate) =>
                candidate.state == PayrollOutboxState.queued &&
                !completedOperationIds.contains(candidate.operationId),
          )) {
            if (canSend != null && !canSend(entry)) continue;
            final pending = entries
                .where(
                  (candidate) =>
                      remainsDependency(candidate, entry.operationId),
                )
                .toList(growable: false);
            final failure = await _terminalDependencyFailure(
              entry,
              pending,
              dependencyReviewOperationIds,
            );
            if (failure == null) continue;
            if (!await _markNeedsReview(entry.operationId, failure, valid)) {
              invalidated++;
              stop = true;
              break;
            }
            needsReview++;
            completedOperationIds.add(entry.operationId);
            dependencyReviewOperationIds.add(entry.operationId);
            madeProgress = true;
            error = failure.toString();
            break;
          }
        }
      }
    } finally {
      _flushing.remove(_writerKey);
    }
    return PayrollFlushResult(
      sent: sent,
      quarantined: quarantined,
      needsReview: needsReview,
      invalidated: invalidated,
      sentKinds: Set.unmodifiable(sentKinds),
      error: error,
    );
  }
}

class PayrollOutboxInvalidated implements Exception {
  const PayrollOutboxInvalidated();
}

class PayrollFlushResult {
  const PayrollFlushResult({
    this.sent = 0,
    this.quarantined = 0,
    this.needsReview = 0,
    this.invalidated = 0,
    this.sentKinds = const {},
    this.error,
  });

  final int sent;
  final int quarantined;
  final int needsReview;
  final int invalidated;
  final Set<PayrollOperationKind> sentKinds;
  final String? error;
}
