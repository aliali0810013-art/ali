import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/invoices/invoice_workspace_page.dart';
import 'package:nizami/src/features/accounting/simple_journal_page.dart';
import 'package:nizami/src/theme/nizami_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _captureScreenshots = bool.fromEnvironment(
  'NINESOFT_CAPTURE_SCREENSHOTS',
);

Future<void> _loadReferenceFonts() async {
  final loaders = [
    FontLoader('NizamiArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf')),
    FontLoader('GESS')
      ..addFont(rootBundle.load('assets/fonts/GE_SS_Two_Bold.ttf')),
    FontLoader('ArialMTBlack')
      ..addFont(rootBundle.load('assets/fonts/Arial_MT_Black.ttf')),
  ];
  await Future.wait(loaders.map((loader) => loader.load()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadReferenceFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> capture(
    WidgetTester tester, {
    required Size size,
    required String name,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: NizamiTheme.light,
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: InvoiceWorkspacePage(
            branchIds: ['branch-preview'],
            tenantName: 'NineSoft',
            employeeName: 'المستخدم',
            token: '',
            roleCode: 'owner',
            permissions: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets(
    'capture phone sales editor',
    (tester) async {
      await capture(
        tester,
        size: const Size(390, 844),
        name: 'ninesoft-phone-sales',
      );
    },
    skip: !_captureScreenshots,
  );

  testWidgets(
    'capture phone journal editor',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: NizamiTheme.light,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: SimpleJournalPage(
              token: '',
              branchIds: ['branch-preview'],
              roleCode: 'owner',
              permissions: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      final create = find.text('قيد جديد');
      expect(create, findsWidgets);
      await tester.tap(create.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/ninesoft-phone-journal.png'),
      );
    },
    skip: !_captureScreenshots,
  );

  testWidgets(
    'capture desktop sales editor',
    (tester) async {
      await capture(
        tester,
        size: const Size(1440, 900),
        name: 'ninesoft-desktop-sales',
      );
    },
    skip: !_captureScreenshots,
  );
}
