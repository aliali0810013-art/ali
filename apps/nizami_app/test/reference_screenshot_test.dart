import 'dart:convert';

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
    SharedPreferences.setMockInitialValues({
      'ninesoft.products.v2.NineSoft': jsonEncode([
        {
          'id': 'prd-1001',
          'sku': 'IT-1001',
          'name': 'لابتوب 15 بوصة',
          'purchasePrice': 650.0,
          'salePrice': 800.0,
          'barcode': '6221000001001',
          'unitName': 'piece',
          'stockQuantity': 50.0,
          'hasPurchasePrice': true,
          'hasSalePrice': true,
          'version': 1,
        },
        {
          'id': 'prd-2005',
          'sku': 'IT-2005',
          'name': 'ماوس لاسلكي',
          'purchasePrice': 70.0,
          'salePrice': 95.0,
          'barcode': '6221000002005',
          'unitName': 'piece',
          'stockQuantity': 75.0,
          'hasPurchasePrice': true,
          'hasSalePrice': true,
          'version': 1,
        },
        {
          'id': 'prd-2006',
          'sku': 'IT-2006',
          'name': 'لوحة مفاتيح',
          'purchasePrice': 210.0,
          'salePrice': 280.0,
          'barcode': '6221000002006',
          'unitName': 'piece',
          'stockQuantity': 40.0,
          'hasPurchasePrice': true,
          'hasSalePrice': true,
          'version': 1,
        },
      ]),
      'ninesoft.customers.v2.NineSoft': jsonEncode([
        {
          'id': 'cus-1024',
          'name': 'مؤسسة النور للتجارة',
          'phone': '551234567',
          'updatedAt': '2026-11-03T10:00:00.000Z',
          'version': 1,
        },
      ]),
    });
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
    await tester.pumpAndSettle(const Duration(milliseconds: 700));

    await tester.enterText(
      find.byKey(const Key('invoice-reference-customer')),
      'مؤسسة النور للتجارة',
    );
    await tester.pump();

    Future<void> addProduct(String name, String quantity) async {
      final productField = find.byKey(const Key('invoice-product-input'));
      await tester.enterText(productField, name);
      await tester.pumpAndSettle();
      final option = find.text(name);
      if (option.evaluate().length > 1) {
        await tester.tap(option.last);
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.byKey(const Key('invoice-quantity-input')),
        quantity,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('invoice-reference-add-line')));
      await tester.pumpAndSettle();
    }

    await addProduct('لابتوب 15 بوصة', '2');
    await addProduct('ماوس لاسلكي', '3');
    await addProduct('لوحة مفاتيح', '1');

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
