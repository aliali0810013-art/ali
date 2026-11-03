import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/auth_api.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/payroll/payroll_api.dart';
import 'package:nizami/src/features/payroll/payroll_cache.dart';
import 'package:nizami/src/features/sync/realtime_sync_coordinator.dart';
import 'package:nizami/src/features/sync/restore_snapshot_store.dart';
import 'package:nizami/src/features/sync/payroll_outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

const tenantA = '11111111-1111-4111-8111-111111111111';
const tenantB = '11111111-1111-4111-8111-111111111112';
const branchA = '22222222-2222-4222-8222-222222222222';
const branchB = '22222222-2222-4222-8222-222222222223';
const employee = '44444444-4444-4444-8444-444444444444';
const advance = '55555555-5555-4555-8555-555555555555';
const run = '66666666-6666-4666-8666-666666666666';
const runItem = '77777777-7777-4777-8777-777777777777';
const payment = '88888888-8888-4888-8888-888888888888';
const runReversal = '66666666-6666-4666-8666-666666666667';
const paymentReversal = '88888888-8888-4888-8888-888888888889';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'complete snapshot atomically replaces all eight branch arrays',
    () async {
      final cache = PayrollCache(tenantA, branchA);
      await cache.replaceSnapshot(_snapshot());
      var value = await cache.read();
      expect(value.employees, hasLength(1));
      expect(value.employeeAdvances, hasLength(1));
      expect(value.payrollRuns, hasLength(1));
      expect(value.payrollRunItems, hasLength(1));
      expect(value.payrollAdvanceAllocations, hasLength(1));
      expect(value.payrollPeriodClaims, hasLength(1));
      expect(value.payrollPayments, hasLength(1));
      expect(value.payrollPaymentItems, hasLength(1));

      await cache.replaceSnapshot({
        'employees': <Object>[],
        'employee_advances': <Object>[],
        'payroll_runs': <Object>[],
        'payroll_run_items': <Object>[],
        'payroll_advance_allocations': <Object>[],
        'payroll_period_claims': <Object>[],
        'payroll_payments': <Object>[],
        'payroll_payment_items': <Object>[],
      });
      value = await cache.read();
      expect(
        value.toJson().values.every((rows) => (rows as List).isEmpty),
        isTrue,
      );
    },
  );

  test('tenant and branch envelopes never mix', () async {
    await PayrollCache(tenantA, branchA).replaceSnapshot(_snapshot());
    await PayrollCache(tenantA, branchB).replaceSnapshot(_snapshot());
    await expectLater(
      PayrollCache(tenantB, branchA).replaceSnapshot(_snapshot()),
      throwsFormatException,
    );
    expect(
      (await PayrollCache(tenantA, branchA).read()).employees,
      hasLength(1),
    );
    expect((await PayrollCache(tenantA, branchB).read()).employees, isEmpty);
    expect((await PayrollCache(tenantB, branchA).read()).employees, isEmpty);
  });

  test(
    'restore journal applies payroll envelope before journal removal',
    () async {
      final session = _session();
      final store = RestoreSnapshotStore.forSession(
        session,
        restoreGeneration: 3,
      );
      final snapshot = {
        ..._snapshot(),
        'restore_generation': 3,
        'snapshot_cursor': 40,
        'branch_ids': [branchA],
        'products': <Object>[],
        'contacts': <Object>[],
        'invoices': <Object>[],
        'purchase_invoices': <Object>[],
        'business_documents': <Object>[],
        'product_sale_options': <Object>[],
      };
      await store.stage(snapshot);
      expect(await store.pending(), isNotNull);
      expect((await PayrollCache(tenantA, branchA).read()).employees, isEmpty);
      expect(await store.resume(), isNotNull);
      expect(
        (await PayrollCache(tenantA, branchA).read()).employees,
        hasLength(1),
      );
      expect(await store.pending(), isNull);
    },
  );

  test(
    'first-login payroll bootstrap applies every branch before cursor commit',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final session = _session(branchIds: const [branchA, branchB]);
      final transport = _SnapshotTransport([
        _bootstrapSnapshot(
          tenantId: tenantA,
          branchIds: const [branchA, branchB],
          cursor: 73,
          restoreGeneration: 4,
        ),
      ]);

      final result = await bootstrapPayrollSnapshot(
        transport: transport,
        baseUri: Uri.parse('https://example.test/api/v1/'),
        prefs: prefs,
        session: session,
        scope: 'scope.first-login',
        restoreGeneration: 0,
        currentCursor: 0,
        isResponseValid: () => true,
      );

      expect(result.cursor, 73);
      expect(result.restoreGeneration, 4);
      expect(result.restoreEpoch, DateTime.parse('2026-10-31T00:00:00.000Z'));
      expect(prefs.getInt('scope.first-login.cursor'), 73);
      expect(prefs.getInt('scope.first-login.restore_generation'), 4);
      expect(prefs.getBool('scope.first-login.payroll_bootstrap'), isTrue);
      expect(
        (await PayrollCache(tenantA, branchA).read()).employees.single.id,
        '$employee-a',
      );
      expect(
        (await PayrollCache(tenantA, branchB).read()).employees.single.id,
        '$employee-b',
      );
      expect(transport.paths, [
        '/api/v1/sync/changes',
        '/api/v1/sync/snapshot',
      ]);
    },
  );

  test(
    'permission expansion bootstraps its new scope without tenant leakage',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final hidden = _session(roleCode: 'accountant', permissions: const []);
      final expanded = _session(roleCode: 'accountant');
      final foreign = _session(tenantId: tenantB, branchIds: const [branchB]);
      final transport = _SnapshotTransport([
        _bootstrapSnapshot(
          tenantId: tenantA,
          branchIds: const [branchA],
          cursor: 80,
        ),
        _bootstrapSnapshot(
          tenantId: tenantB,
          branchIds: const [branchB],
          cursor: 91,
        ),
      ]);

      expect(
        (await bootstrapPayrollSnapshot(
          transport: transport,
          baseUri: Uri.parse('https://example.test/api/v1/'),
          prefs: prefs,
          session: hidden,
          scope: 'scope.hidden',
          restoreGeneration: 0,
          currentCursor: 12,
          isResponseValid: () => true,
        )).cursor,
        12,
      );
      expect(transport.paths, isEmpty);

      expect(
        (await bootstrapPayrollSnapshot(
          transport: transport,
          baseUri: Uri.parse('https://example.test/api/v1/'),
          prefs: prefs,
          session: expanded,
          scope: 'scope.expanded',
          restoreGeneration: 0,
          currentCursor: 0,
          isResponseValid: () => true,
        )).cursor,
        80,
      );
      expect(
        (await bootstrapPayrollSnapshot(
          transport: transport,
          baseUri: Uri.parse('https://example.test/api/v1/'),
          prefs: prefs,
          session: foreign,
          scope: 'scope.foreign',
          restoreGeneration: 0,
          currentCursor: 0,
          isResponseValid: () => true,
        )).cursor,
        91,
      );

      expect(
        (await PayrollCache(tenantA, branchA).read()).employees.single.id,
        '$employee-a',
      );
      expect(
        (await PayrollCache(tenantB, branchB).read()).employees.single.id,
        '$employee-b',
      );
      expect((await PayrollCache(tenantB, branchA).read()).employees, isEmpty);
      expect(transport.paths, [
        '/api/v1/sync/changes',
        '/api/v1/sync/snapshot',
        '/api/v1/sync/changes',
        '/api/v1/sync/snapshot',
      ]);
    },
  );

  test('detail_path rooted at /api/v1 is fetched once and merged', () async {
    final transport = _ReadTransport(_employeeDetail());
    final changed = await applyPayrollChange(
      api: PayrollApi(
        token: 'token',
        transport: transport,
        baseUrl: 'https://example.test/api/v1',
      ),
      tenantId: tenantA,
      allowedBranchIds: const [branchA],
      aggregateType: 'employee',
      aggregateId: employee,
      eventBranchId: branchA,
      payload: {'detail_path': '/api/v1/accounting/employees/$employee'},
      isResponseValid: () => true,
    );
    expect(changed, 'employee');
    expect(
      transport.uri.toString(),
      'https://example.test/api/v1/accounting/employees/$employee',
    );
    expect(
      (await PayrollCache(tenantA, branchA).read()).employees.single.id,
      employee,
    );
  });

  test('reversal detail converges reversal and original status', () async {
    await PayrollCache(tenantA, branchA).replaceSnapshot(_snapshot());
    final reversalId = '55555555-5555-4555-8555-555555555556';
    final detail = _advanceDetail();
    detail['advance'] = {
      ...(detail['advance'] as Map<String, dynamic>),
      'id': reversalId,
      'document_kind': 'employee_advance_reversal',
      'reversal_of_id': advance,
      'status': 'posted',
      'local_operation_id': 'reversal-op',
    };
    detail['original'] = {
      ...(detail['advance'] as Map<String, dynamic>),
      'id': advance,
      'document_kind': 'employee_advance',
      'reversal_of_id': null,
      'status': 'reversed',
      'local_operation_id': 'original-op',
    };
    detail['journal'] = {
      ...(detail['journal'] as Map<String, dynamic>),
      'reference_type': 'employee_advance_reversal',
      'reference_id': reversalId,
    };
    await PayrollCache(tenantA, branchA).mergeRemoteDetail(
      aggregateType: 'employee_advance',
      aggregateId: reversalId,
      detail: detail,
    );
    final rows = (await PayrollCache(tenantA, branchA).read()).employeeAdvances;
    expect(rows.firstWhere((row) => row.id == advance).status, 'reversed');
    expect(
      rows.firstWhere((row) => row.id == reversalId).reversalOfId,
      advance,
    );
  });

  test(
    'run and payment detail paths converge each reversal and original',
    () async {
      await PayrollCache(tenantA, branchA).replaceSnapshot(_snapshot());
      final values = _snapshot();
      final originalPayment = Map<String, dynamic>.from(
        (values['payroll_payments'] as List).single as Map,
      );
      final paymentDetail = {
        'payment': {
          ...originalPayment,
          'id': paymentReversal,
          'document_kind': 'payroll_payment_reversal',
          'reversal_of_id': payment,
          'status': 'posted',
          'reason': 'Correction',
          'local_operation_id': 'payment-reversal-op',
        },
        'original': {...originalPayment, 'status': 'reversed'},
        'items': <Object>[],
        'remaining': [
          {'payroll_run_item_id': runItem, 'remaining_minor': 75000},
        ],
        'journal': {
          'id': 'payment-reversal-journal',
          'branch_id': branchA,
          'reference_type': 'payroll_payment_reversal',
          'reference_id': paymentReversal,
          'reversal_of_id': 'payment-journal',
          'posted_at': '2026-12-01T00:00:00.000Z',
          'lines': <Object>[],
        },
      };
      await applyPayrollChange(
        api: PayrollApi(
          token: 'token',
          transport: _ReadTransport(paymentDetail),
          baseUrl: 'https://example.test/api/v1',
        ),
        tenantId: tenantA,
        allowedBranchIds: const [branchA],
        aggregateType: 'payroll_payment',
        aggregateId: paymentReversal,
        eventBranchId: branchA,
        payload: {
          'detail_path': '/api/v1/accounting/payroll-payments/$paymentReversal',
        },
        isResponseValid: () => true,
      );

      final originalRun = Map<String, dynamic>.from(
        (values['payroll_runs'] as List).single as Map,
      );
      final runDetail = {
        'run': {
          ...originalRun,
          'id': runReversal,
          'document_kind': 'payroll_run_reversal',
          'reversal_of_id': run,
          'status': 'posted',
          'reason': 'Correction',
          'local_operation_id': 'run-reversal-op',
        },
        'original': {...originalRun, 'status': 'reversed'},
        'items': <Object>[],
        'allocations': <Object>[],
        'totals': {
          'gross_minor': 100000,
          'applied_advance_minor': 25000,
          'net_minor': 75000,
        },
        'journal': {
          'id': 'run-reversal-journal',
          'branch_id': branchA,
          'reference_type': 'payroll_run_reversal',
          'reference_id': runReversal,
          'reversal_of_id': 'run-journal',
          'posted_at': '2026-12-01T00:00:00.000Z',
          'lines': <Object>[],
        },
      };
      await applyPayrollChange(
        api: PayrollApi(
          token: 'token',
          transport: _ReadTransport(runDetail),
          baseUrl: 'https://example.test/api/v1',
        ),
        tenantId: tenantA,
        allowedBranchIds: const [branchA],
        aggregateType: 'payroll_run',
        aggregateId: runReversal,
        eventBranchId: branchA,
        payload: {
          'detail_path': '/api/v1/accounting/payroll-runs/$runReversal',
        },
        isResponseValid: () => true,
      );

      final envelope = await PayrollCache(tenantA, branchA).read();
      expect(
        envelope.payrollPayments.firstWhere((row) => row.id == payment).status,
        'reversed',
      );
      expect(
        envelope.payrollPayments
            .firstWhere((row) => row.id == paymentReversal)
            .reversalOfId,
        payment,
      );
      expect(
        envelope.payrollRuns.firstWhere((row) => row.id == run).status,
        'reversed',
      );
      expect(
        envelope.payrollRuns
            .firstWhere((row) => row.id == runReversal)
            .reversalOfId,
        run,
      );
    },
  );

  test(
    'wrong tenant, branch, aggregate, or stale response changes nothing',
    () async {
      for (final detail in [
        {
          'employee': {
            ..._employeeDetail()['employee'] as Map,
            'tenant_id': tenantB,
          },
        },
        {
          'employee': {
            ..._employeeDetail()['employee'] as Map,
            'branch_id': branchB,
          },
        },
        {
          'employee': {..._employeeDetail()['employee'] as Map, 'id': 'wrong'},
        },
      ]) {
        await expectLater(
          applyPayrollChange(
            api: PayrollApi(
              token: 'token',
              transport: _ReadTransport(Map<String, dynamic>.from(detail)),
            ),
            tenantId: tenantA,
            allowedBranchIds: const [branchA],
            aggregateType: 'employee',
            aggregateId: employee,
            eventBranchId: branchA,
            payload: {'detail_path': '/api/v1/accounting/employees/$employee'},
            isResponseValid: () => true,
          ),
          throwsFormatException,
        );
      }
      await expectLater(
        applyPayrollChange(
          api: PayrollApi(
            token: 'token',
            transport: _ReadTransport(_employeeDetail()),
          ),
          tenantId: tenantA,
          allowedBranchIds: const [branchA],
          aggregateType: 'employee',
          aggregateId: employee,
          eventBranchId: branchA,
          payload: {'detail_path': '/api/v1/accounting/employees/$employee'},
          isResponseValid: () => false,
        ),
        throwsStateError,
      );
      expect((await PayrollCache(tenantA, branchA).read()).employees, isEmpty);
    },
  );

  test('payroll permission gate is precise per operation kind', () {
    expect(
      canSendPayrollOperation(
        kind: PayrollOperationKind.employeeCreate,
        roleCode: 'accountant',
        permissions: const ['payroll.manage'],
      ),
      isTrue,
    );
    expect(
      canSendPayrollOperation(
        kind: PayrollOperationKind.payrollPaymentPost,
        roleCode: 'accountant',
        permissions: const ['payroll.approve'],
      ),
      isFalse,
    );
    expect(
      canSendPayrollOperation(
        kind: PayrollOperationKind.payrollPaymentPost,
        roleCode: 'owner',
        permissions: const [],
      ),
      isTrue,
    );
  });

  test(
    'coordinator keeps offline cache and retries a failed initial payroll bootstrap',
    () async {
      final transport = _RetryingCoordinatorTransport();
      final coordinator = RealtimeSyncCoordinator.forTesting(
        transport: transport,
        baseUri: Uri.parse('https://example.test/api/v1/'),
        retryBaseDelay: const Duration(milliseconds: 1),
        idlePollInterval: const Duration(hours: 1),
      );
      final events = <Set<String>>[];
      final subscription = coordinator.changes.listen(events.add);

      await coordinator.start(
        _session(roleCode: 'accountant', permissions: const ['payroll.read']),
      );
      final prefs = await SharedPreferences.getInstance();
      for (var attempt = 0; attempt < 100; attempt++) {
        if (prefs.getKeys().any(
          (key) =>
              key.endsWith('.payroll_bootstrap') && prefs.getBool(key) == true,
        )) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(events.any((types) => types.contains('sync_failure')), isTrue);
      expect(transport.failedRequests, 1);
      expect(
        prefs.getKeys().any(
          (key) =>
              key.endsWith('.payroll_bootstrap') && prefs.getBool(key) == true,
        ),
        isTrue,
      );
      expect(
        (await PayrollCache(tenantA, branchA).read()).employees,
        hasLength(1),
      );

      coordinator.stop();
      await subscription.cancel();
    },
  );
}

AuthSession _session({
  String tenantId = tenantA,
  String roleCode = 'owner',
  List<String> branchIds = const [branchA],
  List<String> permissions = const ['payroll.read'],
}) => AuthSession(
  token: 'token',
  userId: 'user',
  username: 'user',
  displayName: 'User',
  roleCode: roleCode,
  tenantId: tenantId,
  tenantName: 'Tenant',
  tenantSlug: 'tenant',
  branchIds: branchIds,
  mustChangePassword: false,
  permissions: permissions,
);

Map<String, dynamic> _bootstrapSnapshot({
  required String tenantId,
  required List<String> branchIds,
  required int cursor,
  int restoreGeneration = 0,
}) => {
  'snapshot_version': 1,
  'restore_generation': restoreGeneration,
  'snapshot_cursor': cursor,
  'branch_ids': branchIds,
  'products': <Object>[],
  'contacts': <Object>[],
  'invoices': <Object>[],
  'purchase_invoices': <Object>[],
  'business_documents': <Object>[],
  'employees': [
    for (final branchId in branchIds)
      {
        ..._employeeDetail()['employee'] as Map<String, dynamic>,
        'id': '$employee-${branchId == branchA ? 'a' : 'b'}',
        'tenant_id': tenantId,
        'branch_id': branchId,
      },
  ],
  'employee_advances': <Object>[],
  'payroll_runs': <Object>[],
  'payroll_run_items': <Object>[],
  'payroll_advance_allocations': <Object>[],
  'payroll_period_claims': <Object>[],
  'payroll_payments': <Object>[],
  'payroll_payment_items': <Object>[],
};

Map<String, dynamic> _snapshot() => {
  'employees': [
    {
      ..._employeeDetail()['employee'] as Map<String, dynamic>,
      'tenant_id': tenantA,
    },
  ],
  'employee_advances': [
    {
      ..._advanceDetail()['advance'] as Map<String, dynamic>,
      'tenant_id': tenantA,
    },
  ],
  'payroll_runs': [
    {
      'id': run,
      'tenant_id': tenantA,
      'branch_id': branchA,
      'document_kind': 'payroll_run',
      'reversal_of_id': null,
      'actor_id': 'actor',
      'device_id': 'device',
      'local_operation_id': 'run-op',
      'original_request_signature': 'signature',
      'restore_generation': 0,
      'operation_created_at': '2026-11-01T00:00:00.000Z',
      'occurred_at': '2026-11-30T00:00:00.000Z',
      'period_month': '2026-11',
      'selection_mode': 'selected',
      'total_gross_minor': 100000,
      'total_applied_minor': 25000,
      'total_net_minor': 75000,
      'status': 'approved',
      'reason': null,
      'created_at': '2026-11-30T00:00:00.000Z',
      'updated_at': '2026-11-30T00:00:00.000Z',
    },
  ],
  'payroll_run_items': [
    {
      'id': runItem,
      'tenant_id': tenantA,
      'branch_id': branchA,
      'payroll_run_id': run,
      'employee_id': employee,
      'employee_name_snapshot': 'Employee',
      'employee_phone_snapshot': null,
      'employee_base_salary_minor_snapshot': 100000,
      'gross_minor': 100000,
      'applied_advance_minor': 25000,
      'net_minor': 75000,
      'created_at': '2026-11-30T00:00:00.000Z',
    },
  ],
  'payroll_advance_allocations': [
    {
      'id': 'allocation',
      'tenant_id': tenantA,
      'branch_id': branchA,
      'payroll_run_id': run,
      'payroll_run_item_id': runItem,
      'employee_advance_id': advance,
      'employee_id': employee,
      'amount_minor': 25000,
      'created_at': '2026-11-30T00:00:00.000Z',
    },
  ],
  'payroll_period_claims': [
    {
      'id': 'claim',
      'tenant_id': tenantA,
      'branch_id': branchA,
      'employee_id': employee,
      'period_month': '2026-11',
      'payroll_run_id': run,
      'payroll_run_item_id': runItem,
      'created_at': '2026-11-30T00:00:00.000Z',
    },
  ],
  'payroll_payments': [
    {
      'id': payment,
      'tenant_id': tenantA,
      'branch_id': branchA,
      'payroll_run_id': run,
      'document_kind': 'payroll_payment',
      'reversal_of_id': null,
      'actor_id': 'actor',
      'device_id': 'device',
      'local_operation_id': 'payment-op',
      'original_request_signature': 'signature',
      'restore_generation': 0,
      'operation_created_at': '2026-11-30T00:00:00.000Z',
      'occurred_at': '2026-11-30T00:00:00.000Z',
      'account_code': '1110-CASH',
      'total_minor': 75000,
      'status': 'posted',
      'reason': null,
      'created_at': '2026-11-30T00:00:00.000Z',
      'updated_at': '2026-11-30T00:00:00.000Z',
    },
  ],
  'payroll_payment_items': [
    {
      'id': 'payment-item',
      'tenant_id': tenantA,
      'branch_id': branchA,
      'payroll_payment_id': payment,
      'payroll_run_item_id': runItem,
      'employee_id': employee,
      'employee_name_snapshot': 'Employee',
      'employee_phone_snapshot': null,
      'amount_minor': 75000,
      'created_at': '2026-11-30T00:00:00.000Z',
    },
  ],
};

Map<String, dynamic> _employeeDetail() => {
  'employee': {
    'id': employee,
    'tenant_id': tenantA,
    'branch_id': branchA,
    'name': 'Employee',
    'phone': null,
    'base_salary_minor': 100000,
    'start_date': '2026-01-01',
    'notes': null,
    'active': true,
    'version': 1,
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-01-01T00:00:00.000Z',
  },
};

Map<String, dynamic> _advanceDetail() => {
  'advance': {
    'id': advance,
    'tenant_id': tenantA,
    'branch_id': branchA,
    'employee_id': employee,
    'document_kind': 'employee_advance',
    'reversal_of_id': null,
    'employee': {
      'id': employee,
      'name': 'Employee',
      'phone': null,
      'base_salary_minor': 100000,
    },
    'occurred_at': '2026-11-01T00:00:00.000Z',
    'category': 'advance',
    'note': 'Advance',
    'account_code': '1110-CASH',
    'amount_minor': 25000,
    'status': 'posted',
    'reason': null,
    'device_id': 'device',
    'local_operation_id': 'advance-op',
    'restore_generation': 0,
    'operation_created_at': '2026-11-01T00:00:00.000Z',
    'created_at': '2026-11-01T00:00:00.000Z',
    'updated_at': '2026-11-01T00:00:00.000Z',
  },
  'journal': {
    'id': 'journal',
    'branch_id': branchA,
    'reference_type': 'employee_advance',
    'reference_id': advance,
    'reversal_of_id': null,
    'posted_at': '2026-11-01T00:00:00.000Z',
    'lines': <Object>[],
  },
  'employee_balance_minor': 25000,
};

class _ReadTransport implements JsonTransport {
  _ReadTransport(this.value);
  final Map<String, dynamic> value;
  late Uri uri;

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String>? headers,
    String? body,
  }) async {
    this.uri = uri;
    expect(method, 'GET');
    return JsonResponse(statusCode: 200, body: jsonEncode(value));
  }
}

class _SnapshotTransport implements JsonTransport {
  _SnapshotTransport(this.snapshots);

  final List<Map<String, dynamic>> snapshots;
  final List<String> paths = [];

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String>? headers,
    String? body,
  }) async {
    paths.add(uri.path);
    expect(method, 'GET');
    if (uri.path.endsWith('/sync/changes')) {
      final next = snapshots.first;
      final generation = next['restore_generation'] as int;
      return JsonResponse(
        statusCode: 200,
        body: jsonEncode({
          'changes': <Object>[],
          'next_cursor': next['snapshot_cursor'],
          'has_more': false,
          'restore_generation': generation,
          if (generation > 0) 'restore_epoch': '2026-10-31T00:00:00.000Z',
        }),
      );
    }
    expect(
      uri.queryParameters['restore_generation'],
      '${snapshots.first['restore_generation']}',
    );
    return JsonResponse(
      statusCode: 200,
      body: jsonEncode(snapshots.removeAt(0)),
    );
  }
}

class _RetryingCoordinatorTransport implements JsonTransport {
  int failedRequests = 0;

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String>? headers,
    String? body,
  }) async {
    if (uri.path.endsWith('/sync/changes') && failedRequests == 0) {
      failedRequests++;
      return const JsonResponse(statusCode: 503, body: '{}');
    }
    if (uri.path.endsWith('/sync/snapshot')) {
      return JsonResponse(
        statusCode: 200,
        body: jsonEncode(
          _bootstrapSnapshot(
            tenantId: tenantA,
            branchIds: const [branchA],
            cursor: 2,
          ),
        ),
      );
    }
    return JsonResponse(
      statusCode: 200,
      body: jsonEncode({
        'changes': <Object>[],
        'next_cursor': 2,
        'has_more': false,
        'restore_generation': 0,
      }),
    );
  }
}
