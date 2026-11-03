import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/accounting/chart_accounts_api.dart';
import 'package:nizami/src/features/payroll/payroll_cache.dart';
import 'package:nizami/src/features/payroll/payroll_models.dart';
import 'package:nizami/src/features/payroll/payroll_api.dart';
import 'package:nizami/src/features/payroll/payroll_run_page.dart';
import 'package:nizami/src/features/sync/payroll_outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tenant = 'tenant-ui';
const _branch = 'branch-ui';

typedef _PreviewLoader =
    Future<PayrollApprovalPreview> Function({
      required String branchId,
      required String periodMonth,
      required String selectionMode,
      required List<String> employeeIds,
      required int restoreGeneration,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in const [1440.0, 700.0, 390.0]) {
    testWidgets('payroll run and payment fit ${width.toInt()}', (tester) async {
      await _setSurface(tester, width);
      await tester.pumpWidget(_app(_page(roleCode: 'owner')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payroll-run-selection')), findsOneWidget);
      expect(
        find.byKey(const Key('payroll-run-item-run-item-1')),
        findsOneWidget,
      );
      expect(find.text('250,000 ر.ي'), findsWidgets);
      expect(
        find.byKey(const Key('payroll-payment-selection')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('payroll-run-page')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is SingleChildScrollView &&
                widget.scrollDirection == Axis.horizontal,
          ),
        ),
        findsNothing,
      );
      await _expectReachable(tester, find.byKey(const Key('payroll-approve')));
      await _expectReachable(tester, find.byKey(const Key('payroll-pay')));
      await _expectReachable(
        tester,
        find.byKey(const Key('payroll-payment-date')),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('selected approval needs one active employee and queues once', (
    tester,
  ) async {
    await _setSurface(tester, 700);
    final queue = PayrollOutbox(_tenant, _branch);
    await tester.pumpWidget(
      _app(_page(roleCode: 'owner', outbox: queue, envelope: _directoryOnly())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('payroll-mode-selected')));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('payroll-approve')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('payroll-select-employee-1')));
    await tester.pump();
    final approve = find.byKey(const Key('payroll-approve'));
    await tester.ensureVisible(approve);
    await tester.pump();
    await tester.tap(approve);
    await tester.tap(approve);
    await tester.pumpAndSettle();

    final entries = await queue.list();
    expect(entries, hasLength(1));
    expect(entries.single.kind, PayrollOperationKind.payrollRunApproval);
    expect(entries.single.request['selection_mode'], 'selected');
    expect(entries.single.request['employee_ids'], ['employee-1']);
    expect(entries.single.request['restore_generation'], 7);
    expect(entries.single.request['preview_version'], 1);
    expect(
      entries.single.request['preview_signature'],
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(find.text('محفوظ محليًا بانتظار الإرسال'), findsOneWidget);
    expect(find.text('معاينة مؤكدة من الخادم'), findsWidgets);
    expect(find.text('300,000 ر.ي'), findsWidgets);
    expect(find.text('50,000 ر.ي'), findsWidgets);
    expect(find.text('250,000 ر.ي'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _app(_page(roleCode: 'owner', outbox: queue, envelope: _directoryOnly())),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('payroll-approve')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('needs-review approval retains its immutable operation', (
    tester,
  ) async {
    await _setSurface(tester, 700);
    final queue = PayrollOutbox(_tenant, _branch);
    await _seedApproval(queue, state: PayrollOutboxState.needsReview);
    await tester.pumpWidget(
      _app(_page(roleCode: 'owner', outbox: queue, envelope: _directoryOnly())),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('يحتاج مراجعة'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('payroll-approve')))
          .onPressed,
      isNull,
    );
    expect(await queue.count(), 1);
  });

  testWidgets('payroll.read can inspect but cannot approve or pay', (
    tester,
  ) async {
    await _setSurface(tester, 1440);
    await tester.pumpWidget(
      _app(_page(roleCode: 'cashier', permissions: const ['payroll.read'])),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('payroll-approve')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('payroll-pay')), findsNothing);
    expect(
      find.byKey(const Key('payroll-run-item-run-item-1')),
      findsOneWidget,
    );
  });

  testWidgets('partial payment validates integer remaining and queues once', (
    tester,
  ) async {
    await _setSurface(tester, 700);
    final queue = PayrollOutbox(_tenant, _branch);
    await tester.pumpWidget(_app(_page(roleCode: 'owner', outbox: queue)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('payroll-pay-select-run-item-1')));
    await tester.pump();
    final amount = find.byKey(const Key('payroll-pay-amount-run-item-1'));
    await tester.ensureVisible(amount);
    await tester.pump();
    await tester.enterText(amount, '75000');
    final pay = find.byKey(const Key('payroll-pay'));
    await tester.ensureVisible(pay);
    await tester.pump();
    await tester.tap(pay);
    await tester.tap(pay);
    await tester.pumpAndSettle();

    final entries = await queue.list();
    expect(entries, hasLength(1));
    expect(entries.single.kind, PayrollOperationKind.payrollPaymentPost);
    expect((entries.single.request['items'] as List).single, {
      'payroll_run_item_id': 'run-item-1',
      'amount_minor': 75000,
    });
    expect(entries.single.request['restore_generation'], 7);
    expect(entries.single.request['account_code'], '1130-WALLET');
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('payroll-pay')))
          .onPressed,
      isNull,
    );

    final preferences = await SharedPreferences.getInstance();
    final key = 'ninesoft.payroll.outbox.v1.$_tenant.$_branch';
    final rows = jsonDecode(preferences.getString(key)!) as List<dynamic>;
    (rows.single as Map<String, dynamic>)['state'] = 'needs_review';
    (rows.single as Map<String, dynamic>)['rejection_status'] = 422;
    (rows.single as Map<String, dynamic>)['rejection_message'] = 'overpaid';
    await preferences.setString(key, jsonEncode(rows));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(_page(roleCode: 'owner', outbox: queue)));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('payroll-pay')))
          .onPressed,
      isNull,
    );
    expect(await queue.count(), 1);
  });

  testWidgets('sync notification replaces frozen input with canonical cache', (
    tester,
  ) async {
    await _setSurface(tester, 700);
    final changes = StreamController<Set<String>>.broadcast();
    addTearDown(changes.close);
    final cache = PayrollCache(_tenant, _branch);
    await cache.replaceSnapshot(_directoryOnly().toJson());
    await tester.pumpWidget(
      _app(
        _page(
          roleCode: 'owner',
          envelope: _directoryOnly(),
          syncChanges: changes.stream,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payroll-run-item-run-item-1')), findsNothing);

    await cache.replaceSnapshot(_postedEnvelope().toJson());
    changes.add({'payroll_run'});
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('payroll-run-item-run-item-1')),
      findsOneWidget,
    );
    expect(find.text('المسير مرحّل'), findsOneWidget);
  });

  testWidgets('employee advance delta invalidates preview until refreshed', (
    tester,
  ) async {
    await _setSurface(tester, 700);
    final changes = StreamController<Set<String>>.broadcast();
    addTearDown(changes.close);
    final queue = PayrollOutbox(_tenant, _branch);
    final cache = PayrollCache(_tenant, _branch);
    await cache.replaceSnapshot(_directoryOnly().toJson());
    final refreshed = Completer<PayrollApprovalPreview>();
    var calls = 0;
    Future<PayrollApprovalPreview> loader({
      required String branchId,
      required String periodMonth,
      required String selectionMode,
      required List<String> employeeIds,
      required int restoreGeneration,
    }) {
      calls++;
      if (calls == 1) {
        return Future.value(
          _preview(
            signature:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            gross: 300000,
          ),
        );
      }
      return refreshed.future;
    }

    await tester.pumpWidget(
      _app(
        _page(
          roleCode: 'owner',
          outbox: queue,
          envelope: _directoryOnly(),
          syncChanges: changes.stream,
          previewLoader: loader,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('payroll-approve')))
          .onPressed,
      isNotNull,
    );

    changes.add({'employee_advance'});
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('payroll-approve')))
          .onPressed,
      isNull,
    );
    refreshed.complete(
      _preview(
        signature:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        gross: 310000,
        applied: 60000,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('310,000 ر.ي'), findsWidgets);

    final approve = find.byKey(const Key('payroll-approve'));
    await tester.ensureVisible(approve);
    await tester.tap(approve);
    await tester.pumpAndSettle();
    expect(
      (await queue.list()).single.request['preview_signature'],
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
  });

  testWidgets(
    'live operation state moves queued to review to canonical posted',
    (tester) async {
      await _setSurface(tester, 700);
      final changes = StreamController<Set<String>>.broadcast();
      addTearDown(changes.close);
      final queue = PayrollOutbox(_tenant, _branch);
      final cache = PayrollCache(_tenant, _branch);
      await _seedApproval(queue, state: PayrollOutboxState.queued);
      await cache.replaceSnapshot(_directoryOnly().toJson());
      await tester.pumpWidget(
        _app(
          _page(
            roleCode: 'owner',
            outbox: queue,
            envelope: _directoryOnly(),
            syncChanges: changes.stream,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('محفوظ محليًا بانتظار الإرسال'), findsOneWidget);

      final preferences = await SharedPreferences.getInstance();
      final key = 'ninesoft.payroll.outbox.v1.$_tenant.$_branch';
      final rows = jsonDecode(preferences.getString(key)!) as List<dynamic>;
      (rows.single as Map<String, dynamic>)['state'] = 'needs_review';
      (rows.single as Map<String, dynamic>)['rejection_status'] = 422;
      (rows.single as Map<String, dynamic>)['rejection_message'] = 'locked';
      await preferences.setString(key, jsonEncode(rows));
      changes.add({'payroll_needs_review'});
      await tester.pumpAndSettle();
      expect(find.textContaining('يحتاج مراجعة'), findsOneWidget);

      await cache.replaceSnapshot(_postedEnvelope().toJson());
      await preferences.setString(key, '[]');
      changes.add({'payroll_run'});
      await tester.pumpAndSettle();
      expect(find.textContaining('يحتاج مراجعة'), findsNothing);
      expect(
        find.byKey(const Key('payroll-run-item-run-item-1')),
        findsOneWidget,
      );
      expect(find.text('المسير مرحّل'), findsOneWidget);
    },
  );

  testWidgets(
    'later unclaimed subset and multiple canonical runs stay usable',
    (tester) async {
      await _setSurface(tester, 700);
      await tester.pumpWidget(
        _app(_page(roleCode: 'owner', envelope: _multipleRunsEnvelope())),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payroll-run-picker')), findsOneWidget);
      expect(
        find.byKey(const Key('payroll-run-item-employee-2')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('payroll-mode-selected')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('payroll-select-employee-2')));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('payroll-approve')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('payment exposes canonical account and occurrence-date pickers', (
    tester,
  ) async {
    await _setSurface(tester, 700);
    await tester.pumpWidget(_app(_page(roleCode: 'owner')));
    await tester.pumpAndSettle();

    expect(find.textContaining('محفظة الرواتب'), findsOneWidget);
    expect(find.byKey(const Key('payroll-payment-date')), findsOneWidget);
    expect(find.text('أحمد الموظف'), findsWidgets);
  });
}

Widget _page({
  required String roleCode,
  List<String> permissions = const [
    'payroll.read',
    'payroll.approve',
    'payroll.pay',
  ],
  PayrollOutbox? outbox,
  PayrollEnvelope? envelope,
  Stream<Set<String>>? syncChanges,
  _PreviewLoader? previewLoader,
}) => PayrollRunPage(
  token: 'token',
  tenantId: _tenant,
  tenantName: 'مؤسسة الاختبار',
  branchIds: const [_branch],
  roleCode: roleCode,
  permissions: permissions,
  initialEnvelope: envelope ?? _postedEnvelope(),
  outbox: outbox,
  syncChanges: syncChanges,
  accountOptions: const [
    ChartAccount(
      id: 'wallet-account',
      code: '1130-WALLET',
      nameAr: 'محفظة الرواتب',
      type: 'asset',
      normalBalance: 'debit',
      balanceMinor: 0,
      allowPosting: true,
      active: true,
      isCashEquivalent: true,
    ),
  ],
  restoreGeneration: 7,
  initialPeriodMonth: '2026-10',
  previewLoader: previewLoader ?? _previewLoader,
);

Future<PayrollApprovalPreview> _previewLoader({
  required String branchId,
  required String periodMonth,
  required String selectionMode,
  required List<String> employeeIds,
  required int restoreGeneration,
}) async {
  final ids = selectionMode == 'all' ? ['employee-1'] : employeeIds;
  return PayrollApprovalPreview.fromJson({
    'preview_version': 1,
    'preview_signature':
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'restore_generation': restoreGeneration,
    'branch_id': branchId,
    'period_month': periodMonth,
    'selection_mode': selectionMode,
    'employee_ids': employeeIds,
    'confirmed_at': '2026-11-01T08:00:00.000Z',
    'items': [
      for (final id in ids)
        {
          'employee_id': id,
          'employee_name': 'Server employee',
          'gross_minor': 300000,
          'applied_advance_minor': 50000,
          'net_minor': 250000,
        },
    ],
    'totals': {
      'gross_minor': 300000 * ids.length,
      'applied_advance_minor': 50000 * ids.length,
      'net_minor': 250000 * ids.length,
    },
  });
}

PayrollApprovalPreview _preview({
  required String signature,
  required int gross,
  int applied = 50000,
}) => PayrollApprovalPreview.fromJson({
  'preview_version': 1,
  'preview_signature': signature,
  'restore_generation': 7,
  'branch_id': _branch,
  'period_month': '2026-10',
  'selection_mode': 'all',
  'employee_ids': const <String>[],
  'confirmed_at': '2026-11-01T08:00:00.000Z',
  'items': [
    {
      'employee_id': 'employee-1',
      'employee_name': 'Server employee',
      'gross_minor': gross,
      'applied_advance_minor': applied,
      'net_minor': gross - applied,
    },
  ],
  'totals': {
    'gross_minor': gross,
    'applied_advance_minor': applied,
    'net_minor': gross - applied,
  },
});

Widget _app(Widget child) => MaterialApp(
  home: Directionality(textDirection: TextDirection.rtl, child: child),
);

Future<void> _setSurface(WidgetTester tester, double width) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1100);
  addTearDown(tester.view.reset);
}

Future<void> _expectReachable(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pump();
  final rect = tester.getRect(finder);
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(size.width));
  expect(rect.bottom, lessThanOrEqualTo(size.height));
  expect(rect.height, greaterThanOrEqualTo(44));
}

PayrollEnvelope _directoryOnly() => PayrollEnvelope(
  employees: [
    _employee(active: true),
    _employee(id: 'employee-2', active: false),
  ],
  employeeAdvances: const [],
  payrollRuns: const [],
  payrollRunItems: const [],
  payrollAdvanceAllocations: const [],
  payrollPeriodClaims: const [],
  payrollPayments: const [],
  payrollPaymentItems: const [],
);

PayrollEnvelope _postedEnvelope() => PayrollEnvelope(
  employees: [
    _employee(active: true),
    _employee(id: 'employee-2', active: false),
  ],
  employeeAdvances: const [],
  payrollRuns: [
    PayrollRun.fromJson({
      'tenant_id': _tenant,
      'id': 'run-1',
      'branch_id': _branch,
      'document_kind': 'payroll_run',
      'period_month': '2026-10',
      'selection_mode': 'all',
      'occurred_at': '2026-10-31T20:59:59.000Z',
      'status': 'approved',
      'device_id': 'device-1',
      'local_operation_id': 'posted-run-operation',
      'operation_created_at': '2026-10-31T18:00:00.000Z',
      'total_gross_minor': 300000,
      'total_applied_minor': 50000,
      'total_net_minor': 250000,
      'restore_generation': 0,
    }),
  ],
  payrollRunItems: [
    PayrollRunItem.fromJson({
      'tenant_id': _tenant,
      'id': 'run-item-1',
      'branch_id': _branch,
      'payroll_run_id': 'run-1',
      'employee_id': 'employee-1',
      'employee_name_snapshot': 'أحمد الموظف',
      'employee_phone_snapshot': '777123456',
      'employee_base_salary_minor_snapshot': 300000,
      'gross_minor': 300000,
      'applied_advance_minor': 50000,
      'net_minor': 250000,
      'remaining_minor': 200000,
    }),
  ],
  payrollAdvanceAllocations: const [],
  payrollPeriodClaims: [
    PayrollPeriodClaim.fromJson({
      'tenant_id': _tenant,
      'id': 'claim-posted-1',
      'branch_id': _branch,
      'employee_id': 'employee-1',
      'period_month': '2026-10',
      'payroll_run_id': 'run-1',
      'payroll_run_item_id': 'run-item-1',
    }),
  ],
  payrollPayments: const [],
  payrollPaymentItems: const [],
);

Employee _employee({String id = 'employee-1', required bool active}) =>
    Employee.fromJson({
      'tenant_id': _tenant,
      'id': id,
      'branch_id': _branch,
      'name': id == 'employee-1' ? 'أحمد الموظف' : 'موظف سابق',
      'phone': '777123456',
      'base_salary_minor': 300000,
      'start_date': '2026-01-01',
      'notes': null,
      'active': active,
      'version': 1,
    });

Future<void> _seedApproval(
  PayrollOutbox queue, {
  required PayrollOutboxState state,
}) async {
  final request = await PayrollApi(token: 'token').preparePayrollRun(
    branchId: _branch,
    periodMonth: '2026-10',
    selectionMode: 'selected',
    employeeIds: const ['employee-1'],
    restoreGeneration: 7,
  );
  await queue.enqueue(
    kind: PayrollOperationKind.payrollRunApproval,
    aggregateId: 'approval-seed',
    request: request,
  );
  if (state == PayrollOutboxState.queued) return;
  final preferences = await SharedPreferences.getInstance();
  final key = 'ninesoft.payroll.outbox.v1.$_tenant.$_branch';
  final rows = jsonDecode(preferences.getString(key)!) as List<dynamic>;
  (rows.single as Map<String, dynamic>)['state'] = 'needs_review';
  (rows.single as Map<String, dynamic>)['rejection_status'] = 422;
  (rows.single as Map<String, dynamic>)['rejection_message'] = 'review';
  await preferences.setString(key, jsonEncode(rows));
}

PayrollEnvelope _multipleRunsEnvelope() {
  final first = _postedEnvelope();
  final run2 = PayrollRun.fromJson({
    ...first.payrollRuns.single.toJson(),
    'id': 'run-2',
    'local_operation_id': 'posted-run-operation-2',
    'total_gross_minor': 100000,
    'total_applied_minor': 0,
    'total_net_minor': 100000,
  });
  final item2 = PayrollRunItem.fromJson({
    ...first.payrollRunItems.single.toJson(),
    'id': 'run-item-2',
    'payroll_run_id': 'run-2',
    'employee_id': 'employee-2',
    'employee_name_snapshot': 'موظف ثانٍ',
    'employee_base_salary_minor_snapshot': 100000,
    'gross_minor': 100000,
    'applied_advance_minor': 0,
    'net_minor': 100000,
    'remaining_minor': 100000,
  });
  return PayrollEnvelope(
    employees: [
      _employee(active: true),
      _employee(id: 'employee-2', active: true),
    ],
    employeeAdvances: const [],
    payrollRuns: [...first.payrollRuns, run2],
    payrollRunItems: [...first.payrollRunItems, item2],
    payrollAdvanceAllocations: const [],
    payrollPeriodClaims: [
      PayrollPeriodClaim.fromJson({
        'tenant_id': _tenant,
        'id': 'claim-1',
        'branch_id': _branch,
        'employee_id': 'employee-1',
        'period_month': '2026-10',
        'payroll_run_id': 'run-1',
        'payroll_run_item_id': 'run-item-1',
      }),
    ],
    payrollPayments: const [],
    payrollPaymentItems: const [],
  );
}
