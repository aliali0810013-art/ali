import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/auth_api.dart';
import 'package:nizami/src/features/auth/login_page.dart';

void main() {
  testWidgets('successful login submits fields and returns session', (
    tester,
  ) async {
    final api = _FakeAuthApi();
    AuthSession? authenticated;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          authApi: api,
          onAuthenticated: (session) => authenticated = session,
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'اسم المستخدم'),
      'owner',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'كلمة المرور'),
      'secret',
    );
    await tester.tap(find.text('تسجيل الدخول'));
    await tester.pumpAndSettle();

    expect(api.tenant, '');
    expect(api.username, 'owner');
    expect(authenticated?.displayName, 'المالك');
  });

  testWidgets('failed login displays server message', (tester) async {
    final api = _FakeAuthApi(error: 'بيانات الدخول غير صحيحة.');
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(authApi: api, onAuthenticated: (_) {}),
      ),
    );

    for (final label in ['اسم المستخدم', 'كلمة المرور']) {
      await tester.enterText(find.widgetWithText(TextFormField, label), 'x');
    }
    await tester.tap(find.text('تسجيل الدخول'));
    await tester.pumpAndSettle();

    expect(find.text('بيانات الدخول غير صحيحة.'), findsOneWidget);
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
  tenantSlug: 'company',
  branchIds: ['branch-id'],
  mustChangePassword: false,
);

class _FakeAuthApi implements AuthApi {
  _FakeAuthApi({this.error});

  final String? error;
  String? tenant;
  String? username;

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
  }) async {
    this.tenant = tenant;
    this.username = username;
    if (error != null) throw AuthApiException(error!);
    return _session;
  }

  @override
  Future<void> logout(String token) async {}
}
