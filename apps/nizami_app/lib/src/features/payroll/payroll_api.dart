import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../auth/json_transport.dart';
import '../accounting/accounting_api.dart';
import '../accounting/chart_accounts_api.dart';
import 'payroll_models.dart';

class PayrollApi {
  PayrollApi({required this.token, JsonTransport? transport, String? baseUrl})
    : _transport = transport ?? createJsonTransport(),
      _baseUri = Uri.parse(
        '${(baseUrl ?? const String.fromEnvironment('NINESOFT_API_BASE_URL', defaultValue: 'https://ninesoft.qodynex.tech/api/v1')).replaceFirst(RegExp(r'/+$'), '')}/',
      );

  final String token;
  final JsonTransport _transport;
  final Uri _baseUri;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  static String? _cachedDeviceId;

  Future<String> _deviceId() async {
    if ((_cachedDeviceId ?? '').isNotEmpty) return _cachedDeviceId!;
    final preferences = await SharedPreferences.getInstance();
    var value = preferences.getString('ninesoft.accounting.device_uuid.v1');
    if (value == null || value.isEmpty) {
      value = const Uuid().v4();
      if (!await preferences.setString(
        'ninesoft.accounting.device_uuid.v1',
        value,
      )) {
        throw StateError('Unable to persist payroll device identity');
      }
    }
    return _cachedDeviceId = value;
  }

  Future<Map<String, dynamic>> _common({
    required int restoreGeneration,
    String? operationId,
    DateTime? createdAt,
  }) async {
    if (restoreGeneration < 0) {
      throw ArgumentError.value(restoreGeneration, 'restoreGeneration');
    }
    return {
      'device_id': await _deviceId(),
      'local_operation_id': operationId ?? const Uuid().v4(),
      'restore_generation': restoreGeneration,
      'operation_created_at': (createdAt ?? DateTime.now())
          .toUtc()
          .toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> prepareEmployeeCreate({
    required String id,
    required String branchId,
    required String name,
    String? phone,
    required int baseSalaryMinor,
    required String startDate,
    String? notes,
    required int restoreGeneration,
    String? operationId,
    DateTime? createdAt,
  }) async {
    _exactNonNegative(baseSalaryMinor, 'baseSalaryMinor');
    return {
      ...await _common(
        restoreGeneration: restoreGeneration,
        operationId: operationId,
        createdAt: createdAt,
      ),
      'id': _nonEmpty(id, 'id'),
      'branch_id': _nonEmpty(branchId, 'branchId'),
      'name': _nonEmpty(name.trim(), 'name'),
      'phone': phone?.trim(),
      'base_salary_minor': baseSalaryMinor,
      'start_date': _nonEmpty(startDate, 'startDate'),
      'notes': notes?.trim(),
    };
  }

  Future<Map<String, dynamic>> prepareEmployeeUpdate({
    required String id,
    required String branchId,
    required String name,
    String? phone,
    required int baseSalaryMinor,
    required String startDate,
    String? notes,
    required int expectedVersion,
    required int restoreGeneration,
    String? operationId,
    DateTime? createdAt,
  }) async => {
    ...await prepareEmployeeCreate(
      id: id,
      branchId: branchId,
      name: name,
      phone: phone,
      baseSalaryMinor: baseSalaryMinor,
      startDate: startDate,
      notes: notes,
      restoreGeneration: restoreGeneration,
      operationId: operationId,
      createdAt: createdAt,
    ),
    'expected_version': _positive(expectedVersion, 'expectedVersion'),
  };

  Future<Map<String, dynamic>> prepareEmployeeDeactivate({
    required String id,
    required String branchId,
    required int expectedVersion,
    required int restoreGeneration,
    String? operationId,
    DateTime? createdAt,
  }) async => {
    ...await _common(
      restoreGeneration: restoreGeneration,
      operationId: operationId,
      createdAt: createdAt,
    ),
    'id': _nonEmpty(id, 'id'),
    'branch_id': _nonEmpty(branchId, 'branchId'),
    'expected_version': _positive(expectedVersion, 'expectedVersion'),
  };

  Future<Map<String, dynamic>> prepareAdvance({
    required String employeeId,
    required String branchId,
    required int amountMinor,
    required String category,
    required String note,
    required String accountCode,
    required DateTime occurredAt,
    required int restoreGeneration,
    String? operationId,
    DateTime? createdAt,
  }) async {
    _positive(amountMinor, 'amountMinor');
    if (!const {'advance', 'withdrawal', 'debt', 'other'}.contains(category)) {
      throw ArgumentError.value(category, 'category');
    }
    return {
      ...await _common(
        restoreGeneration: restoreGeneration,
        operationId: operationId,
        createdAt: createdAt,
      ),
      'employee_id': _nonEmpty(employeeId, 'employeeId'),
      'branch_id': _nonEmpty(branchId, 'branchId'),
      'amount_minor': amountMinor,
      'category': category,
      'note': _nonEmpty(note.trim(), 'note'),
      'account_code': _nonEmpty(accountCode.trim(), 'accountCode'),
      'occurred_at': occurredAt.toUtc().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> preparePayrollRun({
    required String branchId,
    required String periodMonth,
    required String selectionMode,
    required Iterable<String> employeeIds,
    required int restoreGeneration,
    String? operationId,
    DateTime? createdAt,
    int? previewVersion,
    String? previewSignature,
  }) async {
    if (!const {'all', 'selected'}.contains(selectionMode)) {
      throw ArgumentError.value(selectionMode, 'selectionMode');
    }
    final ids = employeeIds.toSet().toList()..sort();
    if (selectionMode == 'selected' && ids.isEmpty) {
      throw ArgumentError('Selected payroll run needs employees');
    }
    if ((previewVersion == null) != (previewSignature == null) ||
        (previewVersion != null && previewVersion != 1) ||
        (previewSignature != null &&
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(previewSignature))) {
      throw ArgumentError('Invalid payroll preview identity');
    }
    return {
      ...await _common(
        restoreGeneration: restoreGeneration,
        operationId: operationId,
        createdAt: createdAt,
      ),
      'branch_id': _nonEmpty(branchId, 'branchId'),
      'period_month': _nonEmpty(periodMonth, 'periodMonth'),
      'selection_mode': selectionMode,
      'employee_ids': ids,
      'preview_version': ?previewVersion,
      'preview_signature': ?previewSignature,
    };
  }

  Future<PayrollApprovalPreview> fetchPayrollPreview({
    required String branchId,
    required String periodMonth,
    required String selectionMode,
    required Iterable<String> employeeIds,
    required int restoreGeneration,
  }) async {
    final ids = employeeIds.toSet().toList()..sort();
    final response = await _transport.request(
      _resolveApiPath('accounting/payroll-runs/preview'),
      method: 'POST',
      headers: _headers,
      body: jsonEncode({
        'branch_id': _nonEmpty(branchId, 'branchId'),
        'period_month': _nonEmpty(periodMonth, 'periodMonth'),
        'selection_mode': selectionMode,
        'employee_ids': ids,
        'restore_generation': restoreGeneration,
      }),
    );
    return PayrollApprovalPreview.fromJson(
      _decode(response, 'Unable to preview payroll approval.'),
    );
  }

  Future<List<ChartAccount>> fetchPayrollSettlementAccounts(
    String branchId,
  ) async {
    final uri = _baseUri
        .resolve('accounting/payroll-settlement-accounts')
        .replace(
          queryParameters: {'branch_id': _nonEmpty(branchId, 'branchId')},
        );
    final response = await _transport.request(
      uri,
      method: 'GET',
      headers: _headers,
    );
    final decoded = _decode(response, 'Unable to load payroll accounts.');
    final items = decoded['items'];
    if (items is! List) {
      throw const FormatException('Invalid payroll account options');
    }
    return items
        .map(
          (item) => ChartAccount.fromSettlementChoiceJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> preparePayrollPayment({
    required DateTime occurredAt,
    required String accountCode,
    required Iterable<Map<String, Object?>> items,
    required int restoreGeneration,
    String? operationId,
    DateTime? createdAt,
  }) async {
    final canonical = items.map((item) {
      final id = item['payroll_run_item_id'];
      final amount = item['amount_minor'];
      if (id is! String || id.isEmpty || amount is! int) {
        throw const FormatException('Invalid payroll payment item');
      }
      _positive(amount, 'amount_minor');
      return <String, Object?>{
        'payroll_run_item_id': id,
        'amount_minor': amount,
      };
    }).toList();
    canonical.sort(
      (a, b) => (a['payroll_run_item_id'] as String).compareTo(
        b['payroll_run_item_id'] as String,
      ),
    );
    if (canonical.isEmpty) throw ArgumentError('Payment needs items');
    return {
      ...await _common(
        restoreGeneration: restoreGeneration,
        operationId: operationId,
        createdAt: createdAt,
      ),
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'account_code': _nonEmpty(accountCode.trim(), 'accountCode'),
      'items': canonical,
    };
  }

  Future<Map<String, dynamic>> prepareReversal({
    required DateTime occurredAt,
    required String reason,
    required int restoreGeneration,
    String? operationId,
    DateTime? createdAt,
  }) async => {
    ...await _common(
      restoreGeneration: restoreGeneration,
      operationId: operationId,
      createdAt: createdAt,
    ),
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'reason': _nonEmpty(reason.trim(), 'reason'),
  };

  Future<Map<String, dynamic>> prepareAdvanceReversal({
    required DateTime occurredAt,
    required String reason,
    required int restoreGeneration,
    String? operationId,
    DateTime? createdAt,
  }) => prepareReversal(
    occurredAt: occurredAt,
    reason: reason,
    restoreGeneration: restoreGeneration,
    operationId: operationId,
    createdAt: createdAt,
  );

  Future<Map<String, dynamic>> preparePayrollRunReversal({
    required DateTime occurredAt,
    required String reason,
    required int restoreGeneration,
    String? operationId,
    DateTime? createdAt,
  }) => prepareReversal(
    occurredAt: occurredAt,
    reason: reason,
    restoreGeneration: restoreGeneration,
    operationId: operationId,
    createdAt: createdAt,
  );

  Future<Map<String, dynamic>> preparePayrollPaymentReversal({
    required DateTime occurredAt,
    required String reason,
    required int restoreGeneration,
    String? operationId,
    DateTime? createdAt,
  }) => prepareReversal(
    occurredAt: occurredAt,
    reason: reason,
    restoreGeneration: restoreGeneration,
    operationId: operationId,
    createdAt: createdAt,
  );

  Future<Map<String, dynamic>> postEmployeeCreateBody(String body) =>
      postRequestBody(
        method: 'POST',
        path: 'accounting/employees',
        requestBody: body,
      );

  Future<Map<String, dynamic>> postEmployeeUpdateBody(
    String employeeId,
    String body,
  ) => postRequestBody(
    method: 'PUT',
    path: 'accounting/employees/$employeeId',
    requestBody: body,
  );

  Future<Map<String, dynamic>> postEmployeeDeactivateBody(
    String employeeId,
    String body,
  ) => postRequestBody(
    method: 'POST',
    path: 'accounting/employees/$employeeId/deactivate',
    requestBody: body,
  );

  Future<Map<String, dynamic>> postAdvanceBody(String body) => postRequestBody(
    method: 'POST',
    path: 'accounting/employee-advances',
    requestBody: body,
  );

  Future<Map<String, dynamic>> postAdvanceReversalBody(
    String advanceId,
    String body,
  ) => postRequestBody(
    method: 'POST',
    path: 'accounting/employee-advances/$advanceId/reversals',
    requestBody: body,
  );

  Future<Map<String, dynamic>> postPayrollRunBody(String body) =>
      postRequestBody(
        method: 'POST',
        path: 'accounting/payroll-runs',
        requestBody: body,
      );

  Future<Map<String, dynamic>> postPayrollRunReversalBody(
    String runId,
    String body,
  ) => postRequestBody(
    method: 'POST',
    path: 'accounting/payroll-runs/$runId/reversals',
    requestBody: body,
  );

  Future<Map<String, dynamic>> postPayrollPaymentBody(
    String runId,
    String body,
  ) => postRequestBody(
    method: 'POST',
    path: 'accounting/payroll-runs/$runId/payments',
    requestBody: body,
  );

  Future<Map<String, dynamic>> postPayrollPaymentReversalBody(
    String paymentId,
    String body,
  ) => postRequestBody(
    method: 'POST',
    path: 'accounting/payroll-payments/$paymentId/reversals',
    requestBody: body,
  );

  Future<Map<String, dynamic>> postRequestBody({
    required String method,
    required String path,
    required String requestBody,
  }) async {
    if (method != 'POST' && method != 'PUT') {
      throw ArgumentError.value(method, 'method');
    }
    _validatePersistedBody(requestBody);
    final response = await _transport.request(
      _resolveApiPath(path),
      method: method,
      headers: _headers,
      body: requestBody,
    );
    return _decode(response, 'Unable to synchronize payroll operation.');
  }

  Future<Map<String, dynamic>> fetchDetailPath(String detailPath) async {
    final response = await _transport.request(
      _resolveApiPath(detailPath),
      method: 'GET',
      headers: _headers,
    );
    return _decode(response, 'Unable to read canonical payroll detail.');
  }

  Uri _resolveApiPath(String path) {
    final candidate = Uri.tryParse(path);
    if (candidate == null || path.trim().isEmpty || candidate.hasQuery) {
      throw const FormatException('Invalid payroll detail path');
    }
    final resolved = candidate.hasScheme
        ? candidate
        : path.startsWith('/')
        ? _baseUri.replace(path: candidate.path, query: null, fragment: null)
        : _baseUri.resolveUri(candidate);
    final expectedPrefix = _baseUri.path.endsWith('/')
        ? _baseUri.path
        : '${_baseUri.path}/';
    if (resolved.scheme != _baseUri.scheme ||
        resolved.host != _baseUri.host ||
        resolved.port != _baseUri.port ||
        !resolved.path.startsWith(expectedPrefix)) {
      throw const FormatException('Payroll path is outside the API origin');
    }
    return resolved;
  }

  void _validatePersistedBody(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw const AccountingApiError('Invalid persisted payroll request.');
    }
    if (decoded is! Map ||
        (decoded['device_id']?.toString() ?? '').isEmpty ||
        (decoded['local_operation_id']?.toString() ?? '').isEmpty ||
        decoded['restore_generation'] is! int ||
        DateTime.tryParse(decoded['operation_created_at']?.toString() ?? '') ==
            null) {
      throw const AccountingApiError('Invalid persisted payroll request.');
    }
  }

  Map<String, dynamic> _decode(JsonResponse response, String fallback) {
    dynamic decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } catch (_) {
      throw const AccountingApiError('Invalid payroll server response.');
    }
    final value = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AccountingApiError(
        value['message']?.toString() ?? fallback,
        statusCode: response.statusCode,
      );
    }
    return value;
  }

  static String _nonEmpty(String value, String name) {
    if (value.isEmpty) throw ArgumentError.value(value, name);
    return value;
  }

  static int _exactNonNegative(int value, String name) {
    if (value < 0 || value > payrollMaxExactInteger) {
      throw ArgumentError.value(value, name);
    }
    return value;
  }

  static int _positive(int value, String name) {
    if (_exactNonNegative(value, name) == 0) {
      throw ArgumentError.value(value, name);
    }
    return value;
  }
}
