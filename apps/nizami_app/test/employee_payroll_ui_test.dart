import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/accounting/chart_accounts_api.dart';
import 'package:nizami/src/features/payroll/employee_ledger_page.dart';
import 'package:nizami/src/features/payroll/employee_payroll_page.dart';
import 'package:nizami/src/features/payroll/payroll_models.dart';
import 'package:nizami/src/features/payroll/payroll_cache.dart';
import 'package:nizami/src/features/payroll/payroll_api.dart';
import 'package:nizami/src/features/navigation/ninesoft_workspace_shell.dart';
import 'package:nizami/src/features/sync/payroll_outbox.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tenant = 'tenant-ui';
const _branch = 'branch-ui';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in const [1440.0, 700.0, 390.0]) {
    testWidgets('employee directory fits ${width.toInt()} without overflow', (
      tester,
    ) async {
      await _setSurface(tester, width);
      await tester.pumpWidget(_app(_page(roleCode: 'owner')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payroll-module')), findsOneWidget);
      if (width > 700) {
        expect(find.byKey(const Key('payroll-employee-table')), findsOneWidget);
      } else {
        expect(
          find.byKey(const Key('payroll-employee-card-employee-1')),
          findsOneWidget,
        );
      }
      expect(find.text('9,007,199,254,740,991 ر.ي'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('payroll-module')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is SingleChildScrollView &&
                widget.scrollDirection == Axis.horizontal,
          ),
        ),
        findsNothing,
      );
      await _expectReachable(tester, find.byKey(const Key('payroll-open-run')));
      await _expectReachable(
        tester,
        find.byKey(const Key('payroll-statement-employee-1')),
      );
      await _expectReachable(
        tester,
        find.byKey(const Key('payroll-advance-employee-1')),
      );
      await _expectReachable(
        tester,
        find.byKey(const Key('payroll-add-employee')),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('real shell open payroll tab refreshes accounts after restore', (
    tester,
  ) async {
    await _setSurface(tester, 1440);
    await PayrollCache(
      _tenant,
      _branch,
    ).replaceSnapshot(_payableEnvelope().toJson());
    final changes = StreamController<Set<String>>.broadcast();
    addTearDown(changes.close);
    final transport = _SettlementTransport();
    await tester.pumpWidget(
      MaterialApp(
        home: NineSoftWorkspaceShell(
          themeMode: ThemeMode.light,
          onToggleTheme: () {},
          displayName: 'Payroll tester',
          token: 'token',
          tenantName: 'Tenant',
          tenantId: _tenant,
          roleCode: 'owner',
          permissions: const [
            'payroll.read',
            'payroll.manage',
            'payroll.advance',
            'payroll.approve',
            'payroll.pay',
          ],
          branchIds: const [_branch],
          onLogout: () {},
          payrollApi: PayrollApi(
            token: 'token',
            transport: transport,
            baseUrl: 'https://example.test/api/v1',
          ),
          payrollSyncChanges: changes.stream,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final tile = find.text('الموظفون والرواتب').first;
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('payroll-open-run')));
    await tester.pumpAndSettle();
    DropdownButton<String> paymentAccount() => tester.widget(
      find
          .descendant(
            of: find.byKey(const Key('payroll-payment-account')),
            matching: find.byType(DropdownButton<String>),
          )
          .first,
    );
    expect(paymentAccount().items!.single.value, '1110-LEGACY');

    transport.restored = true;
    changes.add({'snapshot_restore'});
    await tester.pumpAndSettle();

    expect(paymentAccount().items!.single.value, '1110-RESTORED');
  });

  for (final width in const [1440.0, 700.0, 390.0]) {
    testWidgets('real workspace shell exercises payroll at ${width.toInt()}', (
      tester,
    ) async {
      await _setSurface(tester, width);
      await PayrollCache(
        _tenant,
        _branch,
      ).replaceSnapshot(_envelope().toJson());
      await tester.pumpWidget(
        MaterialApp(
          home: NineSoftWorkspaceShell(
            themeMode: ThemeMode.light,
            onToggleTheme: () {},
            displayName: 'مختبر الرواتب',
            token: 'token',
            tenantName: 'مؤسسة الاختبار',
            tenantId: _tenant,
            roleCode: 'owner',
            permissions: const [
              'payroll.read',
              'payroll.manage',
              'payroll.advance',
              'payroll.approve',
              'payroll.pay',
            ],
            branchIds: const [_branch],
            onLogout: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      if (width < 900) {
        await tester.tap(find.text('ابدأ'));
        await tester.pumpAndSettle();
      }
      final tile = find.text('الموظفون والرواتب').first;
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      for (
        var index = 0;
        index < 20 &&
            find.byKey(const Key('payroll-module')).evaluate().isEmpty;
        index++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const Key('payroll-module')), findsOneWidget);
      await tester.pumpAndSettle();
      await _expectReachable(
        tester,
        find.byKey(const Key('payroll-statement-employee-1')),
      );
      await tester.tap(find.byKey(const Key('payroll-statement-employee-1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('payroll-ledger-employee-1')),
        findsOneWidget,
      );
      Navigator.of(
        tester.element(find.byKey(const Key('payroll-ledger-employee-1'))),
      ).pop();
      await tester.pumpAndSettle();

      await _expectReachable(
        tester,
        find.byKey(const Key('payroll-advance-employee-1')),
      );
      await tester.tap(find.byKey(const Key('payroll-advance-employee-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payroll-advance-form')), findsOneWidget);
      Navigator.of(
        tester.element(find.byKey(const Key('payroll-advance-form'))),
      ).pop();
      await tester.pumpAndSettle();

      await _expectReachable(tester, find.byKey(const Key('payroll-open-run')));
      await tester.tap(find.byKey(const Key('payroll-open-run')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('payroll-run-page')), findsOneWidget);
      Navigator.of(
        tester.element(find.byKey(const Key('payroll-run-page'))),
      ).pop();
      await tester.pumpAndSettle();

      await _expectReachable(
        tester,
        find.byKey(const Key('payroll-add-employee')),
      );
      await tester.tap(find.byKey(const Key('payroll-add-employee')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('statement navigation keeps the canonical employee snapshot', (
    tester,
  ) async {
    await _setSurface(tester, 700);
    await tester.pumpWidget(_app(_page(roleCode: 'cashier')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('payroll-statement-employee-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('payroll-ledger-employee-1')), findsOneWidget);
    expect(
      find.textContaining('أحمد الموظف صاحب الاسم العربي الطويل'),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('directory consumes canonical employee cache changes', (
    tester,
  ) async {
    await _setSurface(tester, 700);
    final changes = StreamController<Set<String>>.broadcast();
    addTearDown(changes.close);
    final cache = PayrollCache(_tenant, _branch);
    final updated = _envelope().toJson();
    (updated['employees'] as List<dynamic>).first['name'] =
        'اسم مؤكد بعد المزامنة';
    await cache.replaceSnapshot(updated);
    await tester.pumpWidget(
      _app(
        EmployeePayrollPage(
          token: 'token',
          tenantId: _tenant,
          tenantName: 'مؤسسة الاختبار',
          branchIds: const [_branch],
          roleCode: 'cashier',
          permissions: const ['payroll.read'],
          initialEnvelope: _envelope(),
          syncChanges: changes.stream,
          accountOptions: const [],
          restoreGeneration: 7,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('أحمد الموظف صاحب الاسم'), findsWidgets);

    changes.add({'employee'});
    await tester.pumpAndSettle();
    expect(find.text('اسم مؤكد بعد المزامنة'), findsOneWidget);
  });

  testWidgets('initial production open reads durable cache before rendering', (
    tester,
  ) async {
    await _setSurface(tester, 700);
    final cached = _envelope().toJson();
    (cached['employees'] as List<dynamic>).first['name'] =
        'Cached employee on first open';
    await PayrollCache(_tenant, _branch).replaceSnapshot(cached);
    await tester.pumpWidget(
      _app(
        const EmployeePayrollPage(
          token: 'token',
          tenantId: _tenant,
          tenantName: 'Tenant',
          branchIds: [_branch],
          roleCode: 'cashier',
          permissions: ['payroll.read'],
          accountOptions: [],
          restoreGeneration: 7,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cached employee on first open'), findsOneWidget);
    expect(find.textContaining('No employees'), findsNothing);
  });

  testWidgets('advance double tap enqueues one immutable integer request', (
    tester,
  ) async {
    await _setSurface(tester, 700);
    final queue = PayrollOutbox(_tenant, _branch);
    await tester.pumpWidget(
      _app(
        _page(
          roleCode: 'cashier',
          permissions: const ['payroll.read', 'payroll.advance'],
          outbox: queue,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('payroll-advance-employee-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payroll-advance-form')), findsOneWidget);
    expect(find.textContaining('محفظة الرواتب'), findsOneWidget);
    expect(find.byKey(const Key('payroll-advance-date')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('payroll-advance-amount')),
      '125000',
    );
    await tester.enterText(
      find.byKey(const Key('payroll-advance-note')),
      'سلفة طارئة موثقة',
    );
    final submit = find.byKey(const Key('payroll-advance-submit'));
    await tester.tap(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    final entries = await queue.list();
    expect(entries, hasLength(1));
    expect(entries.single.kind, PayrollOperationKind.advancePost);
    expect(entries.single.request['amount_minor'], 125000);
    expect(entries.single.request['restore_generation'], 7);
    expect(entries.single.request['account_code'], '1130-WALLET');
    expect(entries.single.request['note'], 'سلفة طارئة موثقة');
    expect(find.text('محفوظ محليًا بانتظار الإرسال'), findsOneWidget);
  });

  testWidgets(
    'advance intent keeps one identity through queue review ack and restart',
    (tester) async {
      await _setSurface(tester, 700);
      final queue = PayrollOutbox(_tenant, _branch);
      Widget page({PayrollEnvelope? envelope}) => _app(
        _page(
          roleCode: 'cashier',
          permissions: const ['payroll.read', 'payroll.advance'],
          outbox: queue,
          envelope: envelope,
        ),
      );

      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('payroll-advance-employee-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('payroll-advance-amount')),
        '125000',
      );
      await tester.enterText(
        find.byKey(const Key('payroll-advance-note')),
        'Durable advance intent',
      );
      await tester.tap(find.byKey(const Key('payroll-advance-submit')));
      await tester.pumpAndSettle();
      final operation = (await queue.list()).single;

      await tester.tap(find.byKey(const Key('payroll-advance-employee-1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('payroll-advance-intent-${operation.operationId}')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('payroll-advance-submit')), findsNothing);
      await tester.tap(find.byKey(const Key('payroll-advance-new-intent')));
      await tester.pump();
      expect(find.byKey(const Key('payroll-advance-submit')), findsOneWidget);
      Navigator.of(
        tester.element(find.byKey(const Key('payroll-advance-form'))),
      ).pop();
      await tester.pumpAndSettle();

      final preferences = await SharedPreferences.getInstance();
      final outboxKey = 'ninesoft.payroll.outbox.v1.$_tenant.$_branch';
      final rows =
          jsonDecode(preferences.getString(outboxKey)!) as List<dynamic>;
      (rows.single as Map<String, dynamic>)['state'] = 'needs_review';
      (rows.single as Map<String, dynamic>)['rejection_status'] = 422;
      (rows.single as Map<String, dynamic>)['rejection_message'] = 'review';
      await preferences.setString(outboxKey, jsonEncode(rows));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('payroll-advance-employee-1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('payroll-advance-intent-${operation.operationId}')),
        findsOneWidget,
      );
      expect(find.textContaining('review'), findsWidgets);
      Navigator.of(
        tester.element(find.byKey(const Key('payroll-advance-form'))),
      ).pop();
      await tester.pumpAndSettle();

      final posted = _envelopeWithAdvance(operation.request);
      await PayrollCache(_tenant, _branch).replaceSnapshot(posted.toJson());
      await preferences.setString(outboxKey, '[]');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(page(envelope: posted));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('payroll-advance-employee-1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('payroll-advance-intent-${operation.operationId}')),
        findsOneWidget,
      );
      expect(find.textContaining('posted'), findsOneWidget);

      await tester.tap(find.byKey(const Key('payroll-advance-new-intent')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('payroll-advance-amount')),
        '50000',
      );
      await tester.enterText(
        find.byKey(const Key('payroll-advance-note')),
        'Explicit new intent',
      );
      await tester.tap(find.byKey(const Key('payroll-advance-submit')));
      await tester.pumpAndSettle();
      final replacement = (await queue.list()).single;
      expect(replacement.operationId, isNot(operation.operationId));
      expect(replacement.request['amount_minor'], 50000);
    },
  );

  testWidgets('advance intent is durable while enqueue is still awaiting', (
    tester,
  ) async {
    await _setSurface(tester, 700);
    final queue = _DelayedPayrollOutbox(_tenant, _branch);
    await tester.pumpWidget(
      _app(
        _page(
          roleCode: 'cashier',
          permissions: const ['payroll.read', 'payroll.advance'],
          outbox: queue,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('payroll-advance-employee-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('payroll-advance-amount')),
      '25000',
    );
    await tester.enterText(
      find.byKey(const Key('payroll-advance-note')),
      'Awaiting enqueue',
    );
    await tester.tap(find.byKey(const Key('payroll-advance-submit')));
    await queue.started.future;
    final preferences = await SharedPreferences.getInstance();
    final intentKey = preferences.getKeys().singleWhere(
      (key) => key.startsWith('ninesoft.payroll.advance-intent.v1.'),
    );
    final intent =
        jsonDecode(preferences.getString(intentKey)!) as Map<String, dynamic>;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      _app(
        _page(
          roleCode: 'cashier',
          permissions: const ['payroll.read', 'payroll.advance'],
          outbox: queue,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('payroll-advance-employee-1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(Key('payroll-advance-intent-${intent['local_operation_id']}')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('payroll-advance-retry-intent')),
      findsOneWidget,
    );

    queue.release.complete();
    await tester.pumpAndSettle();
    expect((await queue.list()).single.request, intent);
  });

  testWidgets('employee ledger sorts chronology and compensates reversals', (
    tester,
  ) async {
    await _setSurface(tester, 700);
    final envelope = _ledgerEnvelope();
    await tester.pumpWidget(
      _app(
        EmployeeLedgerPage(
          employee: envelope.employees.single,
          envelope: envelope,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final runReversal = find.byKey(
      const Key('payroll-ledger-row-run-reversal:run-item-1'),
    );
    final paymentReversal = find.byKey(
      const Key('payroll-ledger-row-payment-item-reversal'),
    );
    expect(
      find.descendant(of: runReversal, matching: find.text('مدين 250,000 ر.ي')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: paymentReversal,
        matching: find.text('دائن 50,000 ر.ي'),
      ),
      findsOneWidget,
    );
    expect(find.text('التصنيف: advance'), findsOneWidget);
    expect(find.text('الحساب: 1130-WALLET'), findsWidgets);
    expect(find.text('الملاحظة: سلفة موثقة'), findsOneWidget);
    expect(
      tester.getTopLeft(paymentReversal).dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const Key('payroll-ledger-row-advance-original')),
            )
            .dy,
      ),
    );

    await tester.tap(
      find.byKey(const Key('payroll-ledger-open-payment-item-reversal')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('payroll-ledger-detail-payment-item-reversal')),
      findsOneWidget,
    );
    expect(find.text('تفاصيل قانونية للقراءة فقط'), findsOneWidget);
  });

  testWidgets('read-only payroll user cannot see financial write actions', (
    tester,
  ) async {
    await _setSurface(tester, 1440);
    await tester.pumpWidget(
      _app(_page(roleCode: 'cashier', permissions: const ['payroll.read'])),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('payroll-add-employee')), findsNothing);
    expect(find.byKey(const Key('payroll-advance-employee-1')), findsNothing);
    expect(
      find.byKey(const Key('payroll-statement-employee-1')),
      findsOneWidget,
    );
  });

  testWidgets('owner receives employee edit and deactivate controls', (
    tester,
  ) async {
    await _setSurface(tester, 1440);
    await tester.pumpWidget(_app(_page(roleCode: 'owner')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('payroll-edit-employee-1')), findsOneWidget);
    expect(
      find.byKey(const Key('payroll-deactivate-employee-1')),
      findsOneWidget,
    );
  });
}

Widget _page({
  required String roleCode,
  List<String> permissions = const ['payroll.read'],
  PayrollOutbox? outbox,
  PayrollEnvelope? envelope,
}) => EmployeePayrollPage(
  token: 'token',
  tenantId: _tenant,
  tenantName: 'مؤسسة الاختبار',
  branchIds: const [_branch],
  roleCode: roleCode,
  permissions: permissions,
  initialEnvelope: envelope ?? _envelope(),
  outbox: outbox,
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
);

Widget _app(Widget child) => MaterialApp(
  home: Directionality(textDirection: TextDirection.rtl, child: child),
);

Future<void> _setSurface(WidgetTester tester, double width) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
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

PayrollEnvelope _envelope() => PayrollEnvelope(
  employees: [
    Employee.fromJson({
      'tenant_id': _tenant,
      'id': 'employee-1',
      'branch_id': _branch,
      'name': 'أحمد الموظف صاحب الاسم العربي الطويل جدًا للاختبار',
      'phone': '777123456',
      'base_salary_minor': 9007199254740991,
      'advance_balance_minor': 125000,
      'payable_balance_minor': 75000,
      'start_date': '2026-01-01',
      'notes': null,
      'active': true,
      'version': 1,
    }),
    Employee.fromJson({
      'tenant_id': _tenant,
      'id': 'employee-2',
      'branch_id': _branch,
      'name': 'موظف سابق',
      'phone': null,
      'base_salary_minor': 100000,
      'advance_balance_minor': 0,
      'payable_balance_minor': 10000,
      'start_date': '2025-01-01',
      'notes': null,
      'active': false,
      'version': 2,
    }),
  ],
  employeeAdvances: const [],
  payrollRuns: const [],
  payrollRunItems: const [],
  payrollAdvanceAllocations: const [],
  payrollPeriodClaims: const [],
  payrollPayments: const [],
  payrollPaymentItems: const [],
);

PayrollEnvelope _payableEnvelope() {
  final employee = _envelope().employees.first;
  final now = DateTime.now();
  final periodMonth =
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  final run = PayrollRun.fromJson({
    'tenant_id': _tenant,
    'id': 'open-run',
    'branch_id': _branch,
    'document_kind': 'payroll_run',
    'period_month': periodMonth,
    'selection_mode': 'all',
    'occurred_at': '2026-10-31T20:59:59.000Z',
    'status': 'posted',
    'device_id': 'device-1',
    'local_operation_id': 'open-run-operation',
    'operation_created_at': '2026-10-31T18:00:00.000Z',
    'total_gross_minor': 300000,
    'total_applied_minor': 50000,
    'total_net_minor': 250000,
    'restore_generation': 7,
  });
  final item = PayrollRunItem.fromJson({
    'tenant_id': _tenant,
    'id': 'open-run-item',
    'branch_id': _branch,
    'payroll_run_id': run.id,
    'employee_id': employee.id,
    'employee_name_snapshot': employee.name,
    'employee_phone_snapshot': employee.phone,
    'employee_base_salary_minor_snapshot': 300000,
    'gross_minor': 300000,
    'applied_advance_minor': 50000,
    'net_minor': 250000,
    'remaining_minor': 250000,
  });
  return PayrollEnvelope(
    employees: [employee],
    employeeAdvances: const [],
    payrollRuns: [run],
    payrollRunItems: [item],
    payrollAdvanceAllocations: const [],
    payrollPeriodClaims: const [],
    payrollPayments: const [],
    payrollPaymentItems: const [],
  );
}

class _SettlementTransport implements JsonTransport {
  bool restored = false;

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String>? headers,
    String? body,
  }) async => JsonResponse(
    statusCode: 200,
    body: jsonEncode({
      'items': [
        {
          'id': restored ? 'restored-account' : 'legacy-account',
          'code': restored ? '1110-RESTORED' : '1110-LEGACY',
          'name': restored ? 'Restored settlement' : 'Legacy settlement',
          'channel': 'cash',
          'version': restored ? 2 : 1,
        },
      ],
    }),
  );
}

PayrollEnvelope _envelopeWithAdvance(Map<String, dynamic> request) =>
    PayrollEnvelope(
      employees: _envelope().employees,
      employeeAdvances: [
        EmployeeAdvance.fromJson({
          'tenant_id': _tenant,
          'id': 'posted-advance-1',
          'branch_id': _branch,
          'employee_id': 'employee-1',
          'document_kind': 'employee_advance',
          'reversal_of_id': null,
          'amount_minor': request['amount_minor'],
          'category': request['category'],
          'note': request['note'],
          'account_code': request['account_code'],
          'occurred_at': request['occurred_at'],
          'status': 'posted',
          'reason': null,
          'device_id': request['device_id'],
          'local_operation_id': request['local_operation_id'],
          'restore_generation': request['restore_generation'],
          'operation_created_at': request['operation_created_at'],
        }),
      ],
      payrollRuns: const [],
      payrollRunItems: const [],
      payrollAdvanceAllocations: const [],
      payrollPeriodClaims: const [],
      payrollPayments: const [],
      payrollPaymentItems: const [],
    );

PayrollEnvelope _ledgerEnvelope() {
  final employee = _envelope().employees.first;
  final run = PayrollRun.fromJson({
    'tenant_id': _tenant,
    'id': 'run-original',
    'branch_id': _branch,
    'document_kind': 'payroll_run',
    'period_month': '2026-10',
    'selection_mode': 'selected',
    'occurred_at': '2026-10-31T20:59:59.000Z',
    'status': 'reversed',
    'device_id': 'device-1',
    'local_operation_id': 'run-operation',
    'operation_created_at': '2026-10-31T18:00:00.000Z',
    'total_gross_minor': 300000,
    'total_applied_minor': 50000,
    'total_net_minor': 250000,
    'restore_generation': 7,
  });
  final runReversal = PayrollRun.fromJson({
    ...run.toJson(),
    'id': 'run-reversal',
    'document_kind': 'payroll_run_reversal',
    'reversal_of_id': 'run-original',
    'reason': 'تصحيح موثق',
    'occurred_at': '2026-11-02T09:00:00.000Z',
    'status': 'posted',
    'local_operation_id': 'run-reversal-operation',
  });
  final item = PayrollRunItem.fromJson({
    'tenant_id': _tenant,
    'id': 'run-item-1',
    'branch_id': _branch,
    'payroll_run_id': 'run-original',
    'employee_id': employee.id,
    'employee_name_snapshot': employee.name,
    'employee_phone_snapshot': employee.phone,
    'employee_base_salary_minor_snapshot': 300000,
    'gross_minor': 300000,
    'applied_advance_minor': 50000,
    'net_minor': 250000,
    'remaining_minor': 200000,
  });
  final payment = PayrollPayment.fromJson({
    'tenant_id': _tenant,
    'id': 'payment-original',
    'branch_id': _branch,
    'payroll_run_id': 'run-original',
    'document_kind': 'payroll_payment',
    'occurred_at': '2026-11-01T09:00:00.000Z',
    'account_code': '1130-WALLET',
    'status': 'reversed',
    'device_id': 'device-1',
    'local_operation_id': 'payment-operation',
    'operation_created_at': '2026-11-01T08:00:00.000Z',
    'total_minor': 50000,
    'restore_generation': 7,
  });
  final paymentReversal = PayrollPayment.fromJson({
    ...payment.toJson(),
    'id': 'payment-reversal',
    'document_kind': 'payroll_payment_reversal',
    'reversal_of_id': 'payment-original',
    'reason': 'عكس دفعة',
    'occurred_at': '2026-11-03T09:00:00.000Z',
    'status': 'posted',
    'local_operation_id': 'payment-reversal-operation',
  });
  return PayrollEnvelope(
    employees: [employee],
    employeeAdvances: [
      EmployeeAdvance.fromJson({
        'tenant_id': _tenant,
        'id': 'advance-original',
        'branch_id': _branch,
        'employee_id': employee.id,
        'document_kind': 'employee_advance',
        'occurred_at': '2026-10-01T09:00:00.000Z',
        'category': 'advance',
        'note': 'سلفة موثقة',
        'account_code': '1130-WALLET',
        'status': 'posted',
        'device_id': 'device-1',
        'local_operation_id': 'advance-operation',
        'operation_created_at': '2026-10-01T08:00:00.000Z',
        'amount_minor': 50000,
        'restore_generation': 7,
      }),
    ],
    payrollRuns: [run, runReversal],
    payrollRunItems: [item],
    payrollAdvanceAllocations: const [],
    payrollPeriodClaims: const [],
    payrollPayments: [payment, paymentReversal],
    payrollPaymentItems: [
      PayrollPaymentItem.fromJson({
        'tenant_id': _tenant,
        'id': 'payment-item-original',
        'branch_id': _branch,
        'payroll_payment_id': 'payment-original',
        'payroll_run_item_id': 'run-item-1',
        'employee_id': employee.id,
        'employee_name_snapshot': employee.name,
        'amount_minor': 50000,
      }),
      PayrollPaymentItem.fromJson({
        'tenant_id': _tenant,
        'id': 'payment-item-reversal',
        'branch_id': _branch,
        'payroll_payment_id': 'payment-reversal',
        'payroll_run_item_id': 'run-item-1',
        'employee_id': employee.id,
        'employee_name_snapshot': employee.name,
        'amount_minor': 50000,
      }),
    ],
  );
}

class _DelayedPayrollOutbox extends PayrollOutbox {
  _DelayedPayrollOutbox(super.tenantId, super.branchId);

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> enqueue({
    required PayrollOperationKind kind,
    required String aggregateId,
    required Map<String, dynamic> request,
    bool Function()? isValid,
  }) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    await super.enqueue(
      kind: kind,
      aggregateId: aggregateId,
      request: request,
      isValid: isValid,
    );
  }
}
