import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/accounting/financial_reports_page.dart';
import 'package:nizami/src/features/dashboard/dashboard_page.dart';
import 'package:nizami/src/features/dashboard/ninesoft_reference_dashboard.dart';
import 'package:nizami/src/features/modules/module_workspace_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('phone dashboard keeps recent operations and alerts inline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NineSoftReferenceDashboard(
              tenantName: 'ناين فود',
              tenantId: 'tenant-test',
              displayName: 'المالك',
              branchIds: const ['branch-test'],
              modules: const [_products],
              onOpen: (_) {},
              statusIndicator: const Text('متزامن'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-phone-operations')), findsOneWidget);
    expect(find.text('آخر العمليات'), findsOneWidget);
    expect(find.text('تنبيهات العمل'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('financial reports use compact phone controls and KPI cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: FinancialReportsPage(token: 'token', branchIds: []),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('financial-report-selector-grid')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('financial-report-filter-strip')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('financial-report-kpi-grid')), findsOneWidget);
    expect(find.text('إعداد التقرير'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile header exposes account actions without a popup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(
          themeMode: ThemeMode.light,
          onToggleTheme: () {},
          displayName: 'المالك',
          token: 'token',
          tenantName: 'ناين فود',
          tenantId: 'tenant-test',
          roleCode: 'owner',
          permissions: const [],
          branchIds: const [],
          onLogout: () {},
          onOpenModule: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byKey(const Key('dashboard-profile-action')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-theme-action')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-logout-action')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

const _products = ModuleDefinition(
  key: 'products',
  title: 'الأصناف',
  entityLabel: 'صنف',
  actionLabel: 'إضافة صنف',
  icon: Icons.inventory_2_rounded,
  color: Colors.orange,
);
