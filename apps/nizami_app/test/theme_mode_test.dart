import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/app.dart';
import 'package:nizami/src/auth/auth_api.dart';
import 'package:nizami/src/features/dashboard/dashboard_page.dart';
import 'package:nizami/src/settings/theme_preference_store.dart';

void main() {
  testWidgets('theme toggle switches to dark mode and persists preference', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = MemoryThemePreferenceStore();
    await tester.pumpWidget(
      NizamiApp(
        themePreferences: preferences,
        authApi: _FakeAuthApi(),
        initialSession: _session,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('en'),
    );
    expect(
      Directionality.of(tester.element(find.byType(DashboardPage))),
      TextDirection.rtl,
    );

    await tester.tap(find.byTooltip('الوضع الليلي'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(preferences.value, isTrue);
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
