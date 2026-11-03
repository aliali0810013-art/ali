import 'dart:async';

import 'package:flutter/material.dart';

import 'auth/auth_api.dart';
import 'auth/auth_session_store.dart';
import 'auth/http_auth_api.dart';
import 'features/auth/change_password_page.dart';
import 'features/auth/login_page.dart';
import 'features/navigation/ninesoft_workspace_shell.dart';
import 'features/sync/realtime_sync_coordinator.dart';
import 'settings/theme_preference_store.dart';
import 'theme/nizami_theme.dart';

class NizamiApp extends StatefulWidget {
  const NizamiApp({
    super.key,
    this.themePreferences,
    this.authApi,
    this.authSessionStore,
    this.initialSession,
  });

  final ThemePreferenceStore? themePreferences;
  final AuthApi? authApi;
  final AuthSessionStore? authSessionStore;
  final AuthSession? initialSession;

  @override
  State<NizamiApp> createState() => _NizamiAppState();
}

class _NizamiAppState extends State<NizamiApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.light;
  late final ThemePreferenceStore _themePreferences;
  late final AuthApi _authApi;
  late final AuthSessionStore _authSessionStore;
  AuthSession? _session;
  bool _restoringSession = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themePreferences = widget.themePreferences ?? createThemePreferenceStore();
    _authApi = widget.authApi ?? createHttpAuthApi();
    _authSessionStore = widget.authSessionStore ?? PersistentAuthSessionStore();
    _session = widget.initialSession;
    _restoreTheme();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    var restored = widget.initialSession ?? await _authSessionStore.read();
    if (widget.initialSession == null &&
        restored != null &&
        _authApi is AuthSessionValidator) {
      try {
        final refreshed = await (_authApi as AuthSessionValidator)
            .validateSession(restored)
            .timeout(const Duration(seconds: 8));
        await _authSessionStore.write(refreshed);
        restored = refreshed;
      } on AuthApiException catch (error) {
        // Only an explicit authentication/not-found response proves that the
        // cached token is no longer usable. Connectivity failures and server
        // errors must keep the offline session available.
        if (error.statusCode == 401 || error.statusCode == 404) {
          await _authSessionStore.clear();
          restored = null;
        }
      } catch (_) {
        // Network/timeout failures are inconclusive. Preserve the cached
        // session so the offline-first application does not log the user out.
      }
    }
    if (!mounted) return;
    setState(() {
      _session = restored;
      _restoringSession = false;
    });
    if (restored != null && !restored.mustChangePassword) {
      unawaited(RealtimeSyncCoordinator.instance.start(restored));
    }
  }

  Future<void> _authenticated(AuthSession session) async {
    setState(() => _session = session);
    await _authSessionStore.write(session);
    if (!session.mustChangePassword) {
      unawaited(RealtimeSyncCoordinator.instance.start(session));
    }
  }

  Future<void> _passwordChanged() async {
    final session = _session?.passwordChanged();
    if (session == null) return;
    setState(() => _session = session);
    await _authSessionStore.write(session);
    unawaited(RealtimeSyncCoordinator.instance.start(session));
  }

  Future<void> _restoreTheme() async {
    final darkMode = await _themePreferences.readDarkMode();
    if (!mounted || darkMode == null) return;
    setState(() => _themeMode = darkMode ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> _toggleTheme() async {
    final nextMode = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    setState(() => _themeMode = nextMode);
    await _themePreferences.writeDarkMode(nextMode == ThemeMode.dark);
  }

  Future<void> _logout() async {
    final session = _session;
    if (session == null) return;
    RealtimeSyncCoordinator.instance.stop();
    setState(() => _session = null);
    await _authSessionStore.clear();
    try {
      await _authApi.logout(session.token);
    } on AuthApiException {
      // The local session remains closed even if revocation must be retried.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    RealtimeSyncCoordinator.instance.setForeground(
      state == AppLifecycleState.resumed,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RealtimeSyncCoordinator.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ناين سوفت',
      debugShowCheckedModeBanner: false,
      theme: NizamiTheme.light,
      darkTheme: NizamiTheme.dark,
      themeMode: _themeMode,
      // Keep the UI direction Arabic while using the English shaping locale.
      // This prevents Arabic-Indic digit substitution on Windows, Android,
      // web and native print dialogs without translating the custom Arabic UI.
      locale: const Locale('en'),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: ScrollConfiguration(
          behavior: const MaterialScrollBehavior().copyWith(scrollbars: true),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: _restoringSession
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _session == null
          ? LoginPage(
              authApi: _authApi,
              onAuthenticated: (session) => unawaited(_authenticated(session)),
            )
          : _session!.mustChangePassword
          ? ChangePasswordPage(
              authApi: _authApi,
              session: _session!,
              onChanged: () => unawaited(_passwordChanged()),
              onLogout: _logout,
            )
          : NineSoftWorkspaceShell(
              themeMode: _themeMode,
              onToggleTheme: _toggleTheme,
              displayName: _session!.displayName,
              tenantName: _session!.tenantName,
              tenantId: _session!.tenantId,
              roleCode: _session!.roleCode,
              permissions: _session!.permissions,
              branchIds: _session!.branchIds,
              token: _session!.token,
              onLogout: _logout,
            ),
    );
  }
}
