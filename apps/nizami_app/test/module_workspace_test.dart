import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/app.dart';
import 'package:nizami/src/auth/auth_api.dart';
import 'package:nizami/src/features/modules/module_workspace_page.dart';
import 'package:nizami/src/features/navigation/ninesoft_app_launcher.dart';
import 'package:nizami/src/theme/ninesoft_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('dashboard modules open and accept a new record', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      NizamiApp(authApi: _FakeAuthApi(), initialSession: _session),
    );
    await tester.pumpAndSettle();

    // The responsive shell intentionally exposes the same destination in the
    // dashboard grid and the persistent mobile shortcut bar. Exercise the
    // always-visible shortcut without making the test ambiguous.
    final operationsShortcut = find.descendant(
      of: find.byType(NineSoftMobileDock),
      matching: find.text('العمليات'),
    );
    expect(operationsShortcut, findsOneWidget);
    await tester.tap(operationsShortcut);
    await tester.pumpAndSettle();
    expect(find.byType(NineSoftAppLauncher), findsOneWidget);
    await tester.tap(find.byKey(const Key('launcher-app-products')));
    await tester.pumpAndSettle();

    expect(find.text('إضافة صنف'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('add-products')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('record-title')),
      'طابعة حرارية',
    );
    await tester.enterText(
      find.byKey(const ValueKey('record-details')),
      '15000 ريال',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('save-record')));
    await tester.tap(find.byKey(const ValueKey('save-record')));
    await tester.pumpAndSettle();

    expect(find.text('طابعة حرارية'), findsOneWidget);
    expect(find.textContaining('15000 ريال'), findsOneWidget);
  });

  testWidgets('read-only accounting records cannot be edited or deleted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ninesoft.verified.report.v1.tenant-id.branch-id.debts.dues':
          '[{"title":"عميل آجل","details":"فاتورة INV-1","updatedAt":"2026-10-22T09:00:00.000","amount":100.0,"currency":"YER","settled":false,"serverId":"test:1"}]',
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: ModuleWorkspacePage(
          module: ModuleDefinition(
            key: 'debts.dues',
            title: 'سجل الاستحقاقات',
            entityLabel: 'استحقاق',
            actionLabel: 'إضافة استحقاق',
            icon: Icons.account_balance_wallet_outlined,
            color: Colors.orange,
          ),
          tenantName: 'المؤسسة',
          tenantId: 'tenant-id',
          token: '',
          branchIds: ['branch-id'],
          roleCode: 'owner',
          permissions: [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsNothing);
    expect(find.text('عميل آجل'), findsOneWidget);
  });

  testWidgets('catalog write permission controls product creation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const module = ModuleDefinition(
      key: 'products',
      title: 'الأصناف',
      entityLabel: 'صنف',
      actionLabel: 'إضافة صنف',
      icon: Icons.inventory_2_outlined,
      color: Colors.blue,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: ModuleWorkspacePage(
          module: module,
          tenantName: 'المؤسسة',
          tenantId: 'tenant-id',
          token: '',
          branchIds: ['branch-id'],
          roleCode: 'sales',
          permissions: ['catalog.read'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-products')), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: ModuleWorkspacePage(
          module: module,
          tenantName: 'المؤسسة',
          tenantId: 'tenant-id',
          token: '',
          branchIds: ['branch-id'],
          roleCode: 'sales',
          permissions: ['catalog.read', 'catalog.write'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-products')), findsOneWidget);
  });
}

const _session = AuthSession(
  token: 'token',
  userId: 'user-id',
  username: 'owner',
  displayName: 'المالك',
  roleCode: 'owner',
  tenantId: 'tenant-id',
  tenantName: 'المؤسسة',
  tenantSlug: 'tenant',
  branchIds: ['branch-id'],
  mustChangePassword: false,
);

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
