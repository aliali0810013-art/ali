import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'payroll_models.dart';

class PayrollCacheWriteInvalidated implements Exception {
  const PayrollCacheWriteInvalidated();
}

/// The complete canonical payroll state for one tenant branch lives under one
/// SharedPreferences key. Drafts and outbox entries intentionally live elsewhere.
class PayrollCache {
  PayrollCache(this.tenantId, this.branchId) {
    if (tenantId.trim().isEmpty || branchId.trim().isEmpty) {
      throw ArgumentError('Payroll cache scope must be complete');
    }
  }

  final String tenantId;
  final String branchId;

  String get _key => 'ninesoft.payroll.cache.v1.$tenantId.$branchId';
  static final Map<String, Future<void>> _writers = <String, Future<void>>{};

  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _writers[_key] ?? Future<void>.value();
    final gate = Completer<void>();
    _writers[_key] = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
      if (identical(_writers[_key], gate.future)) _writers.remove(_key);
    }
  }

  Future<PayrollEnvelope> read() => _serial(_readUnlocked);

  Future<PayrollEnvelope> _readUnlocked() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return PayrollEnvelope.empty();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Payroll cache envelope is not an object');
    }
    return _parseEnvelope(Map<String, dynamic>.from(decoded));
  }

  PayrollEnvelope _parseEnvelope(Map<String, dynamic> value) {
    List<T> rows<T>(String key, T Function(Map<String, dynamic>) parse) {
      final source = value[key];
      if (source is! List) {
        throw FormatException('Missing payroll cache collection: $key');
      }
      return source
          .map((raw) {
            if (raw is! Map) {
              throw FormatException('Invalid payroll row in $key');
            }
            return parse(Map<String, dynamic>.from(raw));
          })
          .toList(growable: false);
    }

    final envelope = PayrollEnvelope(
      employees: rows(
        'employees',
        (row) => Employee.fromJson(row, tenantId: tenantId, branchId: branchId),
      ),
      employeeAdvances: rows(
        'employee_advances',
        (row) => EmployeeAdvance.fromJson(
          row,
          tenantId: tenantId,
          branchId: branchId,
        ),
      ),
      payrollRuns: rows(
        'payroll_runs',
        (row) =>
            PayrollRun.fromJson(row, tenantId: tenantId, branchId: branchId),
      ),
      payrollRunItems: rows(
        'payroll_run_items',
        (row) => PayrollRunItem.fromJson(
          row,
          tenantId: tenantId,
          branchId: branchId,
        ),
      ),
      payrollAdvanceAllocations: rows(
        'payroll_advance_allocations',
        (row) => PayrollAdvanceAllocation.fromJson(
          row,
          tenantId: tenantId,
          branchId: branchId,
        ),
      ),
      payrollPeriodClaims: rows(
        'payroll_period_claims',
        (row) => PayrollPeriodClaim.fromJson(
          row,
          tenantId: tenantId,
          branchId: branchId,
        ),
      ),
      payrollPayments: rows(
        'payroll_payments',
        (row) => PayrollPayment.fromJson(
          row,
          tenantId: tenantId,
          branchId: branchId,
        ),
      ),
      payrollPaymentItems: rows(
        'payroll_payment_items',
        (row) => PayrollPaymentItem.fromJson(
          row,
          tenantId: tenantId,
          branchId: branchId,
        ),
      ),
    );
    _validateRelationships(envelope);
    return envelope.immutable();
  }

  Future<void> replaceSnapshot(
    Map<String, dynamic> snapshot, {
    bool Function()? isValid,
  }) => _serial(() async {
    final collections = <String, List<dynamic>>{};
    for (final name in const [
      'employees',
      'employee_advances',
      'payroll_runs',
      'payroll_run_items',
      'payroll_advance_allocations',
      'payroll_period_claims',
      'payroll_payments',
      'payroll_payment_items',
    ]) {
      final raw = snapshot[name];
      if (raw is! List) {
        throw FormatException('Restore snapshot is missing $name');
      }
      collections[name] = raw
          .where((item) {
            if (item is! Map) {
              throw FormatException('Invalid payroll snapshot $name');
            }
            final rowBranch = item['branch_id']?.toString() ?? '';
            if (rowBranch == branchId &&
                item['tenant_id'] != null &&
                item['tenant_id']?.toString() != tenantId) {
              throw const FormatException('Payroll snapshot tenant mismatch');
            }
            return rowBranch == branchId;
          })
          .toList(growable: false);
    }
    final envelope = _parseEnvelope(collections);
    await _writeUnlocked(envelope, isValid: isValid);
  });

  Future<void> mergeRemoteDetail({
    required String aggregateType,
    required String aggregateId,
    required Map<String, dynamic> detail,
    bool Function()? isValid,
  }) => _serial(() async {
    if (isValid != null && !isValid()) {
      throw const PayrollCacheWriteInvalidated();
    }
    final current = (await _readUnlocked()).toJson();
    switch (aggregateType) {
      case 'employee':
        final raw = _requiredMap(detail, 'employee');
        final employee = Employee.fromJson(
          raw,
          tenantId: tenantId,
          branchId: branchId,
        );
        if (employee.id != aggregateId) {
          throw const FormatException('Employee detail identity mismatch');
        }
        _upsert(current['employees'] as List, employee.toJson());
      case 'employee_advance':
        _mergeAdvance(current, aggregateId, detail);
      case 'payroll_run':
        _mergeRun(current, aggregateId, detail);
      case 'payroll_payment':
        _mergePayment(current, aggregateId, detail);
      default:
        throw FormatException('Unsupported payroll aggregate: $aggregateType');
    }
    final envelope = _parseEnvelope(current);
    await _writeUnlocked(envelope, isValid: isValid);
  });

  void _mergeAdvance(
    Map<String, dynamic> envelope,
    String aggregateId,
    Map<String, dynamic> detail,
  ) {
    final advance = EmployeeAdvance.fromJson(
      _requiredMap(detail, 'advance'),
      tenantId: tenantId,
      branchId: branchId,
    );
    if (advance.id != aggregateId) {
      throw const FormatException('Advance detail identity mismatch');
    }
    final rows = envelope['employee_advances'] as List;
    _upsert(rows, advance.toJson());
    _validateJournal(detail['journal'], advance.id, advance.documentKind);
    if (detail['original'] != null) {
      final original = EmployeeAdvance.fromJson(
        _requiredMap(detail, 'original'),
        tenantId: tenantId,
        branchId: branchId,
      );
      if (advance.reversalOfId != original.id ||
          original.status != 'reversed') {
        throw const FormatException('Advance reversal original mismatch');
      }
      _upsert(rows, original.toJson());
    }
    if (detail['employee_balance_minor'] is! int) {
      throw const FormatException('Incomplete canonical advance detail');
    }
  }

  void _mergeRun(
    Map<String, dynamic> envelope,
    String aggregateId,
    Map<String, dynamic> detail,
  ) {
    final run = PayrollRun.fromJson(
      _requiredMap(detail, 'run'),
      tenantId: tenantId,
      branchId: branchId,
    );
    if (run.id != aggregateId) {
      throw const FormatException('Payroll run detail identity mismatch');
    }
    _validateJournal(detail['journal'], run.id, run.documentKind);
    _upsert(envelope['payroll_runs'] as List, run.toJson());
    if (detail['original'] != null) {
      final original = PayrollRun.fromJson(
        _requiredMap(detail, 'original'),
        tenantId: tenantId,
        branchId: branchId,
      );
      if (run.reversalOfId != original.id || original.status != 'reversed') {
        throw const FormatException('Payroll run reversal original mismatch');
      }
      _upsert(envelope['payroll_runs'] as List, original.toJson());
    }
    final rawItems = detail['items'];
    final rawAllocations = detail['allocations'];
    if (rawItems is! List ||
        rawAllocations is! List ||
        detail['totals'] is! Map) {
      throw const FormatException('Incomplete canonical payroll run detail');
    }
    final totals = Map<String, dynamic>.from(detail['totals'] as Map);
    final runJson = run.toJson();
    if (totals['gross_minor'] != runJson['total_gross_minor'] ||
        totals['applied_advance_minor'] != runJson['total_applied_minor'] ||
        totals['net_minor'] != runJson['total_net_minor']) {
      throw const FormatException(
        'Payroll run totals acknowledgement mismatch',
      );
    }
    if (run.documentKind == 'payroll_run') {
      final items = rawItems
          .map((raw) {
            if (raw is! Map) {
              throw const FormatException('Invalid payroll run item');
            }
            final row = Map<String, dynamic>.from(raw);
            final employee = _requiredMap(row, 'employee');
            return PayrollRunItem.fromJson(
              {
                ...row,
                'tenant_id': tenantId,
                'branch_id': branchId,
                'payroll_run_id': run.id,
                'employee_id': employee['id'],
                'employee_name_snapshot': employee['name'],
                'employee_phone_snapshot': employee['phone'],
                'employee_base_salary_minor_snapshot':
                    employee['base_salary_minor'],
              },
              tenantId: tenantId,
              branchId: branchId,
            ).toJson();
          })
          .toList(growable: false);
      final allocations = rawAllocations
          .map((raw) {
            if (raw is! Map) {
              throw const FormatException('Invalid payroll allocation');
            }
            return PayrollAdvanceAllocation.fromJson(
              {
                ...Map<String, dynamic>.from(raw),
                'tenant_id': tenantId,
                'branch_id': branchId,
                'payroll_run_id': run.id,
              },
              tenantId: tenantId,
              branchId: branchId,
            ).toJson();
          })
          .toList(growable: false);
      final itemGross = items.fold<int>(
        0,
        (sum, item) => sum + (item['gross_minor'] as int),
      );
      final itemApplied = items.fold<int>(
        0,
        (sum, item) => sum + (item['applied_advance_minor'] as int),
      );
      final itemNet = items.fold<int>(
        0,
        (sum, item) => sum + (item['net_minor'] as int),
      );
      if (itemGross != totals['gross_minor'] ||
          itemApplied != totals['applied_advance_minor'] ||
          itemNet != totals['net_minor']) {
        throw const FormatException('Payroll run item totals mismatch');
      }
      _replaceChildren(
        envelope['payroll_run_items'] as List,
        'payroll_run_id',
        run.id,
        items,
      );
      _replaceChildren(
        envelope['payroll_advance_allocations'] as List,
        'payroll_run_id',
        run.id,
        allocations,
      );
    }
  }

  void _mergePayment(
    Map<String, dynamic> envelope,
    String aggregateId,
    Map<String, dynamic> detail,
  ) {
    final payment = PayrollPayment.fromJson(
      _requiredMap(detail, 'payment'),
      tenantId: tenantId,
      branchId: branchId,
    );
    if (payment.id != aggregateId) {
      throw const FormatException('Payroll payment detail identity mismatch');
    }
    _validateJournal(detail['journal'], payment.id, payment.documentKind);
    _upsert(envelope['payroll_payments'] as List, payment.toJson());
    if (detail['original'] != null) {
      final original = PayrollPayment.fromJson(
        _requiredMap(detail, 'original'),
        tenantId: tenantId,
        branchId: branchId,
      );
      if (payment.reversalOfId != original.id ||
          original.status != 'reversed') {
        throw const FormatException(
          'Payroll payment reversal original mismatch',
        );
      }
      _upsert(envelope['payroll_payments'] as List, original.toJson());
    }
    final rawItems = detail['items'];
    final remaining = detail['remaining'];
    if (rawItems is! List || remaining is! List) {
      throw const FormatException(
        'Incomplete canonical payroll payment detail',
      );
    }
    if (payment.documentKind == 'payroll_payment') {
      final items = rawItems
          .map((raw) {
            if (raw is! Map) {
              throw const FormatException('Invalid payroll payment item');
            }
            final row = Map<String, dynamic>.from(raw);
            final employee = _requiredMap(row, 'employee');
            return PayrollPaymentItem.fromJson(
              {
                ...row,
                'tenant_id': tenantId,
                'branch_id': branchId,
                'payroll_payment_id': payment.id,
                'employee_id': employee['id'],
                'employee_name_snapshot': employee['name'],
                'employee_phone_snapshot': employee['phone'],
              },
              tenantId: tenantId,
              branchId: branchId,
            ).toJson();
          })
          .toList(growable: false);
      final itemTotal = items.fold<int>(
        0,
        (sum, item) => sum + (item['amount_minor'] as int),
      );
      if (itemTotal != payment.toJson()['total_minor']) {
        throw const FormatException('Payroll payment item total mismatch');
      }
      _replaceChildren(
        envelope['payroll_payment_items'] as List,
        'payroll_payment_id',
        payment.id,
        items,
      );
    }
    for (final raw in remaining) {
      if (raw is! Map ||
          raw['payroll_run_item_id'] is! String ||
          raw['remaining_minor'] is! int) {
        throw const FormatException('Invalid payroll payment remaining row');
      }
      final rows = envelope['payroll_run_items'] as List;
      final index = rows.indexWhere(
        (row) => row is Map && row['id'] == raw['payroll_run_item_id'],
      );
      if (index < 0) {
        throw const FormatException(
          'Payment remaining references unknown run item',
        );
      }
      rows[index] = {
        ...Map<String, dynamic>.from(rows[index] as Map),
        'remaining_minor': raw['remaining_minor'],
      };
    }
  }

  static Map<String, dynamic> _requiredMap(
    Map<String, dynamic> source,
    String field,
  ) {
    final value = source[field];
    if (value is! Map) throw FormatException('Missing payroll detail: $field');
    return Map<String, dynamic>.from(value);
  }

  void _validateJournal(Object? raw, String aggregateId, String referenceType) {
    if (raw is! Map) {
      throw const FormatException('Missing canonical payroll journal');
    }
    final journal = Map<String, dynamic>.from(raw);
    if (journal['id'] is! String ||
        (journal['id'] as String).isEmpty ||
        journal['branch_id'] != branchId ||
        journal['reference_type'] != referenceType ||
        journal['reference_id'] != aggregateId ||
        journal['posted_at'] is! String ||
        journal['lines'] is! List) {
      throw const FormatException('Payroll journal identity mismatch');
    }
  }

  static void _upsert(List<dynamic> rows, Map<String, dynamic> row) {
    final index = rows.indexWhere(
      (current) => current is Map && current['id'] == row['id'],
    );
    if (index < 0) {
      rows.add(row);
    } else {
      rows[index] = row;
    }
  }

  static void _replaceChildren(
    List<dynamic> rows,
    String parentField,
    String parentId,
    List<Map<String, dynamic>> replacements,
  ) {
    rows.removeWhere(
      (row) => row is Map && row[parentField]?.toString() == parentId,
    );
    rows.addAll(replacements);
  }

  Future<void> _writeUnlocked(
    PayrollEnvelope envelope, {
    bool Function()? isValid,
  }) async {
    if (isValid != null && !isValid()) {
      throw const PayrollCacheWriteInvalidated();
    }
    final saved = await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(envelope.toJson()),
    );
    if (!saved) throw StateError('Unable to persist payroll cache');
  }

  void _validateRelationships(PayrollEnvelope envelope) {
    final employeeIds = envelope.employees.map((row) => row.id).toSet();
    final advanceIds = envelope.employeeAdvances.map((row) => row.id).toSet();
    final runIds = envelope.payrollRuns.map((row) => row.id).toSet();
    final itemIds = envelope.payrollRunItems.map((row) => row.id).toSet();
    final paymentIds = envelope.payrollPayments.map((row) => row.id).toSet();
    final advancesById = {
      for (final row in envelope.employeeAdvances) row.id: row,
    };
    final itemsById = {for (final row in envelope.payrollRunItems) row.id: row};
    final paymentsById = {
      for (final row in envelope.payrollPayments) row.id: row,
    };
    for (final row in envelope.employeeAdvances) {
      if (!employeeIds.contains(row.employeeId)) {
        throw const FormatException('Advance references unknown employee');
      }
      if (row.reversalOfId != null && !advanceIds.contains(row.reversalOfId)) {
        throw const FormatException(
          'Advance reversal references unknown original',
        );
      }
    }
    for (final row in envelope.payrollRunItems) {
      if (!runIds.contains(row.payrollRunId) ||
          !employeeIds.contains(row.employeeId)) {
        throw const FormatException('Payroll run item relationship mismatch');
      }
    }
    for (final row in envelope.payrollAdvanceAllocations) {
      final item = itemsById[row.payrollRunItemId];
      final advance = advancesById[row.employeeAdvanceId];
      if (!runIds.contains(row.payrollRunId) ||
          item == null ||
          advance == null ||
          !employeeIds.contains(row.employeeId) ||
          item.payrollRunId != row.payrollRunId ||
          item.employeeId != row.employeeId ||
          advance.employeeId != row.employeeId) {
        throw const FormatException('Payroll allocation relationship mismatch');
      }
    }
    for (final row in envelope.payrollPeriodClaims) {
      if (!runIds.contains(row.payrollRunId) ||
          !itemIds.contains(row.payrollRunItemId) ||
          !employeeIds.contains(row.employeeId)) {
        throw const FormatException('Payroll claim relationship mismatch');
      }
    }
    for (final row in envelope.payrollPayments) {
      if (!runIds.contains(row.payrollRunId)) {
        throw const FormatException('Payroll payment references unknown run');
      }
      if (row.reversalOfId != null && !paymentIds.contains(row.reversalOfId)) {
        throw const FormatException(
          'Payment reversal references unknown original',
        );
      }
    }
    for (final row in envelope.payrollPaymentItems) {
      final payment = paymentsById[row.payrollPaymentId];
      final item = itemsById[row.payrollRunItemId];
      if (payment == null ||
          item == null ||
          !employeeIds.contains(row.employeeId) ||
          item.employeeId != row.employeeId ||
          item.payrollRunId != payment.payrollRunId) {
        throw const FormatException(
          'Payroll payment item relationship mismatch',
        );
      }
    }
  }
}
