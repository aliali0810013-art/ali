import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_api.dart';

abstract interface class AuthSessionStore {
  Future<AuthSession?> read();

  Future<void> write(AuthSession session);

  Future<void> clear();
}

class PersistentAuthSessionStore implements AuthSessionStore {
  static const _key = 'ninesoft.auth.session.v1';

  @override
  Future<AuthSession?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final session = AuthSession.fromJson(Map<String, dynamic>.from(decoded));
      if (session.token.isEmpty ||
          session.userId.isEmpty ||
          session.tenantId.isEmpty ||
          session.isExpired) {
        await clear();
        return null;
      }
      return session;
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(session.toJson()));
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
  }
}

class MemoryAuthSessionStore implements AuthSessionStore {
  MemoryAuthSessionStore([this.value]);

  AuthSession? value;

  @override
  Future<AuthSession?> read() async => value;

  @override
  Future<void> write(AuthSession session) async => value = session;

  @override
  Future<void> clear() async => value = null;
}
