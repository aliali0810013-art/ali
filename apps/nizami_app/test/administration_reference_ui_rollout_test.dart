import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/auth_api.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/administration/administration_api.dart';
import 'package:nizami/src/features/administration/administration_page.dart';
import 'package:nizami/src/features/auth/change_password_page.dart';
import 'package:nizami/src/features/auth/login_page.dart';
import 'package:nizami/src/features/backup/backup_api.dart';
import 'package:nizami/src/features/backup/backup_page.dart';
import 'package:nizami/src/features/dashboard/section_hub_page.dart';
import 'package:nizami/src/features/modules/module_workspace_page.dart';
import 'package:nizami/src/features/settings/identity_api.dart';
import 'package:nizami/src/features/settings/identity_settings_page.dart';
import 'package:nizami/src/features/sync/quarantine_review_page.dart';
import 'package:nizami/src/features/wasl/wasl_api.dart';
import 'package:nizami/src/features/wasl/wasl_page.dart';
import 'package:nizami/src/features/wasl/wasl_qr_scanner_page.dart';
import 'package:nizami/src/features/whatsapp/whatsapp_api.dart';
import 'package:nizami/src/features/whatsapp/whatsapp_page.dart';
import 'package:nizami/src/theme/ninesoft_entry_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'owned administration pages retain the reference presentation contract',
    () {
      const entryPages = <String>[
        'lib/src/features/administration/administration_page.dart',
        'lib/src/features/auth/login_page.dart',
        'lib/src/features/auth/change_password_page.dart',
        'lib/src/features/backup/backup_page.dart',
        'lib/src/features/dashboard/section_hub_page.dart',
        'lib/src/features/settings/identity_settings_page.dart',
        'lib/src/features/sync/quarantine_review_page.dart',
        'lib/src/features/wasl/wasl_page.dart',
        'lib/src/features/whatsapp/whatsapp_page.dart',
      ];
      for (final path in entryPages) {
        final source = File(path).readAsStringSync();
        expect(source, contains('NineSoftEntryHeading('), reason: path);
        expect(source, contains('NineSoftEntrySection('), reason: path);
      }
      final scanner = File(
        'lib/src/features/wasl/wasl_qr_scanner_page.dart',
      ).readAsStringSync();
      expect(scanner, contains('0xFF08294D'));
      expect(scanner, contains('0xFF10C5A7'));
    },
  );

  Future<void> setViewport(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 700);
    addTearDown(tester.view.reset);
  }

  Widget app(Widget child) => MaterialApp(
    home: Directionality(textDirection: TextDirection.rtl, child: child),
  );

  void acrossWidths(
    String name,
    Future<void> Function(WidgetTester tester, double width) body,
  ) {
    for (final width in <double>[1440, 700, 390]) {
      testWidgets('$name at ${width.toInt()}', (tester) async {
        await setViewport(tester, width);
        await body(tester, width);
      });
    }
  }

  acrossWidths('login scrolls to its primary action', (tester, _) async {
    await tester.pumpWidget(
      app(LoginPage(authApi: _ErrorAuthApi(), onAuthenticated: (_) {})),
    );
    final action = find.byKey(const Key('login-submit'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();

    expect(find.byType(NineSoftEntryHeading), findsOneWidget);
    expect(find.byType(NineSoftEntrySection), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  acrossWidths('change password scrolls to its primary action', (
    tester,
    _,
  ) async {
    await tester.pumpWidget(
      app(
        ChangePasswordPage(
          authApi: _ErrorAuthApi(),
          session: _session,
          onChanged: () {},
          onLogout: () {},
        ),
      ),
    );
    final footer = find.byKey(const Key('change-password-footer'));
    await tester.ensureVisible(footer);
    await tester.tap(
      find.descendant(of: footer, matching: find.byType(FilledButton)),
    );
    await tester.pump();

    expect(find.byType(NineSoftEntryHeading), findsOneWidget);
    expect(find.byType(NineSoftEntrySection), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  acrossWidths('administration opens its owner create action', (
    tester,
    _,
  ) async {
    await tester.pumpWidget(
      app(
        AdministrationPage(
          token: 'token',
          tenantName: 'NineSoft',
          showUsers: true,
          roleCode: 'owner',
          api: AdministrationApi(
            token: 'token',
            transport: _AdministrationTransport(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final action = find.byKey(const Key('administration-create-action'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('إضافة مستخدم'), findsOneWidget);
    expect(find.byType(NineSoftEntryHeading), findsOneWidget);
    await tester.tap(find.text('إلغاء').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('all permissions toggle selects and clears every permission', (
    tester,
  ) async {
    await setViewport(tester, 700);
    await tester.pumpWidget(
      app(
        AdministrationPage(
          token: 'token',
          tenantName: 'NineSoft',
          showUsers: true,
          roleCode: 'owner',
          api: AdministrationApi(
            token: 'token',
            transport: _AdministrationTransport(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('administration-create-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('صلاحيات الفرع أو الموظف'));
    await tester.pumpAndSettle();

    final allPermissions = find.byKey(
      const Key('administration-all-permissions'),
    );
    expect(allPermissions, findsOneWidget);
    await tester.tap(allPermissions);
    await tester.pumpAndSettle();
    expect(find.text('محدد 29 صلاحيات'), findsOneWidget);

    await tester.tap(allPermissions);
    await tester.pumpAndSettle();
    expect(find.text('محدد 0 صلاحيات'), findsOneWidget);
  });

  testWidgets('user creation accepts any non-empty password', (tester) async {
    await setViewport(tester, 700);
    final transport = _AdministrationTransport();
    await tester.pumpWidget(
      app(
        AdministrationPage(
          token: 'token',
          tenantName: 'NineSoft',
          showUsers: true,
          roleCode: 'owner',
          api: AdministrationApi(token: 'token', transport: transport),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('administration-create-action')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'الاسم'), 'محمد');
    await tester.enterText(
      find.widgetWithText(TextField, 'اسم المستخدم'),
      'mohammed',
    );
    await tester.enterText(find.widgetWithText(TextField, 'كلمة المرور'), '1');

    await tester.tap(find.text('إنشاء المستخدم'));
    await tester.pumpAndSettle();

    expect(transport.lastUserRequest?['password'], '1');
  });

  testWidgets('customer copy page loads isolated copies instead of branches', (
    tester,
  ) async {
    await setViewport(tester, 700);
    final transport = _AdministrationTransport();
    await tester.pumpWidget(
      app(
        AdministrationPage(
          token: 'token',
          tenantName: 'NineSoft',
          showUsers: false,
          roleCode: 'owner',
          api: AdministrationApi(token: 'token', transport: transport),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(transport.requestedPaths, contains('/api/v1/customer-copies'));
    expect(
      transport.requestedPaths.where((path) => path.endsWith('/branches')),
      isEmpty,
    );
    expect(find.text('إدارة نسخ العملاء'), findsOneWidget);
    expect(find.text('نسخة عميل جديدة'), findsOneWidget);
  });

  testWidgets('customer copy creation sends one atomic provisioning request', (
    tester,
  ) async {
    await setViewport(tester, 700);
    final transport = _AdministrationTransport();
    await tester.pumpWidget(
      app(
        AdministrationPage(
          token: 'token',
          tenantName: 'NineSoft',
          showUsers: false,
          roleCode: 'owner',
          api: AdministrationApi(token: 'token', transport: transport),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('administration-create-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'اسم نسخة العميل أو المنشأة'),
      'مؤسسة الحارثي',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'رمز النسخة لتسجيل الدخول'),
      'alharthi',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'اسم المستخدم'),
      'owner',
    );
    await tester.enterText(find.widgetWithText(TextField, 'كلمة المرور'), '1');

    await tester.tap(find.text('إنشاء'));
    await tester.pumpAndSettle();

    expect(transport.lastCustomerCopyRequest?['name'], 'مؤسسة الحارثي');
    expect(transport.lastCustomerCopyRequest?['slug'], 'alharthi');
    expect(transport.lastCustomerCopyRequest?['owner_username'], 'owner');
    expect(transport.lastCustomerCopyRequest?['password'], '1');
    expect(
      transport.requestedPaths.where((path) => path.endsWith('/branches')),
      isEmpty,
    );
  });

  acrossWidths('backup scrolls to a guarded restore action', (tester, _) async {
    await tester.pumpWidget(
      app(
        BackupPage(
          token: 'token',
          api: BackupApi(token: 'token', transport: _BackupTransport()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final action = find.widgetWithIcon(IconButton, Icons.restore_rounded);
    await tester.scrollUntilVisible(
      action,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('إلغاء').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  acrossWidths('identity scrolls to its save action', (tester, _) async {
    final transport = _IdentityTransport();
    await tester.pumpWidget(
      app(
        IdentitySettingsPage(
          branchIds: const ['MAIN'],
          tenantName: 'NineSoft',
          tenantId: 'tenant',
          token: 'token',
          api: IdentityApi(token: 'token', transport: transport),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final footer = find.byKey(const Key('identity-save-footer'));
    await tester.ensureVisible(footer);
    await tester.tap(
      find.descendant(of: footer, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();

    expect(transport.puts, 1);
    expect(tester.takeException(), isNull);
  });

  acrossWidths('quarantine non-owner keeps refresh reachable', (
    tester,
    _,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    await tester.pumpWidget(
      app(
        const QuarantineReviewPage(
          tenantId: 'tenant',
          reviewer: 'reviewer',
          isOwner: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final action = find.widgetWithIcon(IconButton, Icons.refresh);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.byType(NineSoftEntryHeading), findsOneWidget);
    expect(find.byType(NineSoftEntrySection), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  acrossWidths('WASL scrolls to a populated transfer action', (
    tester,
    _,
  ) async {
    await tester.pumpWidget(
      app(
        WaslPage(
          token: 'token',
          tenantName: 'NineSoft',
          branchIds: const ['MAIN'],
          api: WaslApi(
            token: 'token',
            branchId: 'MAIN',
            transport: _WaslTransport(),
            baseUrl: 'https://example.test/api/v1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final action = find.text('100 YER');
    await tester.dragUntilVisible(
      action,
      find.byType(ListView),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('إغلاق').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  acrossWidths('QR scanner renders without a platform camera', (
    tester,
    _,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/scanner',
        routes: {
          '/': (_) => const Scaffold(body: Text('home')),
          '/scanner': (_) => Directionality(
            textDirection: TextDirection.rtl,
            child: WaslQrScannerPage(
              cameraPreviewBuilder: (_) => const ColoredBox(
                key: Key('scanner-placeholder'),
                color: Colors.black,
              ),
            ),
          ),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scanner-placeholder')), findsOneWidget);
    final back = find.byTooltip('Back');
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'login renders branded reference sections and keeps error state',
    (tester) async {
      await setViewport(tester, 390);
      await tester.pumpWidget(
        app(LoginPage(authApi: _ErrorAuthApi(), onAuthenticated: (_) {})),
      );

      expect(find.byType(NineSoftEntryHeading), findsOneWidget);
      expect(find.byType(NineSoftEntrySection), findsOneWidget);
      await tester.enterText(find.byKey(const Key('login-username')), 'owner');
      await tester.enterText(find.byKey(const Key('login-password')), 'wrong');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();

      expect(find.text('invalid-login'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('change password disables its reference footer while saving', (
    tester,
  ) async {
    await setViewport(tester, 390);
    final api = _PendingAuthApi();
    await tester.pumpWidget(
      app(
        ChangePasswordPage(
          authApi: api,
          session: _session,
          onChanged: () {},
          onLogout: () {},
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('change-password-current')),
      'temporary',
    );
    await tester.enterText(
      find.byKey(const Key('change-password-new')),
      'NewStrongPass123!',
    );
    await tester.enterText(
      find.byKey(const Key('change-password-confirmation')),
      'NewStrongPass123!',
    );
    final footerFinder = find.byKey(const Key('change-password-footer'));
    await tester.ensureVisible(footerFinder);
    await tester.tap(
      find.descendant(of: footerFinder, matching: find.byType(FilledButton)),
    );
    await tester.pump();

    final footer = tester.widget<NineSoftEntryFooter>(
      find.byKey(const Key('change-password-footer')),
    );
    expect(footer.enabled, isFalse);
    expect(api.calls, 1);
    api.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('non-owner administration keeps populated records read-only', (
    tester,
  ) async {
    await setViewport(tester, 390);
    await tester.pumpWidget(
      app(
        AdministrationPage(
          token: 'token',
          tenantName: 'NineSoft',
          showUsers: true,
          roleCode: 'manager',
          api: AdministrationApi(
            token: 'token',
            transport: _AdministrationTransport(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NineSoftEntryHeading), findsOneWidget);
    expect(find.byType(NineSoftEntrySection), findsOneWidget);
    expect(find.text('Test User'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[1440, 700, 390]) {
    testWidgets('populated section hub adapts at ${width.toInt()}', (
      tester,
    ) async {
      await setViewport(tester, width);
      var opened = false;
      await tester.pumpWidget(
        app(
          SectionHubPage(
            module: const ModuleDefinition(
              key: 'accounts',
              title: 'Accounts',
              entityLabel: 'Account',
              actionLabel: 'Open',
              icon: Icons.account_balance,
              color: Color(0xFF008E81),
            ),
            tenantName: 'NineSoft',
            token: 'token',
            branchIds: ['MAIN'],
            roleCode: 'owner',
            permissions: const [],
            onOpenChildModule: (_) => opened = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NineSoftEntryHeading), findsOneWidget);
      expect(find.byType(NineSoftEntrySection), findsOneWidget);
      expect(find.byKey(const Key('section-hub-grid')), findsOneWidget);
      final action = find.text('شجرة الحسابات');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in <double>[1440, 700, 390]) {
    testWidgets(
      'connected WhatsApp uses reference status at ${width.toInt()}',
      (tester) async {
        await setViewport(tester, width);
        await tester.pumpWidget(
          app(
            WhatsappPage(
              branchIds: const ['MAIN'],
              token: 'token',
              api: WhatsappApi(
                token: 'token',
                transport: _WhatsappTransport(),
                baseUrl: 'https://example.test/api/v1',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(NineSoftEntryHeading), findsOneWidget);
        expect(find.byType(NineSoftEntrySection), findsWidgets);
        final action = find.byKey(const ValueKey('disconnect-whatsapp'));
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('تراجع'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}

const _session = AuthSession(
  token: 'token',
  userId: 'owner-id',
  username: 'owner',
  displayName: 'Owner',
  roleCode: 'owner',
  tenantId: 'tenant-id',
  tenantName: 'NineSoft',
  tenantSlug: 'nine',
  branchIds: ['MAIN'],
  mustChangePassword: true,
);

class _ErrorAuthApi implements AuthApi {
  @override
  Future<AuthSession> login({
    required String tenant,
    required String username,
    required String password,
  }) => throw const AuthApiException('invalid-login');

  @override
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {}

  @override
  Future<void> logout(String token) async {}
}

class _PendingAuthApi extends _ErrorAuthApi {
  final _pending = Completer<void>();
  int calls = 0;

  void complete() => _pending.complete();

  @override
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) {
    calls++;
    return _pending.future;
  }
}

class _AdministrationTransport implements JsonTransport {
  Map<String, dynamic>? lastUserRequest;
  Map<String, dynamic>? lastCustomerCopyRequest;
  final requestedPaths = <String>[];

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    requestedPaths.add(uri.path);
    if (method == 'POST' && uri.path.endsWith('/users')) {
      lastUserRequest = Map<String, dynamic>.from(
        jsonDecode(body!) as Map<String, dynamic>,
      );
      return const JsonResponse(
        statusCode: 201,
        body:
            '{"data":{"id":"user-2","display_name":"محمد","username":"mohammed","role_code":"manager","branch_ids":["MAIN"]}}',
      );
    }
    if (method == 'POST' && uri.path.endsWith('/customer-copies')) {
      lastCustomerCopyRequest = Map<String, dynamic>.from(
        jsonDecode(body!) as Map<String, dynamic>,
      );
      return const JsonResponse(
        statusCode: 201,
        body:
            '{"data":{"id":"copy-2","name":"مؤسسة الحارثي","slug":"alharthi","active":true,"main_branch":{"id":"branch-2","code":"MAIN","name":"الفرع الرئيسي"},"owner":{"id":"owner-2","username":"owner","display_name":"مؤسسة الحارثي","access_expires_at":null}}}',
      );
    }
    if (uri.path.endsWith('/customer-copies')) {
      return const JsonResponse(
        statusCode: 200,
        body:
            '{"data":[{"id":"copy-1","name":"نسخة عميل","slug":"client-1","active":true,"main_branch":{"id":"branch-1","code":"MAIN","name":"الفرع الرئيسي"},"owner":{"id":"owner-1","username":"client","display_name":"مالك العميل","access_expires_at":null}}]}',
      );
    }
    if (uri.path.endsWith('/branches')) {
      return const JsonResponse(
        statusCode: 200,
        body: '{"data":[{"id":"MAIN","name":"Main"}]}',
      );
    }
    return const JsonResponse(
      statusCode: 200,
      body:
          '{"data":[{"id":"user-1","display_name":"Test User","username":"test","role_code":"sales","branch_ids":["MAIN"]}]}',
    );
  }
}

class _WhatsappTransport implements JsonTransport {
  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async => const JsonResponse(statusCode: 200, body: '{"state":"open"}');
}

class _BackupTransport implements JsonTransport {
  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async => const JsonResponse(
    statusCode: 200,
    body:
        '{"data":[{"name":"backup-test.json","size":2048,"created_at":"2026-11-01T08:30:00Z"}]}',
  );
}

class _IdentityTransport implements JsonTransport {
  int puts = 0;

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    if (method == 'PUT') puts++;
    return const JsonResponse(
      statusCode: 200,
      body:
          '{"data":{"business_name":"NineSoft","business_name_en":"NineSoft","business_tagline":"Accounting","phone":"777000000","address":"Sanaa","email":"info@example.test","invoice_header":"Header","invoice_footer":"Footer","primary_color":4280896120,"logo_scale":1.0}}',
    );
  }
}

class _WaslTransport implements JsonTransport {
  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    if (uri.path.endsWith('/wasl/capabilities')) {
      return const JsonResponse(
        statusCode: 200,
        body:
            '{"view_transfers":true,"view_raw_sms":true,"pair_devices":false,"unlink_devices":false,"sync_transfers":false,"approve_payment":false,"match_invoice":false}',
      );
    }
    if (uri.path.endsWith('/wasl/status')) {
      return const JsonResponse(
        statusCode: 200,
        body:
            '{"server_reachable":true,"linked":true,"last_sync_at":"2026-11-01T08:00:00Z"}',
      );
    }
    return const JsonResponse(
      statusCode: 200,
      body:
          '{"items":[{"id":"transfer-1","amount":"100","currency":"YER","source":"Bank","received_at":"2026-11-01T08:30:00Z","state":"sms_received","reference":"REF-1","body":"payment notice"}]}',
    );
  }
}
