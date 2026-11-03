import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/app.dart';
import 'package:nizami/src/auth/auth_api.dart';
import 'package:nizami/src/auth/auth_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('startup keeps a cached session after successful validation', (
    tester,
  ) async {
    final store = MemoryAuthSessionStore(_cachedSession);
    final api = _ValidatingAuthApi();

    await tester.pumpWidget(NizamiApp(authApi: api, authSessionStore: store));
    await tester.pumpAndSettle();

    expect(api.validatedTokens, ['cached-token']);
    expect(store.value?.token, 'cached-token');
    expect(find.text('كلمة المرور المؤقتة'), findsOneWidget);
    expect(find.text('اسم المستخدم'), findsNothing);
  });

  testWidgets(
    'startup persists revoked permissions and removed branches from auth/me',
    (tester) async {
      final store = MemoryAuthSessionStore(_cachedSession);
      final api = _ValidatingAuthApi(refreshedSession: _refreshedSession);

      await tester.pumpWidget(NizamiApp(authApi: api, authSessionStore: store));
      await tester.pumpAndSettle();

      expect(api.validatedTokens, ['cached-token']);
      expect(store.value?.token, 'cached-token');
      expect(store.value?.displayName, 'Updated Owner');
      expect(store.value?.roleCode, 'cashier');
      expect(store.value?.tenantName, 'Updated Tenant');
      expect(store.value?.branchIds, ['branch-b']);
      expect(store.value?.permissions, ['invoices.view']);
    },
  );

  for (final statusCode in [401, 404]) {
    testWidgets('startup clears a cached session after confirmed $statusCode', (
      tester,
    ) async {
      final store = MemoryAuthSessionStore(_cachedSession);
      final api = _ValidatingAuthApi(statusCode: statusCode);

      await tester.pumpWidget(NizamiApp(authApi: api, authSessionStore: store));
      await tester.pumpAndSettle();

      expect(api.validatedTokens, ['cached-token']);
      expect(store.value, isNull);
      expect(find.text('اسم المستخدم'), findsOneWidget);
      expect(find.text('كلمة المرور المؤقتة'), findsNothing);
    });
  }

  for (final failure in <({String label, int? statusCode})>[
    (label: 'network failure', statusCode: null),
    (label: 'server error', statusCode: 500),
  ]) {
    testWidgets('startup keeps a cached session after ${failure.label}', (
      tester,
    ) async {
      final store = MemoryAuthSessionStore(_cachedSession);
      final api = _ValidatingAuthApi(
        statusCode: failure.statusCode,
        fail: true,
      );

      await tester.pumpWidget(NizamiApp(authApi: api, authSessionStore: store));
      await tester.pumpAndSettle();

      expect(api.validatedTokens, ['cached-token']);
      expect(store.value?.token, 'cached-token');
      expect(find.text('كلمة المرور المؤقتة'), findsOneWidget);
      expect(find.text('اسم المستخدم'), findsNothing);
    });
  }

  testWidgets('explicit initial session is not treated as a cached session', (
    tester,
  ) async {
    final api = _ValidatingAuthApi(statusCode: 401);

    await tester.pumpWidget(
      NizamiApp(
        authApi: api,
        authSessionStore: MemoryAuthSessionStore(),
        initialSession: _cachedSession,
      ),
    );
    await tester.pumpAndSettle();

    expect(api.validatedTokens, isEmpty);
    expect(find.text('كلمة المرور المؤقتة'), findsOneWidget);
  });
}

const _cachedSession = AuthSession(
  token: 'cached-token',
  userId: 'user-id',
  username: 'owner',
  displayName: 'المالك',
  roleCode: 'owner',
  tenantId: 'tenant-id',
  tenantName: 'المؤسسة',
  tenantSlug: 'tenant',
  branchIds: ['branch-a', 'branch-b'],
  mustChangePassword: true,
  permissions: ['invoices.view', 'invoices.delete'],
);

const _refreshedSession = AuthSession(
  token: 'cached-token',
  userId: 'user-id',
  username: 'owner',
  displayName: 'Updated Owner',
  roleCode: 'cashier',
  tenantId: 'tenant-id',
  tenantName: 'Updated Tenant',
  tenantSlug: 'tenant',
  branchIds: ['branch-b'],
  mustChangePassword: true,
  permissions: ['invoices.view'],
);

class _ValidatingAuthApi implements AuthApi, AuthSessionValidator {
  _ValidatingAuthApi({
    this.statusCode,
    this.fail = false,
    this.refreshedSession,
  });

  final int? statusCode;
  final bool fail;
  final AuthSession? refreshedSession;
  final List<String> validatedTokens = [];

  @override
  Future<AuthSession> validateSession(AuthSession cachedSession) async {
    validatedTokens.add(cachedSession.token);
    if (fail || statusCode != null) {
      throw AuthApiException(
        statusCode == null ? 'network unavailable' : 'validation failed',
        statusCode: statusCode,
      );
    }
    return refreshedSession ?? cachedSession;
  }

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
  }) async => _cachedSession;

  @override
  Future<void> logout(String token) async {}
}
