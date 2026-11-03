import 'dart:collection';

const int payrollMaxExactInteger = 9007199254740991;

Map<String, dynamic> _immutableJson(Map<String, dynamic> source) {
  dynamic freeze(Object? value) {
    if (value == null || value is String || value is bool) return value;
    if (value is int) {
      if (value.abs() > payrollMaxExactInteger) {
        throw const FormatException(
          'Payroll integer is outside exact JSON range',
        );
      }
      return value;
    }
    if (value is num) {
      throw const FormatException('Payroll JSON numbers must be integers');
    }
    if (value is List) {
      return List<dynamic>.unmodifiable(value.map(freeze));
    }
    if (value is Map) {
      return Map<String, dynamic>.unmodifiable(
        value.map((key, item) => MapEntry(key.toString(), freeze(item))),
      );
    }
    throw const FormatException('Unsupported payroll JSON value');
  }

  return Map<String, dynamic>.from(freeze(source) as Map);
}

Map<String, dynamic> _copyJson(Map<String, dynamic> source) {
  dynamic copy(Object? value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), copy(item)));
    }
    if (value is List) return value.map(copy).toList(growable: false);
    return value;
  }

  return Map<String, dynamic>.from(copy(source) as Map);
}

String _requiredString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing payroll field: $field');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String field, {int minimum = 0}) {
  final value = json[field];
  if (value is! int || value < minimum || value > payrollMaxExactInteger) {
    throw FormatException('Invalid payroll integer: $field');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid payroll field: $field');
  return value;
}

void _validateScope(
  Map<String, dynamic> json, {
  String? tenantId,
  String? branchId,
}) {
  final rowTenant = json['tenant_id'];
  if (rowTenant != null &&
      (rowTenant is! String ||
          rowTenant.isEmpty ||
          (tenantId != null && rowTenant != tenantId))) {
    throw const FormatException('Payroll tenant identity mismatch');
  }
  final rowBranch = json['branch_id'];
  if (branchId != null && rowBranch != branchId) {
    throw const FormatException('Payroll branch identity mismatch');
  }
}

abstract class PayrollJsonModel {
  const PayrollJsonModel();
  Map<String, dynamic> get _json;
  Map<String, dynamic> toJson() => _copyJson(_json);
}

class Employee extends PayrollJsonModel {
  Employee._(this._json);

  factory Employee.fromJson(
    Map<String, dynamic> json, {
    String? tenantId,
    String? branchId,
  }) {
    final value = _immutableJson(json);
    _validateScope(value, tenantId: tenantId, branchId: branchId);
    _requiredString(value, 'id');
    _requiredString(value, 'branch_id');
    _requiredString(value, 'name');
    _optionalString(value, 'phone');
    _requiredInt(value, 'base_salary_minor');
    _requiredString(value, 'start_date');
    _optionalString(value, 'notes');
    if (value['active'] is! bool) {
      throw const FormatException('Invalid employee active flag');
    }
    _requiredInt(value, 'version', minimum: 1);
    return Employee._(value);
  }

  @override
  final Map<String, dynamic> _json;
  String get id => _json['id'] as String;
  String? get tenantId => _json['tenant_id'] as String?;
  String get branchId => _json['branch_id'] as String;
  String get name => _json['name'] as String;
  String? get phone => _json['phone'] as String?;
  int get baseSalaryMinor => _json['base_salary_minor'] as int;
  bool get active => _json['active'] as bool;
  int get version => _json['version'] as int;
}

class PayrollApprovalPreview extends PayrollJsonModel {
  PayrollApprovalPreview._(this._json, this.items);

  factory PayrollApprovalPreview.fromJson(Map<String, dynamic> json) {
    final value = _immutableJson(json);
    if (_requiredInt(value, 'preview_version', minimum: 1) != 1) {
      throw const FormatException('Unsupported payroll preview version');
    }
    final signature = _requiredString(value, 'preview_signature');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(signature)) {
      throw const FormatException('Invalid payroll preview signature');
    }
    _requiredInt(value, 'restore_generation');
    _requiredString(value, 'branch_id');
    _requiredString(value, 'period_month');
    final mode = _requiredString(value, 'selection_mode');
    if (!const {'all', 'selected'}.contains(mode)) {
      throw const FormatException('Invalid payroll preview selection mode');
    }
    _requiredString(value, 'confirmed_at');
    final rawItems = value['items'];
    final totals = value['totals'];
    if (rawItems is! List || rawItems.isEmpty || totals is! Map) {
      throw const FormatException('Invalid payroll preview body');
    }
    final items = rawItems
        .map((row) {
          if (row is! Map) {
            throw const FormatException('Invalid payroll preview item');
          }
          return PayrollApprovalPreviewItem.fromJson(
            Map<String, dynamic>.from(row),
          );
        })
        .toList(growable: false);
    final totalMap = Map<String, dynamic>.from(totals);
    final gross = _requiredInt(totalMap, 'gross_minor');
    final applied = _requiredInt(totalMap, 'applied_advance_minor');
    final net = _requiredInt(totalMap, 'net_minor');
    if (gross != applied + net ||
        items.fold<int>(0, (sum, row) => sum + row.grossMinor) != gross ||
        items.fold<int>(0, (sum, row) => sum + row.appliedMinor) != applied ||
        items.fold<int>(0, (sum, row) => sum + row.netMinor) != net) {
      throw const FormatException('Payroll preview totals do not balance');
    }
    return PayrollApprovalPreview._(value, List.unmodifiable(items));
  }

  @override
  final Map<String, dynamic> _json;
  final List<PayrollApprovalPreviewItem> items;
  int get version => _json['preview_version'] as int;
  String get signature => _json['preview_signature'] as String;
  int get restoreGeneration => _json['restore_generation'] as int;
  String get branchId => _json['branch_id'] as String;
  String get periodMonth => _json['period_month'] as String;
  String get selectionMode => _json['selection_mode'] as String;
  int get grossMinor => (_json['totals'] as Map)['gross_minor'] as int;
  int get appliedMinor =>
      (_json['totals'] as Map)['applied_advance_minor'] as int;
  int get netMinor => (_json['totals'] as Map)['net_minor'] as int;
}

class PayrollApprovalPreviewItem extends PayrollJsonModel {
  PayrollApprovalPreviewItem._(this._json);

  factory PayrollApprovalPreviewItem.fromJson(Map<String, dynamic> json) {
    final value = _immutableJson(json);
    _requiredString(value, 'employee_id');
    _requiredString(value, 'employee_name');
    final gross = _requiredInt(value, 'gross_minor');
    final applied = _requiredInt(value, 'applied_advance_minor');
    final net = _requiredInt(value, 'net_minor');
    if (gross != applied + net) {
      throw const FormatException('Payroll preview item does not balance');
    }
    return PayrollApprovalPreviewItem._(value);
  }

  @override
  final Map<String, dynamic> _json;
  String get employeeId => _json['employee_id'] as String;
  String get employeeName => _json['employee_name'] as String;
  int get grossMinor => _json['gross_minor'] as int;
  int get appliedMinor => _json['applied_advance_minor'] as int;
  int get netMinor => _json['net_minor'] as int;
}

class EmployeeAdvance extends PayrollJsonModel {
  EmployeeAdvance._(this._json);

  factory EmployeeAdvance.fromJson(
    Map<String, dynamic> json, {
    String? tenantId,
    String? branchId,
  }) {
    final value = _immutableJson(json);
    _validateScope(value, tenantId: tenantId, branchId: branchId);
    for (final field in const [
      'id',
      'branch_id',
      'employee_id',
      'document_kind',
      'occurred_at',
      'category',
      'note',
      'account_code',
      'status',
      'device_id',
      'local_operation_id',
      'operation_created_at',
    ]) {
      _requiredString(value, field);
    }
    _optionalString(value, 'reversal_of_id');
    _optionalString(value, 'reason');
    _requiredInt(value, 'amount_minor', minimum: 1);
    _requiredInt(value, 'restore_generation');
    return EmployeeAdvance._(value);
  }

  @override
  final Map<String, dynamic> _json;
  String get id => _json['id'] as String;
  String? get tenantId => _json['tenant_id'] as String?;
  String get branchId => _json['branch_id'] as String;
  String get employeeId => _json['employee_id'] as String;
  String get documentKind => _json['document_kind'] as String;
  String? get reversalOfId => _json['reversal_of_id'] as String?;
  int get amountMinor => _json['amount_minor'] as int;
  String get status => _json['status'] as String;
  String get deviceId => _json['device_id'] as String;
  String get localOperationId => _json['local_operation_id'] as String;
  int get restoreGeneration => _json['restore_generation'] as int;
}

class PayrollRun extends PayrollJsonModel {
  PayrollRun._(this._json);

  factory PayrollRun.fromJson(
    Map<String, dynamic> json, {
    String? tenantId,
    String? branchId,
  }) {
    final value = _immutableJson(json);
    _validateScope(value, tenantId: tenantId, branchId: branchId);
    for (final field in const [
      'id',
      'branch_id',
      'document_kind',
      'period_month',
      'selection_mode',
      'occurred_at',
      'status',
      'device_id',
      'local_operation_id',
      'operation_created_at',
    ]) {
      _requiredString(value, field);
    }
    _optionalString(value, 'reversal_of_id');
    _optionalString(value, 'reason');
    _requiredInt(value, 'total_gross_minor');
    _requiredInt(value, 'total_applied_minor');
    _requiredInt(value, 'total_net_minor');
    _requiredInt(value, 'restore_generation');
    if ((value['total_gross_minor'] as int) !=
        (value['total_applied_minor'] as int) +
            (value['total_net_minor'] as int)) {
      throw const FormatException('Payroll run totals do not balance');
    }
    return PayrollRun._(value);
  }

  @override
  final Map<String, dynamic> _json;
  String get id => _json['id'] as String;
  String? get tenantId => _json['tenant_id'] as String?;
  String get branchId => _json['branch_id'] as String;
  String get documentKind => _json['document_kind'] as String;
  String? get reversalOfId => _json['reversal_of_id'] as String?;
  String get status => _json['status'] as String;
  String get deviceId => _json['device_id'] as String;
  String get localOperationId => _json['local_operation_id'] as String;
  int get restoreGeneration => _json['restore_generation'] as int;
}

class PayrollRunItem extends PayrollJsonModel {
  PayrollRunItem._(this._json);

  factory PayrollRunItem.fromJson(
    Map<String, dynamic> json, {
    String? tenantId,
    String? branchId,
  }) {
    final value = _immutableJson(json);
    _validateScope(value, tenantId: tenantId, branchId: branchId);
    for (final field in const [
      'id',
      'branch_id',
      'payroll_run_id',
      'employee_id',
    ]) {
      _requiredString(value, field);
    }
    _requiredInt(value, 'employee_base_salary_minor_snapshot');
    _requiredInt(value, 'gross_minor');
    _requiredInt(value, 'applied_advance_minor');
    _requiredInt(value, 'net_minor');
    final remaining = value['remaining_minor'];
    if (remaining != null && remaining is! int) {
      throw const FormatException('Invalid remaining payroll amount');
    }
    return PayrollRunItem._(value);
  }

  @override
  final Map<String, dynamic> _json;
  String get id => _json['id'] as String;
  String get branchId => _json['branch_id'] as String;
  String get payrollRunId => _json['payroll_run_id'] as String;
  String get employeeId => _json['employee_id'] as String;
  int get netMinor => _json['net_minor'] as int;
  int? get remainingMinor => _json['remaining_minor'] as int?;
}

class PayrollAdvanceAllocation extends PayrollJsonModel {
  PayrollAdvanceAllocation._(this._json);

  factory PayrollAdvanceAllocation.fromJson(
    Map<String, dynamic> json, {
    String? tenantId,
    String? branchId,
  }) {
    final value = _immutableJson(json);
    _validateScope(value, tenantId: tenantId, branchId: branchId);
    for (final field in const [
      'id',
      'branch_id',
      'payroll_run_id',
      'payroll_run_item_id',
      'employee_advance_id',
      'employee_id',
    ]) {
      _requiredString(value, field);
    }
    _requiredInt(value, 'amount_minor', minimum: 1);
    return PayrollAdvanceAllocation._(value);
  }

  @override
  final Map<String, dynamic> _json;
  String get id => _json['id'] as String;
  String get branchId => _json['branch_id'] as String;
  String get payrollRunId => _json['payroll_run_id'] as String;
  String get payrollRunItemId => _json['payroll_run_item_id'] as String;
  String get employeeAdvanceId => _json['employee_advance_id'] as String;
  String get employeeId => _json['employee_id'] as String;
}

class PayrollPeriodClaim extends PayrollJsonModel {
  PayrollPeriodClaim._(this._json);

  factory PayrollPeriodClaim.fromJson(
    Map<String, dynamic> json, {
    String? tenantId,
    String? branchId,
  }) {
    final value = _immutableJson(json);
    _validateScope(value, tenantId: tenantId, branchId: branchId);
    for (final field in const [
      'id',
      'branch_id',
      'employee_id',
      'period_month',
      'payroll_run_id',
      'payroll_run_item_id',
    ]) {
      _requiredString(value, field);
    }
    return PayrollPeriodClaim._(value);
  }

  @override
  final Map<String, dynamic> _json;
  String get id => _json['id'] as String;
  String get branchId => _json['branch_id'] as String;
  String get payrollRunId => _json['payroll_run_id'] as String;
  String get payrollRunItemId => _json['payroll_run_item_id'] as String;
  String get employeeId => _json['employee_id'] as String;
}

class PayrollPayment extends PayrollJsonModel {
  PayrollPayment._(this._json);

  factory PayrollPayment.fromJson(
    Map<String, dynamic> json, {
    String? tenantId,
    String? branchId,
  }) {
    final value = _immutableJson(json);
    _validateScope(value, tenantId: tenantId, branchId: branchId);
    for (final field in const [
      'id',
      'branch_id',
      'payroll_run_id',
      'document_kind',
      'occurred_at',
      'account_code',
      'status',
      'device_id',
      'local_operation_id',
      'operation_created_at',
    ]) {
      _requiredString(value, field);
    }
    _optionalString(value, 'reversal_of_id');
    _optionalString(value, 'reason');
    _requiredInt(value, 'total_minor', minimum: 1);
    _requiredInt(value, 'restore_generation');
    return PayrollPayment._(value);
  }

  @override
  final Map<String, dynamic> _json;
  String get id => _json['id'] as String;
  String? get tenantId => _json['tenant_id'] as String?;
  String get branchId => _json['branch_id'] as String;
  String get payrollRunId => _json['payroll_run_id'] as String;
  String get documentKind => _json['document_kind'] as String;
  String? get reversalOfId => _json['reversal_of_id'] as String?;
  String get status => _json['status'] as String;
  String get deviceId => _json['device_id'] as String;
  String get localOperationId => _json['local_operation_id'] as String;
  int get restoreGeneration => _json['restore_generation'] as int;
}

class PayrollPaymentItem extends PayrollJsonModel {
  PayrollPaymentItem._(this._json);

  factory PayrollPaymentItem.fromJson(
    Map<String, dynamic> json, {
    String? tenantId,
    String? branchId,
  }) {
    final value = _immutableJson(json);
    _validateScope(value, tenantId: tenantId, branchId: branchId);
    for (final field in const [
      'id',
      'branch_id',
      'payroll_payment_id',
      'payroll_run_item_id',
      'employee_id',
    ]) {
      _requiredString(value, field);
    }
    _requiredInt(value, 'amount_minor', minimum: 1);
    return PayrollPaymentItem._(value);
  }

  @override
  final Map<String, dynamic> _json;
  String get id => _json['id'] as String;
  String get branchId => _json['branch_id'] as String;
  String get payrollPaymentId => _json['payroll_payment_id'] as String;
  String get payrollRunItemId => _json['payroll_run_item_id'] as String;
  String get employeeId => _json['employee_id'] as String;
}

class PayrollEnvelope {
  const PayrollEnvelope({
    required this.employees,
    required this.employeeAdvances,
    required this.payrollRuns,
    required this.payrollRunItems,
    required this.payrollAdvanceAllocations,
    required this.payrollPeriodClaims,
    required this.payrollPayments,
    required this.payrollPaymentItems,
  });

  factory PayrollEnvelope.empty() => const PayrollEnvelope(
    employees: [],
    employeeAdvances: [],
    payrollRuns: [],
    payrollRunItems: [],
    payrollAdvanceAllocations: [],
    payrollPeriodClaims: [],
    payrollPayments: [],
    payrollPaymentItems: [],
  );

  final List<Employee> employees;
  final List<EmployeeAdvance> employeeAdvances;
  final List<PayrollRun> payrollRuns;
  final List<PayrollRunItem> payrollRunItems;
  final List<PayrollAdvanceAllocation> payrollAdvanceAllocations;
  final List<PayrollPeriodClaim> payrollPeriodClaims;
  final List<PayrollPayment> payrollPayments;
  final List<PayrollPaymentItem> payrollPaymentItems;

  Map<String, dynamic> toJson() => {
    'employees': employees.map((value) => value.toJson()).toList(),
    'employee_advances': employeeAdvances
        .map((value) => value.toJson())
        .toList(),
    'payroll_runs': payrollRuns.map((value) => value.toJson()).toList(),
    'payroll_run_items': payrollRunItems
        .map((value) => value.toJson())
        .toList(),
    'payroll_advance_allocations': payrollAdvanceAllocations
        .map((value) => value.toJson())
        .toList(),
    'payroll_period_claims': payrollPeriodClaims
        .map((value) => value.toJson())
        .toList(),
    'payroll_payments': payrollPayments.map((value) => value.toJson()).toList(),
    'payroll_payment_items': payrollPaymentItems
        .map((value) => value.toJson())
        .toList(),
  };

  PayrollEnvelope immutable() => PayrollEnvelope(
    employees: UnmodifiableListView(employees),
    employeeAdvances: UnmodifiableListView(employeeAdvances),
    payrollRuns: UnmodifiableListView(payrollRuns),
    payrollRunItems: UnmodifiableListView(payrollRunItems),
    payrollAdvanceAllocations: UnmodifiableListView(payrollAdvanceAllocations),
    payrollPeriodClaims: UnmodifiableListView(payrollPeriodClaims),
    payrollPayments: UnmodifiableListView(payrollPayments),
    payrollPaymentItems: UnmodifiableListView(payrollPaymentItems),
  );
}
