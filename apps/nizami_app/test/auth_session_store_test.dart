import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/auth_api.dart';
import 'package:nizami/src/auth/auth_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('session survives application recreation', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PersistentAuthSessionStore();
    await store.write(_session);

    final restored = await PersistentAuthSessionStore().read();

    expect(restored?.token, _session.token);
    expect(restored?.tenantId, _session.tenantId);
    expect(restored?.permissions, _session.permissions);
  });

  test('expired session is rejected and removed', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PersistentAuthSessionStore();
    await store.write(
      AuthSession(
        token: 'expired',
        userId: 'user',
        username: 'owner',
        displayName: 'Owner',
        roleCode: 'owner',
        tenantId: 'tenant',
        tenantName: 'Tenant',
        tenantSlug: 'tenant',
        branchIds: const ['main'],
        mustChangePassword: false,
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );

    expect(await store.read(), isNull);
    expect(await store.read(), isNull);
  });
}

final _session = AuthSession(
  token: 'token',
  userId: 'user',
  username: 'owner',
  displayName: 'Owner',
  roleCode: 'owner',
  tenantId: 'tenant',
  tenantName: 'Tenant',
  tenantSlug: 'tenant',
  branchIds: const ['main'],
  mustChangePassword: false,
  permissions: const ['documents.edit'],
  expiresAt: DateTime.now().add(const Duration(days: 1)),
);
