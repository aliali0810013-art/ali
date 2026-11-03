import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/auth_api.dart';
import 'package:nizami/src/features/auth/change_password_page.dart';

void main() {
  testWidgets('temporary owner password must be replaced before continuing', (
    tester,
  ) async {
    final api = _FakeAuthApi();
    var changed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ChangePasswordPage(
          authApi: api,
          session: _session,
          onChanged: () => changed = true,
          onLogout: () {},
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'كلمة المرور المؤقتة'),
      'temporary',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'كلمة المرور الجديدة'),
      'NewStrongPass123!',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'تأكيد كلمة المرور الجديدة'),
      'NewStrongPass123!',
    );
    await tester.tap(find.text('حفظ ومتابعة'));
    await tester.pumpAndSettle();

    expect(api.changed, isTrue);
    expect(changed, isTrue);
  });
}

const _session = AuthSession(
  token: 'token',
  userId: 'owner-id',
  username: 'owner',
  displayName: 'مالك النظام',
  roleCode: 'owner',
  tenantId: 'tenant-id',
  tenantName: 'المؤسسة',
  tenantSlug: '001',
  branchIds: ['branch-id'],
  mustChangePassword: true,
);

class _FakeAuthApi implements AuthApi {
  bool changed = false;

  @override
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    changed = true;
  }

  @override
  Future<AuthSession> login({
    required String tenant,
    required String username,
    required String password,
  }) async => _session;

  @override
  Future<void> logout(String token) async {}
}
