import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/app.dart';
import 'package:nizami/src/auth/auth_api.dart';
import 'package:nizami/src/features/navigation/ninesoft_desktop_navigation.dart';
import 'package:nizami/src/features/navigation/ninesoft_app_launcher.dart';
import 'package:nizami/src/theme/ninesoft_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'desktop uses the start taskbar and keeps module navigation',
    (tester) async {
      SharedPreferences.setMockInitialValues(_syncReady);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        NizamiApp(authApi: _FakeAuthApi(), initialSession: _session),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NineSoftDesktopNavigation), findsNothing);
      expect(find.byType(NineSoftDesktopTopBar), findsOneWidget);
      expect(find.byKey(const Key('ninesoft-desktop-taskbar')), findsOneWidget);
      expect(find.byKey(const Key('ninesoft-start-button')), findsOneWidget);
      expect(find.byType(NineSoftMobileDock), findsNothing);
      expect(find.text('المبيعات'), findsWidgets);
      await tester.tap(find.byKey(const Key('ninesoft-start-button')));
      await tester.pumpAndSettle();
      expect(find.byType(NineSoftAppLauncher), findsOneWidget);
      final payrollApp = find.byKey(const Key('launcher-app-payroll'));
      expect(payrollApp, findsOneWidget);
      await tester.ensureVisible(payrollApp);
      await tester.pumpAndSettle();
      await tester.tap(payrollApp);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payroll-module')), findsOneWidget);
    },
  );

  testWidgets('mobile keeps the bottom shortcuts while a module is open', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(_syncReady);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NizamiApp(authApi: _FakeAuthApi(), initialSession: _session),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NineSoftMobileDock), findsOneWidget);
    final overviewGrid = tester.widget<GridView>(
      find.byKey(const Key('dashboard-overview-grid')),
    );
    final overviewDelegate =
        overviewGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(overviewDelegate.crossAxisCount, 2);
    final operationsShortcut = find.descendant(
      of: find.byType(NineSoftMobileDock),
      matching: find.text('العمليات'),
    );
    expect(operationsShortcut, findsOneWidget);
    await tester.tap(operationsShortcut);
    await tester.pumpAndSettle();
    expect(find.byType(NineSoftAppLauncher), findsOneWidget);
    final productsApp = find.byKey(const Key('launcher-app-products'));
    expect(productsApp, findsOneWidget);
    await tester.tap(productsApp);
    await tester.pumpAndSettle();
    expect(find.byType(NineSoftMobileDock), findsOneWidget);
    expect(find.text('الأصناف'), findsWidgets);
  });

  testWidgets('dashboard child shortcut opens the existing receipt editor', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(_syncReady);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NizamiApp(authApi: _FakeAuthApi(), initialSession: _session),
    );
    await tester.pumpAndSettle();

    final receipt = find.byKey(const Key('quick-action-receipt'));
    await tester.scrollUntilVisible(
      receipt,
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(receipt);
    await tester.pumpAndSettle();

    expect(find.text('سندات القبض'), findsWidgets);
  });

  testWidgets('Atlas applications launcher opens on desktop and filters apps', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(_syncReady);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NizamiApp(authApi: _FakeAuthApi(), initialSession: _session),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('التطبيقات'));
    await tester.pumpAndSettle();
    expect(find.byType(NineSoftAppLauncher), findsOneWidget);
    expect(find.text('قائمة NineSoft'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(NineSoftAppLauncher),
        matching: find.byType(TextField),
      ),
      'مرتجع',
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(NineSoftAppLauncher),
        matching: find.text('مرتجعات المبيعات'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Atlas applications launcher is reachable from mobile dock', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(_syncReady);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NizamiApp(authApi: _FakeAuthApi(), initialSession: _session),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('العمليات'));
    await tester.pumpAndSettle();
    expect(find.byType(NineSoftAppLauncher), findsOneWidget);
    expect(find.byKey(const Key('ninesoft-left-app-drawer')), findsOneWidget);
    expect(find.byKey(const Key('mobile-app-library-grid')), findsOneWidget);
    expect(find.byKey(const Key('mobile-app-library-list')), findsNothing);
    expect(find.byKey(const Key('launcher-app-sales')), findsOneWidget);
  });
}

const _session = AuthSession(
  token: 'test-token',
  userId: 'test-user',
  username: 'owner',
  displayName: 'مدير الاختبار',
  roleCode: 'owner',
  tenantId: 'test-tenant',
  tenantName: 'مؤسسة الاختبار',
  tenantSlug: 'test',
  branchIds: ['test-branch'],
  mustChangePassword: false,
);

const _syncReady = <String, Object>{
  'ninesoft.sync.v1.test-tenant.test-user.owner.test-branch..payroll_bootstrap':
      true,
};

class _FakeAuthApi implements AuthApi {
  @override
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {}

  @override
  Future<AuthSession> login({
    required String tenant,
    required String username,
    required String password,
  }) async => _session;

  @override
  Future<void> logout(String token) async {}
}
