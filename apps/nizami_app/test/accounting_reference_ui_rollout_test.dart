import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nizami/src/features/accounting/account_statement_page.dart';
import 'package:nizami/src/features/accounting/account_transfer_page.dart';
import 'package:nizami/src/features/accounting/accounting_api.dart';
import 'package:nizami/src/features/accounting/accounting_periods_page.dart';
import 'package:nizami/src/features/accounting/cashbox_page.dart';
import 'package:nizami/src/features/accounting/chart_accounts_api.dart';
import 'package:nizami/src/features/accounting/financial_reports_page.dart';
import 'package:nizami/src/features/accounting/opening_balances_page.dart';
import 'package:nizami/src/features/accounting/product_inquiry_page.dart';
import 'package:nizami/src/features/inventory/stock_operations_page.dart';
import 'package:nizami/src/theme/ninesoft_entry_ui.dart';

const _workspacePages = <String>[
  'lib/src/features/accounting/account_statement_page.dart',
  'lib/src/features/accounting/account_transfer_page.dart',
  'lib/src/features/accounting/accounting_periods_page.dart',
  'lib/src/features/accounting/cashbox_page.dart',
  'lib/src/features/accounting/financial_reports_page.dart',
  'lib/src/features/accounting/opening_balances_page.dart',
  'lib/src/features/accounting/product_inquiry_page.dart',
  'lib/src/features/inventory/stock_operations_page.dart',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void setViewport(WidgetTester tester, double width, double height) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  test('all accounting workspaces use the reference heading and section', () {
    for (final path in _workspacePages) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains("import '../../theme/ninesoft_entry_ui.dart';"),
        reason: '$path must use the shared reference UI primitives',
      );
      expect(source, contains('NineSoftEntryHeading('), reason: path);
      expect(source, contains('NineSoftEntrySection('), reason: path);
    }
  });

  test('entry workspaces use the responsive grid and save footer', () {
    for (final path in const [
      'lib/src/features/accounting/account_transfer_page.dart',
      'lib/src/features/accounting/accounting_periods_page.dart',
      'lib/src/features/accounting/opening_balances_page.dart',
      'lib/src/features/inventory/stock_operations_page.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('NineSoftEntryFieldGrid('), reason: path);
      expect(source, contains('NineSoftEntryFooter('), reason: path);
    }
  });

  test(
    'financial reports and statements use the shared financial template',
    () {
      for (final path in const [
        'lib/src/features/accounting/account_statement_page.dart',
        'lib/src/features/accounting/financial_reports_page.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source,
          contains("import '../../theme/ninesoft_financial_ui.dart';"),
          reason: path,
        );
        expect(
          source,
          contains('NineSoftFinancialSummaryStrip('),
          reason: path,
        );
        expect(
          source,
          contains('NineSoftResponsiveFinancialTable('),
          reason: path,
        );
      }
    },
  );

  test('account statement supports document-aware Ctrl+P printing', () {
    final source = File(
      'lib/src/features/accounting/account_statement_page.dart',
    ).readAsStringSync();
    expect(source, contains('LogicalKeyboardKey.keyP'));
    expect(source, contains('compactDocumentNumber(number)'));
    expect(source, contains('_printSourceDocument()'));
  });

  for (final width in const [1440.0, 700.0, 390.0]) {
    testWidgets('populated cashbox adapts rows at ${width.toInt()}', (
      tester,
    ) async {
      final accounting = _FakeAccountingApi();
      final chart = _FakeChartApi();
      setViewport(tester, width, 900);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: CashboxPage(
              token: '',
              tenantName: 'NineSoft',
              tenantId: 'tenant-1',
              branchIds: const ['branch-1'],
              roleCode: 'owner',
              permissions: const [],
              accountingApi: accounting,
              chartApi: chart,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final beforeRefresh = accounting.journalReads;
      await tester.tap(find.byKey(const Key('cashbox-refresh-action')));
      await tester.pumpAndSettle();
      expect(accounting.journalReads, beforeRefresh + 1);
      expect(accounting.mutations, 0);

      await tester.scrollUntilVisible(
        find.byKey(const Key('cashbox-movements-section')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('بيع نقدي تجريبي'), findsOneWidget);
      expect(find.text('صرف مورد تجريبي'), findsOneWidget);
      if (width >= 900) {
        expect(
          find.byKey(const Key('cashbox-movements-table')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('cashbox-movement-card-journal-1')),
          findsNothing,
        );
      } else {
        expect(find.byKey(const Key('cashbox-movements-table')), findsNothing);
        expect(
          find.byKey(const Key('cashbox-movement-card-journal-1')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('period actions are reachable and cancel before mutation', (
    tester,
  ) async {
    final accounting = _FakeAccountingApi();
    setViewport(tester, 390, 700);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountingPeriodsPage(
            token: '',
            branchIds: const ['branch-1'],
            roleCode: 'owner',
            accountingApi: accounting,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('period-reason-field')),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('period-reason-field')),
      'إقفال بعد مطابقة جميع الحسابات',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('period-close-footer')),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('period-close-footer')), findsOneWidget);
    await tester.tap(find.text('إقفال الفترة'));
    await tester.pumpAndSettle();
    expect(find.text('إقفال فترة محاسبية'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(accounting.mutations, 0);

    await tester.scrollUntilVisible(
      find.byKey(const Key('annual-close-footer')),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('annual-close-footer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-owner and read-only stock keep posting disabled', (
    tester,
  ) async {
    setViewport(tester, 700, 900);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountingPeriodsPage(
            token: '',
            branchIds: const ['branch-1'],
            roleCode: 'accountant',
            accountingApi: _FakeAccountingApi(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final periodFooters = tester.widgetList<NineSoftEntryFooter>(
      find.byType(NineSoftEntryFooter),
    );
    expect(periodFooters, isNotEmpty);
    expect(periodFooters.every((footer) => !footer.enabled), isTrue);

    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: StockOperationsPage(
            token: '',
            tenantId: 'tenant-1',
            branchIds: [],
            isTransfer: false,
            canWrite: false,
          ),
        ),
      ),
    );
    await tester.pump();
    final stockFooter = tester.widget<NineSoftEntryFooter>(
      find.byType(NineSoftEntryFooter),
    );
    expect(stockFooter.enabled, isFalse);
    expect(
      find.text('هذه الجلسة لا تملك صلاحية ترحيل المخزون.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in const [1440.0, 700.0, 390.0]) {
    testWidgets('representative pages fit ${width.toInt()} without overflow', (
      tester,
    ) async {
      final pages = <Widget>[
        const AccountStatementPage(token: '', branchIds: []),
        const AccountTransferPage(token: '', branchIds: []),
        const AccountingPeriodsPage(
          token: '',
          branchIds: [],
          roleCode: 'owner',
        ),
        const CashboxPage(
          token: '',
          tenantName: 'NineSoft',
          tenantId: 'test-tenant',
          branchIds: [],
          roleCode: 'owner',
          permissions: [],
        ),
        const FinancialReportsPage(token: '', branchIds: []),
        const OpeningBalancesPage(token: '', branchIds: [], roleCode: 'owner'),
        const ProductInquiryPage(token: '', branchIds: []),
        const StockOperationsPage(
          token: '',
          tenantId: 'test-tenant',
          branchIds: [],
          isTransfer: false,
          canWrite: true,
        ),
      ];

      for (final page in pages) {
        setViewport(tester, width, 1200);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: Directionality(textDirection: TextDirection.rtl, child: page),
          ),
        );
        await tester.pump();

        expect(find.byType(NineSoftEntryHeading), findsOneWidget);
        expect(find.byType(NineSoftEntrySection), findsWidgets);
        expect(
          tester.takeException(),
          isNull,
          reason: '${page.runtimeType} @$width',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }
}

class _FakeAccountingApi extends AccountingApi {
  _FakeAccountingApi() : super(token: 'test');

  int journalReads = 0;
  int mutations = 0;

  @override
  Future<List<Map<String, dynamic>>> listJournals({
    required String branchId,
  }) async {
    journalReads++;
    return [
      {
        'id': 'journal-1',
        'description': 'بيع نقدي تجريبي',
        'reference_type': 'sale_invoice',
        'posted_at': '2026-10-31T08:00:00Z',
        'lines': [
          {
            'account_code': '1100-CASH',
            'debit_minor': 125000,
            'credit_minor': 0,
          },
        ],
      },
      {
        'id': 'journal-2',
        'description': 'صرف مورد تجريبي',
        'reference_type': 'supplier_payment',
        'posted_at': '2026-10-31T09:00:00Z',
        'lines': [
          {
            'account_code': '1100-CASH',
            'debit_minor': 0,
            'credit_minor': 25000,
          },
        ],
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> periodLocks() async => [
    {'branch_id': 'branch-1', 'closed_through': '2025-12-31'},
  ];

  @override
  Future<List<Map<String, dynamic>>> fiscalYearClosures() async => const [];

  @override
  Future<Map<String, dynamic>> accountingIntegrity(String branchId) async => {
    'status': 'balanced',
    'inventory_difference_minor': 0,
    'inventory_unvalued_movements': 0,
    'unassigned_contact_ledger_lines': 0,
    'journal_entry_errors': const [],
  };

  @override
  Future<Map<String, dynamic>> administrationMetadata() async => {
    'restore_generation': 1,
  };

  @override
  Future<Map<String, dynamic>> closeAccountingPeriod({
    required String branchId,
    required String through,
    required String reason,
    required int restoreGeneration,
    required String operationCreatedAt,
  }) async {
    mutations++;
    return const {};
  }
}

class _FakeChartApi extends ChartAccountsApi {
  _FakeChartApi() : super('test');

  @override
  Future<List<ChartAccount>> list(String branchId) async => const [
    ChartAccount(
      id: 'cash-1',
      code: '1100-CASH',
      nameAr: 'الصندوق الرئيسي',
      type: 'asset',
      normalBalance: 'debit',
      balanceMinor: 100000,
      isCashEquivalent: true,
    ),
  ];
}
