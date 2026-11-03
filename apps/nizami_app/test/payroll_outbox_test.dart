import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/payroll/payroll_api.dart';
import 'package:nizami/src/features/payroll/payroll_cache.dart';
import 'package:nizami/src/features/payroll/payroll_models.dart';
import 'package:nizami/src/features/sync/payroll_outbox.dart';
import 'package:nizami/src/features/sync/quarantined_operation_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const tenant = '11111111-1111-4111-8111-111111111111';
const branch = '22222222-2222-4222-8222-222222222222';
const otherBranch = '22222222-2222-4222-8222-222222222223';
const device = '33333333-3333-4333-8333-333333333333';
const employee = '44444444-4444-4444-8444-444444444444';
const advance = '55555555-5555-4555-8555-555555555555';
const run = '66666666-6666-4666-8666-666666666666';
const runItem = '77777777-7777-4777-8777-777777777777';
const payment = '88888888-8888-4888-8888-888888888888';
const advanceReversal = '55555555-5555-4555-8555-555555555556';
const runReversal = '66666666-6666-4666-8666-666666666667';
const paymentReversal = '88888888-8888-4888-8888-888888888889';

const operationEndpoints = <(PayrollOperationKind, String, String, String)>[
  (
    PayrollOperationKind.employeeCreate,
    employee,
    'POST',
    '/api/v1/accounting/employees',
  ),
  (
    PayrollOperationKind.employeeUpdate,
    employee,
    'PUT',
    '/api/v1/accounting/employees/$employee',
  ),
  (
    PayrollOperationKind.employeeDeactivate,
    employee,
    'POST',
    '/api/v1/accounting/employees/$employee/deactivate',
  ),
  (
    PayrollOperationKind.advancePost,
    advance,
    'POST',
    '/api/v1/accounting/employee-advances',
  ),
  (
    PayrollOperationKind.advanceReversal,
    advance,
    'POST',
    '/api/v1/accounting/employee-advances/$advance/reversals',
  ),
  (
    PayrollOperationKind.payrollRunApproval,
    run,
    'POST',
    '/api/v1/accounting/payroll-runs',
  ),
  (
    PayrollOperationKind.payrollRunReversal,
    run,
    'POST',
    '/api/v1/accounting/payroll-runs/$run/reversals',
  ),
  (
    PayrollOperationKind.payrollPaymentPost,
    run,
    'POST',
    '/api/v1/accounting/payroll-runs/$run/payments',
  ),
  (
    PayrollOperationKind.payrollPaymentReversal,
    payment,
    'POST',
    '/api/v1/accounting/payroll-payments/$payment/reversals',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('money DTOs reject double JSON and preserve integer serialization', () {
    expect(
      () => Employee.fromJson({..._employeeJson(), 'base_salary_minor': 1.0}),
      throwsFormatException,
    );
    final value = Employee.fromJson({
      ..._employeeJson(),
      'base_salary_minor': 9007199254740991,
    });
    expect(value.baseSalaryMinor, 9007199254740991);
    expect(value.toJson()['base_salary_minor'], isA<int>());
  });

  test(
    'payroll API uses signed preview and narrow settlement endpoints',
    () async {
      final transport = _Transport((uri, method, body) async {
        if (uri.path.endsWith('/accounting/payroll-runs/preview')) {
          expect(method, 'POST');
          final request = jsonDecode(body!) as Map<String, dynamic>;
          expect(request['employee_ids'], [employee]);
          return _response({
            'preview_version': 1,
            'preview_signature':
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'restore_generation': 7,
            'branch_id': branch,
            'period_month': '2026-10',
            'selection_mode': 'selected',
            'employee_ids': [employee],
            'confirmed_at': '2026-11-01T08:00:00.000Z',
            'items': [
              {
                'employee_id': employee,
                'employee_name': 'Canonical employee',
                'gross_minor': 100000,
                'applied_advance_minor': 25000,
                'net_minor': 75000,
              },
            ],
            'totals': {
              'gross_minor': 100000,
              'applied_advance_minor': 25000,
              'net_minor': 75000,
            },
          });
        }
        expect(uri.path, '/api/v1/accounting/payroll-settlement-accounts');
        expect(uri.queryParameters['branch_id'], branch);
        expect(method, 'GET');
        return _response({
          'items': [
            {
              'id': 'cash-id',
              'code': '1100-CASH',
              'name': 'Cash',
              'channel': 'cash',
              'version': 1,
            },
          ],
        });
      });
      final api = PayrollApi(token: 'token', transport: transport);

      final preview = await api.fetchPayrollPreview(
        branchId: branch,
        periodMonth: '2026-10',
        selectionMode: 'selected',
        employeeIds: const [employee],
        restoreGeneration: 7,
      );
      final accounts = await api.fetchPayrollSettlementAccounts(branch);

      expect(preview.signature, hasLength(64));
      expect(preview.netMinor, 75000);
      expect(accounts.single.code, '1100-CASH');
      expect(accounts.single.isCashEquivalent, isTrue);
    },
  );

  test('all operation kinds persist immutable bytes across restart', () async {
    final cases = <(PayrollOperationKind, String, Map<String, dynamic>)>[
      (PayrollOperationKind.employeeCreate, employee, _employeeCreate('op-1')),
      (PayrollOperationKind.employeeUpdate, employee, _employeeUpdate('op-2')),
      (
        PayrollOperationKind.employeeDeactivate,
        employee,
        _employeeDeactivate('op-3'),
      ),
      (PayrollOperationKind.advancePost, advance, _advancePost('op-4')),
      (PayrollOperationKind.advanceReversal, advance, _reversal('op-5')),
      (PayrollOperationKind.payrollRunApproval, run, _runApproval('op-6')),
      (PayrollOperationKind.payrollRunReversal, run, _reversal('op-7')),
      (PayrollOperationKind.payrollPaymentPost, payment, _paymentPost('op-8')),
      (PayrollOperationKind.payrollPaymentReversal, payment, _reversal('op-9')),
    ];
    final queue = PayrollOutbox(tenant, branch);
    for (final value in cases) {
      await queue.enqueue(
        kind: value.$1,
        aggregateId: value.$2,
        request: value.$3,
      );
    }
    final before = (await queue.list()).map((row) => row.requestBody).toList();
    final restarted = PayrollOutbox(tenant, branch);
    final after = (await restarted.list())
        .map((row) => row.requestBody)
        .toList();
    expect(after, before);
    for (var index = 0; index < cases.length; index++) {
      expect(after[index], jsonEncode(cases[index].$3));
    }
  });

  test(
    'every operation retries byte-identical persisted bytes after restart',
    () async {
      for (final kind in PayrollOperationKind.values) {
        SharedPreferences.setMockInitialValues({});
        final operation = 'retry-${kind.name}';
        final request = _requestFor(kind, operation);
        await PayrollCache(tenant, branch).replaceSnapshot(_seedFor(kind));
        final queue = PayrollOutbox(tenant, branch);
        await queue.enqueue(
          kind: kind,
          aggregateId: _aggregateFor(kind),
          request: request,
        );
        final firstTransport = _Transport(
          (uri, method, body) async => const JsonResponse(
            statusCode: 503,
            body: 'temporarily unavailable',
          ),
        );
        final first = await queue.flush(
          api: PayrollApi(token: 'token', transport: firstTransport),
          currentRestoreGeneration: 0,
        );
        expect(first.sent, 0, reason: kind.name);
        expect(firstTransport.bodies, hasLength(1), reason: kind.name);

        final secondTransport = _Transport((uri, method, body) async {
          final persisted = jsonDecode(body!) as Map<String, dynamic>;
          return _response(_ackFor(kind, persisted));
        });
        final second = await PayrollOutbox(tenant, branch).flush(
          api: PayrollApi(token: 'token', transport: secondTransport),
          currentRestoreGeneration: 0,
        );

        expect(second.sent, 1, reason: kind.name);
        expect(
          secondTransport.bodies,
          firstTransport.bodies,
          reason: kind.name,
        );
        expect(await queue.count(), 0, reason: kind.name);
      }
    },
  );

  test('every operation keeps its row until full canonical ACK', () async {
    for (final kind in PayrollOperationKind.values) {
      SharedPreferences.setMockInitialValues({});
      final request = _requestFor(kind, 'bad-ack-${kind.name}');
      await PayrollCache(tenant, branch).replaceSnapshot(_seedFor(kind));
      final queue = PayrollOutbox(tenant, branch);
      await queue.enqueue(
        kind: kind,
        aggregateId: _aggregateFor(kind),
        request: request,
      );
      final result = await queue.flush(
        api: PayrollApi(
          token: 'token',
          transport: _Transport((uri, method, body) async {
            final persisted = jsonDecode(body!) as Map<String, dynamic>;
            final ack = _ackFor(kind, persisted);
            final key = switch (kind.aggregateType) {
              'employee' => 'employee',
              'employee_advance' => 'advance',
              'payroll_run' => 'run',
              _ => 'payment',
            };
            (ack[key] as Map<String, dynamic>)['local_operation_id'] = 'wrong';
            return _response(ack);
          }),
        ),
        currentRestoreGeneration: 0,
      );

      expect(result.sent, 0, reason: kind.name);
      expect(await queue.count(), 1, reason: kind.name);
    }
  });

  test(
    'employee create ACK is cached before dependent advance posts',
    () async {
      final transport = _Transport((uri, method, body) async {
        final request = jsonDecode(body!) as Map<String, dynamic>;
        if (uri.path.endsWith('/accounting/employees')) {
          return _response(_employeeAck(request));
        }
        return _response(_advanceAck(request));
      });
      final queue = PayrollOutbox(tenant, branch);
      await queue.enqueue(
        kind: PayrollOperationKind.employeeCreate,
        aggregateId: employee,
        request: _employeeCreate('op-create'),
      );
      await queue.enqueue(
        kind: PayrollOperationKind.advancePost,
        aggregateId: advance,
        request: _advancePost('op-advance'),
      );

      final result = await queue.flush(
        api: PayrollApi(token: 'token', transport: transport),
        currentRestoreGeneration: 0,
      );

      expect(result.sent, 2);
      expect(transport.paths, [
        '/api/v1/accounting/employees',
        '/api/v1/accounting/employee-advances',
      ]);
      final cached = await PayrollCache(tenant, branch).read();
      expect(cached.employees.single.id, employee);
      expect(cached.employeeAdvances.single.id, advance);
      expect(await queue.count(), 0);
    },
  );

  test(
    'employee then advance then run drain in one dependency-ordered flush',
    () async {
      final transport = _Transport((uri, method, body) async {
        final request = jsonDecode(body!) as Map<String, dynamic>;
        if (uri.path.endsWith('/accounting/employees')) {
          return _response(_employeeAck(request));
        }
        if (uri.path.endsWith('/accounting/employee-advances')) {
          return _response(_advanceAck(request));
        }
        return _response(_runAck(request));
      });
      final queue = PayrollOutbox(tenant, branch);
      await queue.enqueue(
        kind: PayrollOperationKind.employeeCreate,
        aggregateId: employee,
        request: _employeeCreate('chain-create'),
      );
      await queue.enqueue(
        kind: PayrollOperationKind.advancePost,
        aggregateId: advance,
        request: _advancePost('chain-advance'),
      );
      await queue.enqueue(
        kind: PayrollOperationKind.payrollRunApproval,
        aggregateId: run,
        request: _runApproval('chain-run'),
      );

      final result = await queue.flush(
        api: PayrollApi(token: 'token', transport: transport),
        currentRestoreGeneration: 0,
      );

      expect(result.sent, 3);
      expect(transport.paths, [
        '/api/v1/accounting/employees',
        '/api/v1/accounting/employee-advances',
        '/api/v1/accounting/payroll-runs',
      ]);
      expect(
        (await PayrollCache(tenant, branch).read()).payrollRuns.single.id,
        run,
      );
    },
  );

  test(
    'deactivation queued first waits for later finance across restart',
    () async {
      await PayrollCache(
        tenant,
        branch,
      ).replaceSnapshot(_cacheSnapshot(employees: [_employeeJson()]));
      final deactivateRequest = {
        ..._employeeDeactivate('deactivate-after-finance'),
        'expected_version': 1,
      };
      final queue = PayrollOutbox(tenant, branch);
      await queue.enqueue(
        kind: PayrollOperationKind.employeeDeactivate,
        aggregateId: employee,
        request: deactivateRequest,
      );
      await queue.enqueue(
        kind: PayrollOperationKind.advancePost,
        aggregateId: advance,
        request: _advancePost('finance-before-deactivate'),
      );
      final transport = _Transport((uri, method, body) async {
        final request = jsonDecode(body!) as Map<String, dynamic>;
        if (uri.path.endsWith('/accounting/employee-advances')) {
          return _response(_advanceAck(request));
        }
        return _response(_employeeAck(request, version: 2, active: false));
      });

      final result = await PayrollOutbox(tenant, branch).flush(
        api: PayrollApi(token: 'token', transport: transport),
        currentRestoreGeneration: 0,
      );

      expect(result.sent, 2);
      expect(transport.paths, [
        '/api/v1/accounting/employee-advances',
        '/api/v1/accounting/employees/$employee/deactivate',
      ]);
      expect(await queue.count(), 0);
      expect(
        (await PayrollCache(tenant, branch).read()).employees.single.active,
        isFalse,
      );
    },
  );

  test('finance queued first still drains before deactivation', () async {
    await PayrollCache(
      tenant,
      branch,
    ).replaceSnapshot(_cacheSnapshot(employees: [_employeeJson()]));
    final queue = PayrollOutbox(tenant, branch);
    await queue.enqueue(
      kind: PayrollOperationKind.advancePost,
      aggregateId: advance,
      request: _advancePost('finance-first'),
    );
    await queue.enqueue(
      kind: PayrollOperationKind.employeeDeactivate,
      aggregateId: employee,
      request: {
        ..._employeeDeactivate('deactivate-second'),
        'expected_version': 1,
      },
    );
    final transport = _Transport((uri, method, body) async {
      final request = jsonDecode(body!) as Map<String, dynamic>;
      return uri.path.endsWith('/accounting/employee-advances')
          ? _response(_advanceAck(request))
          : _response(_employeeAck(request, version: 2, active: false));
    });

    final result = await PayrollOutbox(tenant, branch).flush(
      api: PayrollApi(token: 'token', transport: transport),
      currentRestoreGeneration: 0,
    );

    expect(result.sent, 2);
    expect(transport.paths, [
      '/api/v1/accounting/employee-advances',
      '/api/v1/accounting/employees/$employee/deactivate',
    ]);
  });

  test(
    'run reversal waits for payment reversal in either enqueue order',
    () async {
      for (final runFirst in [true, false]) {
        SharedPreferences.setMockInitialValues({});
        await PayrollCache(tenant, branch).replaceSnapshot(
          _seedFor(PayrollOperationKind.payrollPaymentReversal),
        );
        final queue = PayrollOutbox(tenant, branch);
        Future<void> enqueueRun() => queue.enqueue(
          kind: PayrollOperationKind.payrollRunReversal,
          aggregateId: run,
          request: _reversal('run-reversal-$runFirst'),
        );
        Future<void> enqueuePayment() => queue.enqueue(
          kind: PayrollOperationKind.payrollPaymentReversal,
          aggregateId: payment,
          request: _reversal('payment-reversal-$runFirst'),
        );
        if (runFirst) {
          await enqueueRun();
          await enqueuePayment();
        } else {
          await enqueuePayment();
          await enqueueRun();
        }
        final transport = _Transport((uri, method, body) async {
          final request = jsonDecode(body!) as Map<String, dynamic>;
          return uri.path.contains('/payroll-payments/')
              ? _response(_paymentReversalAck(request))
              : _response(_runReversalAck(request));
        });

        final result = await PayrollOutbox(tenant, branch).flush(
          api: PayrollApi(token: 'token', transport: transport),
          currentRestoreGeneration: 0,
        );

        expect(result.sent, 2, reason: 'runFirst=$runFirst');
        expect(transport.paths, [
          '/api/v1/accounting/payroll-payments/$payment/reversals',
          '/api/v1/accounting/payroll-runs/$run/reversals',
        ]);
        expect(await queue.count(), 0);
      }
    },
  );

  test(
    'advance reversal precedes related run approval in either enqueue order after restart',
    () async {
      for (final approvalFirst in [true, false]) {
        SharedPreferences.setMockInitialValues({});
        await PayrollCache(
          tenant,
          branch,
        ).replaceSnapshot(_seedFor(PayrollOperationKind.advanceReversal));
        final queue = PayrollOutbox(tenant, branch);
        Future<void> enqueueApproval() => queue.enqueue(
          kind: PayrollOperationKind.payrollRunApproval,
          aggregateId: run,
          request: _runApproval('approve-after-reversal-$approvalFirst'),
        );
        Future<void> enqueueReversal() => queue.enqueue(
          kind: PayrollOperationKind.advanceReversal,
          aggregateId: advance,
          request: _reversal('reverse-before-approval-$approvalFirst'),
        );
        if (approvalFirst) {
          await enqueueApproval();
          await enqueueReversal();
        } else {
          await enqueueReversal();
          await enqueueApproval();
        }
        final transport = _Transport((uri, method, body) async {
          final request = jsonDecode(body!) as Map<String, dynamic>;
          return uri.path.contains('/employee-advances/')
              ? _response(_advanceReversalAck(request))
              : _response(_runAck(request, applyAdvance: false));
        });

        final result = await PayrollOutbox(tenant, branch).flush(
          api: PayrollApi(token: 'token', transport: transport),
          currentRestoreGeneration: 0,
        );

        expect(result.sent, 2, reason: 'approvalFirst=$approvalFirst');
        expect(transport.paths, [
          '/api/v1/accounting/employee-advances/$advance/reversals',
          '/api/v1/accounting/payroll-runs',
        ], reason: 'approvalFirst=$approvalFirst');
        expect(await queue.count(), 0, reason: 'approvalFirst=$approvalFirst');
      }
    },
  );

  test(
    'advance reversal conflict blocks approval in both orders and flush modes',
    () async {
      final cases = <({bool approvalFirst, bool restartAfterConflict})>[
        (approvalFirst: true, restartAfterConflict: false),
        (approvalFirst: false, restartAfterConflict: false),
        (approvalFirst: true, restartAfterConflict: true),
        (approvalFirst: false, restartAfterConflict: true),
      ];
      for (final value in cases) {
        SharedPreferences.setMockInitialValues({});
        final reason =
            'approvalFirst=${value.approvalFirst}, '
            'restartAfterConflict=${value.restartAfterConflict}';
        await PayrollCache(
          tenant,
          branch,
        ).replaceSnapshot(_seedFor(PayrollOperationKind.advanceReversal));
        final queue = PayrollOutbox(tenant, branch);
        Future<void> enqueueApproval() => queue.enqueue(
          kind: PayrollOperationKind.payrollRunApproval,
          aggregateId: run,
          request: _runApproval('approval-conflict-$reason'),
        );
        Future<void> enqueueReversal() => queue.enqueue(
          kind: PayrollOperationKind.advanceReversal,
          aggregateId: advance,
          request: _reversal('reversal-conflict-$reason'),
        );
        if (value.approvalFirst) {
          await enqueueApproval();
          await enqueueReversal();
        } else {
          await enqueueReversal();
          await enqueueApproval();
        }
        final transport = _Transport(
          (uri, method, body) async => JsonResponse(
            statusCode: 422,
            body: jsonEncode({'message': 'ADVANCE_REVERSAL_CONFLICT'}),
          ),
        );

        final first = await PayrollOutbox(tenant, branch).flush(
          api: PayrollApi(token: 'token', transport: transport),
          currentRestoreGeneration: 0,
          maxPerCycle: value.restartAfterConflict ? 1 : 12,
        );

        expect(first.sent, 0, reason: reason);
        expect(
          first.needsReview,
          value.restartAfterConflict ? 1 : 2,
          reason: reason,
        );
        expect(transport.paths, [
          '/api/v1/accounting/employee-advances/$advance/reversals',
        ], reason: reason);

        if (value.restartAfterConflict) {
          expect(
            (await queue.list()).map((entry) => entry.state),
            containsAll([
              PayrollOutboxState.queued,
              PayrollOutboxState.needsReview,
            ]),
            reason: reason,
          );
          final restartedTransport = _Transport((uri, method, body) async {
            fail('review-blocked approval must not be sent: $reason');
          });
          final second = await PayrollOutbox(tenant, branch).flush(
            api: PayrollApi(token: 'token', transport: restartedTransport),
            currentRestoreGeneration: 0,
          );
          expect(second.sent, 0, reason: reason);
          expect(second.needsReview, 1, reason: reason);
          expect(restartedTransport.paths, isEmpty, reason: reason);
        }
        expect(
          (await queue.list()).map((entry) => entry.state),
          everyElement(PayrollOutboxState.needsReview),
          reason: reason,
        );
      }
    },
  );

  test(
    'run reversal becomes reviewable when a queued payment posts first',
    () async {
      await PayrollCache(
        tenant,
        branch,
      ).replaceSnapshot(_seedFor(PayrollOperationKind.payrollPaymentPost));
      final queue = PayrollOutbox(tenant, branch);
      await queue.enqueue(
        kind: PayrollOperationKind.payrollRunReversal,
        aggregateId: run,
        request: _reversal('reverse-run-before-payment'),
      );
      await queue.enqueue(
        kind: PayrollOperationKind.payrollPaymentPost,
        aggregateId: run,
        request: _paymentPost('post-payment-before-run-reversal'),
      );

      final result = await queue.flush(
        api: PayrollApi(
          token: 'token',
          transport: _Transport((uri, method, body) async {
            final request = jsonDecode(body!) as Map<String, dynamic>;
            return _response(_paymentAck(request));
          }),
        ),
        currentRestoreGeneration: 0,
      );

      expect(result.sent, 1);
      expect(result.needsReview, 1);
      expect((await queue.list()).single.state, PayrollOutboxState.needsReview);
    },
  );

  test('concurrent flush is one tenant-wide HTTP flight', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final transport = _Transport((uri, method, body) async {
      started.complete();
      await release.future;
      return _response(_employeeAck(jsonDecode(body!) as Map<String, dynamic>));
    });
    final queue = PayrollOutbox(tenant, branch);
    await queue.enqueue(
      kind: PayrollOperationKind.employeeCreate,
      aggregateId: employee,
      request: _employeeCreate('op-flight'),
    );
    final api = PayrollApi(token: 'token', transport: transport);
    final first = queue.flush(api: api, currentRestoreGeneration: 0);
    await started.future;
    final second = queue.flush(api: api, currentRestoreGeneration: 0);
    release.complete();
    expect((await first).sent, 1);
    expect((await second).sent, 0);
    expect(transport.bodies, hasLength(1));
  });

  test(
    'same tenant operation ID with changed path or body conflicts',
    () async {
      await PayrollOutbox(tenant, branch).enqueue(
        kind: PayrollOperationKind.employeeCreate,
        aggregateId: employee,
        request: _employeeCreate('op-conflict'),
      );
      await expectLater(
        PayrollOutbox(tenant, otherBranch).enqueue(
          kind: PayrollOperationKind.employeeCreate,
          aggregateId: 'different',
          request: {
            ..._employeeCreate('op-conflict'),
            'id': 'different',
            'branch_id': otherBranch,
          },
        ),
        throwsStateError,
      );
    },
  );

  test(
    'malformed canonical success stays queued and cache unchanged',
    () async {
      await PayrollCache(tenant, branch).replaceSnapshot({
        'employees': [_employeeJson()],
        'employee_advances': <Object>[],
        'payroll_runs': <Object>[],
        'payroll_run_items': <Object>[],
        'payroll_advance_allocations': <Object>[],
        'payroll_period_claims': <Object>[],
        'payroll_payments': <Object>[],
        'payroll_payment_items': <Object>[],
      });
      final queue = PayrollOutbox(tenant, branch);
      await queue.enqueue(
        kind: PayrollOperationKind.advancePost,
        aggregateId: advance,
        request: _advancePost('op-bad-ack'),
      );
      final transport = _Transport((uri, method, body) async {
        final ack = _advanceAck(jsonDecode(body!) as Map<String, dynamic>);
        (ack['advance'] as Map<String, dynamic>)['local_operation_id'] =
            'wrong';
        return _response(ack);
      });
      final result = await queue.flush(
        api: PayrollApi(token: 'token', transport: transport),
        currentRestoreGeneration: 0,
      );
      expect(result.sent, 0);
      expect(transport.bodies, hasLength(1));
      expect(await queue.count(), 1);
      expect(
        (await PayrollCache(tenant, branch).read()).employeeAdvances,
        isEmpty,
      );
    },
  );

  test('employee ACK requires full operation and aggregate identity', () async {
    final mismatches = <String, Object?>{
      'device_id': 'wrong-device',
      'local_operation_id': 'wrong-operation',
      'restore_generation': 9,
      'tenant_id': 'wrong-tenant',
      'branch_id': otherBranch,
      'id': 'wrong-employee',
    };
    for (final mismatch in mismatches.entries) {
      SharedPreferences.setMockInitialValues({});
      final request = _employeeCreate('employee-ack-${mismatch.key}');
      final queue = PayrollOutbox(tenant, branch);
      await queue.enqueue(
        kind: PayrollOperationKind.employeeCreate,
        aggregateId: employee,
        request: request,
      );
      final result = await queue.flush(
        api: PayrollApi(
          token: 'token',
          transport: _Transport((uri, method, body) async {
            final ack = _employeeAck(request);
            (ack['employee'] as Map<String, dynamic>)[mismatch.key] =
                mismatch.value;
            return _response(ack);
          }),
        ),
        currentRestoreGeneration: 0,
      );

      expect(result.sent, 0, reason: mismatch.key);
      expect(await queue.count(), 1, reason: mismatch.key);
      expect(
        (await PayrollCache(tenant, branch).read()).employees,
        isEmpty,
        reason: mismatch.key,
      );
    }
  });

  test('401 leaves every operation kind queued and uncached', () async {
    expect(
      operationEndpoints.map((value) => value.$1),
      unorderedEquals(PayrollOperationKind.values),
    );
    for (final value in operationEndpoints) {
      SharedPreferences.setMockInitialValues({});
      final kind = value.$1;
      final cache = PayrollCache(tenant, branch);
      await cache.replaceSnapshot(_seedFor(kind));
      final before = jsonEncode((await cache.read()).toJson());
      final queue = PayrollOutbox(tenant, branch);
      final request = _requestFor(kind, 'unauthorized-${kind.name}');
      final body = jsonEncode(request);
      final transport = _Transport(
        (uri, method, body) async => JsonResponse(
          statusCode: 401,
          body: jsonEncode({'message': 'Unauthenticated.'}),
        ),
      );
      await queue.enqueue(kind: kind, aggregateId: value.$2, request: request);
      final result = await queue.flush(
        api: PayrollApi(token: 'token', transport: transport),
        currentRestoreGeneration: 0,
      );
      expect(result.sent, 0, reason: kind.name);
      expect(transport.paths, [value.$4], reason: kind.name);
      expect(transport.methods, [value.$3], reason: kind.name);
      expect(transport.bodies, [body], reason: kind.name);
      expect(
        (await queue.list()).single.state,
        PayrollOutboxState.queued,
        reason: kind.name,
      );
      expect(
        jsonEncode((await cache.read()).toJson()),
        before,
        reason: kind.name,
      );
    }
  });

  test('deterministic 4xx makes every operation kind durable review', () async {
    expect(
      operationEndpoints.map((value) => value.$1),
      unorderedEquals(PayrollOperationKind.values),
    );
    for (final value in operationEndpoints) {
      SharedPreferences.setMockInitialValues({});
      final kind = value.$1;
      final cache = PayrollCache(tenant, branch);
      await cache.replaceSnapshot(_seedFor(kind));
      final before = jsonEncode((await cache.read()).toJson());
      final queue = PayrollOutbox(tenant, branch);
      final request = _requestFor(kind, 'review-${kind.name}');
      final body = jsonEncode(request);
      final transport = _Transport(
        (uri, method, body) async => JsonResponse(
          statusCode: 422,
          body: jsonEncode({'message': 'REJECTED'}),
        ),
      );
      await queue.enqueue(kind: kind, aggregateId: value.$2, request: request);
      final result = await queue.flush(
        api: PayrollApi(token: 'token', transport: transport),
        currentRestoreGeneration: 0,
      );
      expect(result.needsReview, 1, reason: kind.name);
      expect(transport.paths, [value.$4], reason: kind.name);
      expect(transport.methods, [value.$3], reason: kind.name);
      expect(transport.bodies, [body], reason: kind.name);
      expect(
        (await queue.list()).single.state,
        PayrollOutboxState.needsReview,
        reason: kind.name,
      );
      expect(
        jsonEncode((await cache.read()).toJson()),
        before,
        reason: kind.name,
      );
    }
  });

  test(
    'restore mismatch quarantines every operation kind without HTTP',
    () async {
      for (final kind in PayrollOperationKind.values) {
        SharedPreferences.setMockInitialValues({});
        final cache = PayrollCache(tenant, branch);
        await cache.replaceSnapshot(_seedFor(kind));
        final before = jsonEncode((await cache.read()).toJson());
        final queue = PayrollOutbox(tenant, branch);
        final operation = 'restore-${kind.name}';
        await queue.enqueue(
          kind: kind,
          aggregateId: _aggregateFor(kind),
          request: _requestFor(kind, operation),
        );
        final transport = _Transport((uri, method, body) async {
          fail('quarantined ${kind.name} work must not be sent');
        });
        final result = await queue.flush(
          api: PayrollApi(token: 'token', transport: transport),
          currentRestoreGeneration: 1,
        );
        expect(result.quarantined, 1, reason: kind.name);
        expect(transport.paths, isEmpty, reason: kind.name);
        expect(await queue.count(), 0, reason: kind.name);
        final quarantined = await QuarantinedOperationStore(tenant).list();
        expect(quarantined, hasLength(1), reason: kind.name);
        expect(
          quarantined.single['operation_id'],
          operation,
          reason: kind.name,
        );
        expect(
          jsonEncode((await cache.read()).toJson()),
          before,
          reason: kind.name,
        );
      }
    },
  );

  test(
    'server restore-boundary rejection quarantines every exact operation',
    () async {
      expect(
        operationEndpoints.map((value) => value.$1),
        unorderedEquals(PayrollOperationKind.values),
      );
      for (final value in operationEndpoints) {
        SharedPreferences.setMockInitialValues({});
        final kind = value.$1;
        final cache = PayrollCache(tenant, branch);
        await cache.replaceSnapshot(_seedFor(kind));
        final before = jsonEncode((await cache.read()).toJson());
        final operation = 'server-restore-${kind.name}';
        final request = _requestFor(kind, operation);
        final body = jsonEncode(request);
        final queue = PayrollOutbox(tenant, branch);
        final transport = _Transport(
          (uri, method, body) async => JsonResponse(
            statusCode: 409,
            body: jsonEncode({'message': 'RESTORE_GENERATION_MISMATCH'}),
          ),
        );
        await queue.enqueue(
          kind: kind,
          aggregateId: value.$2,
          request: request,
        );
        final result = await queue.flush(
          api: PayrollApi(token: 'token', transport: transport),
          currentRestoreGeneration: 0,
        );

        expect(result.quarantined, 1, reason: kind.name);
        expect(transport.paths, [value.$4], reason: kind.name);
        expect(transport.methods, [value.$3], reason: kind.name);
        expect(transport.bodies, [body], reason: kind.name);
        expect(await queue.count(), 0, reason: kind.name);
        final quarantined = await QuarantinedOperationStore(tenant).list();
        expect(quarantined, hasLength(1), reason: kind.name);
        expect(
          quarantined.single['operation_id'],
          operation,
          reason: kind.name,
        );
        expect(
          quarantined.single['reason'],
          'RESTORE_GENERATION_MISMATCH',
          reason: kind.name,
        );
        expect(
          (quarantined.single['payload'] as Map)['request_body'],
          body,
          reason: kind.name,
        );
        expect(
          jsonEncode((await cache.read()).toJson()),
          before,
          reason: kind.name,
        );
      }
    },
  );

  test(
    'stale session response cannot cache or dequeue any operation kind',
    () async {
      for (final kind in PayrollOperationKind.values) {
        SharedPreferences.setMockInitialValues({});
        var current = true;
        final cache = PayrollCache(tenant, branch);
        await cache.replaceSnapshot(_seedFor(kind));
        final before = jsonEncode((await cache.read()).toJson());
        final queue = PayrollOutbox(tenant, branch);
        await queue.enqueue(
          kind: kind,
          aggregateId: _aggregateFor(kind),
          request: _requestFor(kind, 'stale-${kind.name}'),
        );
        final result = await queue.flush(
          api: PayrollApi(
            token: 'token',
            transport: _Transport((uri, method, body) async {
              current = false;
              return _response(
                _ackFor(kind, jsonDecode(body!) as Map<String, dynamic>),
              );
            }),
          ),
          currentRestoreGeneration: 0,
          isResponseValid: () => current,
        );
        expect(result.invalidated, 1, reason: kind.name);
        expect(await queue.count(), 1, reason: kind.name);
        expect(
          (await queue.list()).single.state,
          PayrollOutboxState.queued,
          reason: kind.name,
        );
        expect(
          jsonEncode((await cache.read()).toJson()),
          before,
          reason: kind.name,
        );
      }
    },
  );
}

Map<String, dynamic> _common(String operation) => {
  'device_id': device,
  'local_operation_id': operation,
  'restore_generation': 0,
  'operation_created_at': '2026-11-01T00:00:00.000Z',
};

Map<String, dynamic> _employeeCreate(String operation) => {
  ..._common(operation),
  'id': employee,
  'branch_id': branch,
  'name': 'Employee',
  'phone': null,
  'base_salary_minor': 100000,
  'start_date': '2026-01-01',
  'notes': null,
};

Map<String, dynamic> _employeeUpdate(String operation) => {
  ..._employeeCreate(operation),
  'expected_version': 1,
};

Map<String, dynamic> _employeeDeactivate(String operation) => {
  ..._common(operation),
  'id': employee,
  'branch_id': branch,
  'expected_version': 2,
};

Map<String, dynamic> _advancePost(String operation) => {
  ..._common(operation),
  'employee_id': employee,
  'branch_id': branch,
  'amount_minor': 25000,
  'category': 'advance',
  'note': 'Advance',
  'account_code': '1110-CASH',
  'occurred_at': '2026-11-01T01:00:00.000Z',
};

Map<String, dynamic> _runApproval(String operation) => {
  ..._common(operation),
  'branch_id': branch,
  'period_month': '2026-11',
  'selection_mode': 'selected',
  'employee_ids': [employee],
};

Map<String, dynamic> _paymentPost(String operation) => {
  ..._common(operation),
  'occurred_at': '2026-11-30T00:00:00.000Z',
  'account_code': '1110-CASH',
  'items': [
    {'payroll_run_item_id': runItem, 'amount_minor': 75000},
  ],
};

Map<String, dynamic> _reversal(String operation) => {
  ..._common(operation),
  'occurred_at': '2026-12-01T00:00:00.000Z',
  'reason': 'Correction required',
};

Map<String, dynamic> _employeeJson() => {
  'id': employee,
  'tenant_id': tenant,
  'branch_id': branch,
  'name': 'Employee',
  'phone': null,
  'base_salary_minor': 100000,
  'start_date': '2026-01-01',
  'notes': null,
  'active': true,
  'version': 1,
  'created_at': '2026-11-01T00:00:00.000Z',
  'updated_at': '2026-11-01T00:00:00.000Z',
};

Map<String, dynamic> _employeeAck(
  Map<String, dynamic> request, {
  int version = 1,
  bool active = true,
}) => {
  'employee': {
    ..._employeeJson(),
    'active': active,
    'version': version,
    'device_id': request['device_id'],
    'local_operation_id': request['local_operation_id'],
    'restore_generation': request['restore_generation'],
    'operation_created_at': request['operation_created_at'],
  },
};

Map<String, dynamic> _cacheSnapshot({
  List<Map<String, dynamic>> employees = const [],
  List<Map<String, dynamic>> advances = const [],
  List<Map<String, dynamic>> runs = const [],
  List<Map<String, dynamic>> runItems = const [],
  List<Map<String, dynamic>> allocations = const [],
  List<Map<String, dynamic>> claims = const [],
  List<Map<String, dynamic>> payments = const [],
  List<Map<String, dynamic>> paymentItems = const [],
}) => {
  'employees': employees,
  'employee_advances': advances,
  'payroll_runs': runs,
  'payroll_run_items': runItems,
  'payroll_advance_allocations': allocations,
  'payroll_period_claims': claims,
  'payroll_payments': payments,
  'payroll_payment_items': paymentItems,
};

String _aggregateFor(PayrollOperationKind kind) => switch (kind) {
  PayrollOperationKind.employeeCreate ||
  PayrollOperationKind.employeeUpdate ||
  PayrollOperationKind.employeeDeactivate => employee,
  PayrollOperationKind.advancePost => advance,
  PayrollOperationKind.advanceReversal => advance,
  PayrollOperationKind.payrollRunApproval => run,
  PayrollOperationKind.payrollRunReversal => run,
  PayrollOperationKind.payrollPaymentPost => run,
  PayrollOperationKind.payrollPaymentReversal => payment,
};

Map<String, dynamic> _requestFor(PayrollOperationKind kind, String operation) =>
    switch (kind) {
      PayrollOperationKind.employeeCreate => _employeeCreate(operation),
      PayrollOperationKind.employeeUpdate => _employeeUpdate(operation),
      PayrollOperationKind.employeeDeactivate => _employeeDeactivate(operation),
      PayrollOperationKind.advancePost => _advancePost(operation),
      PayrollOperationKind.advanceReversal => _reversal(operation),
      PayrollOperationKind.payrollRunApproval => _runApproval(operation),
      PayrollOperationKind.payrollRunReversal => _reversal(operation),
      PayrollOperationKind.payrollPaymentPost => _paymentPost(operation),
      PayrollOperationKind.payrollPaymentReversal => _reversal(operation),
    };

Map<String, dynamic> _seedFor(PayrollOperationKind kind) {
  final employeeRow = {
    ..._employeeJson(),
    if (kind == PayrollOperationKind.employeeDeactivate) 'version': 2,
  };
  return switch (kind) {
    PayrollOperationKind.employeeCreate => _cacheSnapshot(),
    PayrollOperationKind.employeeUpdate ||
    PayrollOperationKind.employeeDeactivate ||
    PayrollOperationKind.advancePost => _cacheSnapshot(
      employees: [employeeRow],
    ),
    PayrollOperationKind.advanceReversal ||
    PayrollOperationKind.payrollRunApproval => _cacheSnapshot(
      employees: [employeeRow],
      advances: [_advanceJson()],
    ),
    PayrollOperationKind.payrollRunReversal => _cacheSnapshot(
      employees: [employeeRow],
      advances: [_advanceJson()],
      runs: [_runJson()],
      runItems: [_runItemJson()],
      allocations: [_allocationJson()],
    ),
    PayrollOperationKind.payrollPaymentPost => _cacheSnapshot(
      employees: [employeeRow],
      runs: [_runJson()],
      runItems: [_runItemJson()],
    ),
    PayrollOperationKind.payrollPaymentReversal => _cacheSnapshot(
      employees: [employeeRow],
      runs: [_runJson()],
      runItems: [_runItemJson()],
      payments: [_paymentJson()],
      paymentItems: [_paymentItemJson()],
    ),
  };
}

Map<String, dynamic> _ackFor(
  PayrollOperationKind kind,
  Map<String, dynamic> request,
) => switch (kind) {
  PayrollOperationKind.employeeCreate => _employeeAck(request),
  PayrollOperationKind.employeeUpdate => _employeeAck(request, version: 2),
  PayrollOperationKind.employeeDeactivate => _employeeAck(
    request,
    version: 3,
    active: false,
  ),
  PayrollOperationKind.advancePost => _advanceAck(request),
  PayrollOperationKind.advanceReversal => _advanceReversalAck(request),
  PayrollOperationKind.payrollRunApproval => _runAck(request),
  PayrollOperationKind.payrollRunReversal => _runReversalAck(request),
  PayrollOperationKind.payrollPaymentPost => _paymentAck(request),
  PayrollOperationKind.payrollPaymentReversal => _paymentReversalAck(request),
};

Map<String, dynamic> _advanceAck(Map<String, dynamic> request) => {
  'advance': {
    'id': advance,
    'tenant_id': tenant,
    'branch_id': branch,
    'employee_id': employee,
    'document_kind': 'employee_advance',
    'reversal_of_id': null,
    'employee': {
      'id': employee,
      'name': 'Employee',
      'phone': null,
      'base_salary_minor': 100000,
    },
    'occurred_at': request['occurred_at'],
    'category': request['category'],
    'note': request['note'],
    'account_code': request['account_code'],
    'amount_minor': request['amount_minor'],
    'status': 'posted',
    'reason': null,
    'device_id': request['device_id'],
    'local_operation_id': request['local_operation_id'],
    'restore_generation': request['restore_generation'],
    'operation_created_at': request['operation_created_at'],
    'created_at': '2026-11-01T01:00:00.000Z',
    'updated_at': '2026-11-01T01:00:00.000Z',
  },
  'journal': {
    'id': 'journal',
    'branch_id': branch,
    'reference_type': 'employee_advance',
    'reference_id': advance,
    'reversal_of_id': null,
    'posted_at': request['occurred_at'],
    'lines': [
      {
        'account_code': '1250-EMPLOYEE-ADVANCES',
        'debit_minor': 25000,
        'credit_minor': 0,
        'employee_id': employee,
      },
      {
        'account_code': '1110-CASH',
        'debit_minor': 0,
        'credit_minor': 25000,
        'employee_id': null,
      },
    ],
  },
  'employee_balance_minor': 25000,
};

Map<String, dynamic> _advanceJson() => {
  'id': advance,
  'tenant_id': tenant,
  'branch_id': branch,
  'employee_id': employee,
  'document_kind': 'employee_advance',
  'reversal_of_id': null,
  'occurred_at': '2026-11-01T01:00:00.000Z',
  'category': 'advance',
  'note': 'Advance',
  'account_code': '1110-CASH',
  'amount_minor': 25000,
  'status': 'posted',
  'reason': null,
  'device_id': device,
  'local_operation_id': 'seed-advance',
  'restore_generation': 0,
  'operation_created_at': '2026-11-01T01:00:00.000Z',
  'created_at': '2026-11-01T01:00:00.000Z',
  'updated_at': '2026-11-01T01:00:00.000Z',
};

Map<String, dynamic> _advanceReversalAck(Map<String, dynamic> request) => {
  'advance': {
    ..._advanceJson(),
    'id': advanceReversal,
    'document_kind': 'employee_advance_reversal',
    'reversal_of_id': advance,
    'reason': request['reason'],
    'occurred_at': request['occurred_at'],
    'device_id': request['device_id'],
    'local_operation_id': request['local_operation_id'],
    'restore_generation': request['restore_generation'],
    'operation_created_at': request['operation_created_at'],
  },
  'original': {..._advanceJson(), 'status': 'reversed'},
  'journal': {
    'id': 'advance-reversal-journal',
    'branch_id': branch,
    'reference_type': 'employee_advance_reversal',
    'reference_id': advanceReversal,
    'reversal_of_id': 'journal',
    'posted_at': request['occurred_at'],
    'lines': <Object>[],
  },
  'employee_balance_minor': 0,
};

Map<String, dynamic> _runAck(
  Map<String, dynamic> request, {
  bool applyAdvance = true,
}) => {
  'run': {
    'id': run,
    'tenant_id': tenant,
    'branch_id': branch,
    'document_kind': 'payroll_run',
    'reversal_of_id': null,
    'period_month': request['period_month'],
    'selection_mode': request['selection_mode'],
    'occurred_at': '2026-11-30T00:00:00.000Z',
    'total_gross_minor': 100000,
    'total_applied_minor': applyAdvance ? 25000 : 0,
    'total_net_minor': applyAdvance ? 75000 : 100000,
    'status': 'approved',
    'reason': null,
    'device_id': request['device_id'],
    'local_operation_id': request['local_operation_id'],
    'restore_generation': request['restore_generation'],
    'operation_created_at': request['operation_created_at'],
    'created_at': '2026-11-30T00:00:00.000Z',
    'updated_at': '2026-11-30T00:00:00.000Z',
  },
  'items': [
    {
      'id': runItem,
      'employee': {
        'id': employee,
        'name': 'Employee',
        'phone': null,
        'base_salary_minor': 100000,
      },
      'gross_minor': 100000,
      'applied_advance_minor': applyAdvance ? 25000 : 0,
      'net_minor': applyAdvance ? 75000 : 100000,
    },
  ],
  'allocations': applyAdvance
      ? [
          {
            'id': 'allocation',
            'payroll_run_item_id': runItem,
            'employee_advance_id': advance,
            'employee_id': employee,
            'amount_minor': 25000,
          },
        ]
      : <Object>[],
  'totals': {
    'gross_minor': 100000,
    'applied_advance_minor': applyAdvance ? 25000 : 0,
    'net_minor': applyAdvance ? 75000 : 100000,
  },
  'journal': {
    'id': 'run-journal',
    'branch_id': branch,
    'reference_type': 'payroll_run',
    'reference_id': run,
    'reversal_of_id': null,
    'posted_at': '2026-11-30T00:00:00.000Z',
    'lines': <Object>[],
  },
};

Map<String, dynamic> _runJson() => {
  'id': run,
  'tenant_id': tenant,
  'branch_id': branch,
  'document_kind': 'payroll_run',
  'reversal_of_id': null,
  'period_month': '2026-11',
  'selection_mode': 'selected',
  'occurred_at': '2026-11-30T00:00:00.000Z',
  'total_gross_minor': 100000,
  'total_applied_minor': 25000,
  'total_net_minor': 75000,
  'status': 'approved',
  'reason': null,
  'device_id': device,
  'local_operation_id': 'seed-run',
  'restore_generation': 0,
  'operation_created_at': '2026-11-30T00:00:00.000Z',
  'created_at': '2026-11-30T00:00:00.000Z',
  'updated_at': '2026-11-30T00:00:00.000Z',
};

Map<String, dynamic> _runItemJson() => {
  'id': runItem,
  'tenant_id': tenant,
  'branch_id': branch,
  'payroll_run_id': run,
  'employee_id': employee,
  'employee_name_snapshot': 'Employee',
  'employee_phone_snapshot': null,
  'employee_base_salary_minor_snapshot': 100000,
  'gross_minor': 100000,
  'applied_advance_minor': 25000,
  'net_minor': 75000,
  'remaining_minor': 75000,
  'created_at': '2026-11-30T00:00:00.000Z',
};

Map<String, dynamic> _allocationJson() => {
  'id': 'allocation',
  'tenant_id': tenant,
  'branch_id': branch,
  'payroll_run_id': run,
  'payroll_run_item_id': runItem,
  'employee_advance_id': advance,
  'employee_id': employee,
  'amount_minor': 25000,
  'created_at': '2026-11-30T00:00:00.000Z',
};

Map<String, dynamic> _runReversalAck(Map<String, dynamic> request) => {
  'run': {
    ..._runJson(),
    'id': runReversal,
    'document_kind': 'payroll_run_reversal',
    'reversal_of_id': run,
    'status': 'posted',
    'reason': request['reason'],
    'occurred_at': request['occurred_at'],
    'device_id': request['device_id'],
    'local_operation_id': request['local_operation_id'],
    'restore_generation': request['restore_generation'],
    'operation_created_at': request['operation_created_at'],
  },
  'original': {..._runJson(), 'status': 'reversed'},
  'items': <Object>[],
  'allocations': <Object>[],
  'totals': {
    'gross_minor': 100000,
    'applied_advance_minor': 25000,
    'net_minor': 75000,
  },
  'journal': {
    'id': 'run-reversal-journal',
    'branch_id': branch,
    'reference_type': 'payroll_run_reversal',
    'reference_id': runReversal,
    'reversal_of_id': 'run-journal',
    'posted_at': request['occurred_at'],
    'lines': <Object>[],
  },
};

Map<String, dynamic> _paymentJson() => {
  'id': payment,
  'tenant_id': tenant,
  'branch_id': branch,
  'payroll_run_id': run,
  'document_kind': 'payroll_payment',
  'reversal_of_id': null,
  'occurred_at': '2026-11-30T00:00:00.000Z',
  'account_code': '1110-CASH',
  'total_minor': 75000,
  'status': 'posted',
  'reason': null,
  'device_id': device,
  'local_operation_id': 'seed-payment',
  'restore_generation': 0,
  'operation_created_at': '2026-11-30T00:00:00.000Z',
  'created_at': '2026-11-30T00:00:00.000Z',
  'updated_at': '2026-11-30T00:00:00.000Z',
};

Map<String, dynamic> _paymentItemJson() => {
  'id': 'payment-item',
  'tenant_id': tenant,
  'branch_id': branch,
  'payroll_payment_id': payment,
  'payroll_run_item_id': runItem,
  'employee_id': employee,
  'employee_name_snapshot': 'Employee',
  'employee_phone_snapshot': null,
  'amount_minor': 75000,
  'created_at': '2026-11-30T00:00:00.000Z',
};

Map<String, dynamic> _paymentAck(Map<String, dynamic> request) => {
  'payment': {
    ..._paymentJson(),
    'device_id': request['device_id'],
    'local_operation_id': request['local_operation_id'],
    'restore_generation': request['restore_generation'],
    'operation_created_at': request['operation_created_at'],
    'occurred_at': request['occurred_at'],
    'account_code': request['account_code'],
  },
  'items': [
    {
      'id': 'payment-item',
      'payroll_run_item_id': runItem,
      'employee': {'id': employee, 'name': 'Employee', 'phone': null},
      'amount_minor': 75000,
    },
  ],
  'remaining': [
    {'payroll_run_item_id': runItem, 'remaining_minor': 0},
  ],
  'journal': {
    'id': 'payment-journal',
    'branch_id': branch,
    'reference_type': 'payroll_payment',
    'reference_id': payment,
    'reversal_of_id': null,
    'posted_at': request['occurred_at'],
    'lines': <Object>[],
  },
};

Map<String, dynamic> _paymentReversalAck(Map<String, dynamic> request) => {
  'payment': {
    ..._paymentJson(),
    'id': paymentReversal,
    'document_kind': 'payroll_payment_reversal',
    'reversal_of_id': payment,
    'status': 'posted',
    'reason': request['reason'],
    'occurred_at': request['occurred_at'],
    'device_id': request['device_id'],
    'local_operation_id': request['local_operation_id'],
    'restore_generation': request['restore_generation'],
    'operation_created_at': request['operation_created_at'],
  },
  'original': {..._paymentJson(), 'status': 'reversed'},
  'items': <Object>[],
  'remaining': [
    {'payroll_run_item_id': runItem, 'remaining_minor': 75000},
  ],
  'journal': {
    'id': 'payment-reversal-journal',
    'branch_id': branch,
    'reference_type': 'payroll_payment_reversal',
    'reference_id': paymentReversal,
    'reversal_of_id': 'payment-journal',
    'posted_at': request['occurred_at'],
    'lines': <Object>[],
  },
};

JsonResponse _response(Map<String, dynamic> value) =>
    JsonResponse(statusCode: 200, body: jsonEncode(value));

typedef _Handler =
    Future<JsonResponse> Function(Uri uri, String method, String? body);

class _Transport implements JsonTransport {
  _Transport(this.handler);
  final _Handler handler;
  final List<String> paths = [];
  final List<String> methods = [];
  final List<String> bodies = [];

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String>? headers,
    String? body,
  }) async {
    paths.add(uri.path);
    methods.add(method);
    if (body != null) bodies.add(body);
    return handler(uri, method, body);
  }
}
