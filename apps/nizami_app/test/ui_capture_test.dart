import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/app.dart';
import 'package:nizami/src/auth/auth_api.dart';
import 'package:nizami/src/features/modules/module_workspace_page.dart';
import 'package:nizami/src/features/navigation/ninesoft_desktop_navigation.dart';
import 'package:nizami/src/theme/nizami_theme.dart';
import 'package:nizami/src/settings/theme_preference_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('capture desktop dashboard', (tester) async {
    await _loadVisualFonts();
    SharedPreferences.setMockInitialValues({});
    await _setSurface(tester, const Size(1440, 900));
    await tester.pumpWidget(
      NizamiApp(
        authApi: _FakeAuthApi(),
        initialSession: _session,
        themePreferences: MemoryThemePreferenceStore(),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/ninesoft-dashboard-desktop.png'),
    );
  }, skip: !_captureGoldens);

  testWidgets('capture mobile dashboard', (tester) async {
    await _loadVisualFonts();
    SharedPreferences.setMockInitialValues({});
    await _setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(
      NizamiApp(
        authApi: _FakeAuthApi(),
        initialSession: _session,
        themePreferences: MemoryThemePreferenceStore(),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/ninesoft-dashboard-mobile.png'),
    );
  }, skip: !_captureGoldens);

  testWidgets('capture responsive products empty state', (tester) async {
    await _loadVisualFonts();
    SharedPreferences.setMockInitialValues({});
    await _setSurface(tester, const Size(1280, 800));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: NizamiTheme.light,
        locale: const Locale('en'),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const ModuleWorkspacePage(
          module: ModuleDefinition(
            key: 'products',
            title: 'الأصناف',
            entityLabel: 'صنف',
            actionLabel: 'إضافة صنف',
            icon: Icons.inventory_2_rounded,
            color: Color(0xFF0868F7),
          ),
          tenantName: 'NineSoft',
          tenantId: 'visual-test-tenant',
          token: '',
          branchIds: ['visual-test-branch'],
          roleCode: 'owner',
          permissions: [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/ninesoft-products-desktop-empty.png'),
    );
  }, skip: !_captureGoldens);

  for (final section in _sections) {
    testWidgets('capture ${section.slug} phone section', (tester) async {
      await _captureSection(
        tester,
        section: section,
        size: const Size(390, 844),
        golden: 'goldens/sections/${section.slug}-phone.png',
      );
    }, skip: !_captureGoldens);

    testWidgets('capture ${section.slug} desktop section', (tester) async {
      await _captureSection(
        tester,
        section: section,
        size: const Size(1440, 900),
        golden: 'goldens/sections/${section.slug}-desktop.png',
      );
    }, skip: !_captureGoldens);
  }
}

const _captureGoldens = bool.fromEnvironment('NINESOFT_CAPTURE_GOLDENS');

bool _fontsLoaded = false;

Future<void> _loadVisualFonts() async {
  if (_fontsLoaded) return;
  final loaders = <FontLoader>[
    FontLoader('NizamiArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf')),
    FontLoader('GESS')
      ..addFont(rootBundle.load('assets/fonts/GE_SS_Two_Bold.ttf')),
    FontLoader('ArialMTBlack')
      ..addFont(rootBundle.load('assets/fonts/Arial_MT_Black.ttf')),
    FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')),
  ];
  await Future.wait(loaders.map((loader) => loader.load()));
  _fontsLoaded = true;
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _captureSection(
  WidgetTester tester, {
  required ({String slug, String title, String desktopTitle}) section,
  required Size size,
  required String golden,
}) async {
  await _loadVisualFonts();
  SharedPreferences.setMockInitialValues({});
  await _setSurface(tester, size);
  await tester.pumpWidget(
    NizamiApp(
      authApi: _FakeAuthApi(),
      initialSession: _session,
      themePreferences: MemoryThemePreferenceStore(),
    ),
  );
  await tester.pumpAndSettle();
  final desktop = size.width >= 900;
  Finder target = desktop
      ? find.descendant(
          of: find.byType(NineSoftDesktopNavigation),
          matching: find.text(section.desktopTitle),
        )
      : find.text(section.title);
  if (!desktop && target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      420,
      scrollable: find.byType(Scrollable).first,
    );
  }
  if (target.evaluate().length > 1) target = target.first;
  expect(target, findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(golden));
}

const _sections = <({String slug, String title, String desktopTitle})>[
  (slug: 'sales', title: 'المبيعات', desktopTitle: 'المبيعات'),
  (slug: 'purchases', title: 'المشتريات', desktopTitle: 'المشتريات'),
  (slug: 'products', title: 'الأصناف', desktopTitle: 'الأصناف'),
  (slug: 'customers', title: 'العملاء', desktopTitle: 'العملاء'),
  (slug: 'suppliers', title: 'الموردون', desktopTitle: 'الموردون'),
  (slug: 'inventory', title: 'المستودعات', desktopTitle: 'المخزون'),
  (slug: 'accounts', title: 'المحاسبة', desktopTitle: 'الحسابات'),
  (slug: 'documents', title: 'السندات', desktopTitle: 'السندات'),
  (slug: 'reports', title: 'التقارير', desktopTitle: 'التقارير'),
  (slug: 'settings', title: 'الإعدادات', desktopTitle: 'الإعدادات'),
];

const _session = AuthSession(
  token: 'visual-test-token',
  userId: 'visual-test-user',
  username: 'owner',
  displayName: 'مدير النظام',
  roleCode: 'owner',
  tenantId: 'visual-test-tenant',
  tenantName: 'NineSoft',
  tenantSlug: 'visual-test',
  branchIds: ['visual-test-branch'],
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
