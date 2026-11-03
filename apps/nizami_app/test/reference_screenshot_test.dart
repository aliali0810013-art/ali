// Sales visual acceptance: fixed 941x1672 physical capture, DPR 1.5.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/invoices/invoice_workspace_page.dart';
import 'package:nizami/src/features/invoices/invoice_history_store.dart';
import 'package:nizami/src/features/invoices/invoice_pdf_service.dart';
import 'package:nizami/src/features/navigation/ninesoft_workspace_shell.dart';
import 'package:nizami/src/theme/ninesoft_ui.dart';
import 'package:nizami/src/features/accounting/simple_journal_page.dart';
import 'package:nizami/src/theme/nizami_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _captureScreenshots = bool.fromEnvironment(
  'NINESOFT_CAPTURE_SCREENSHOTS',
);

DateTime _referenceNow() => DateTime(2025, 1, 30, 10, 24);
String _referenceInvoiceNumber(DateTime _) => 'INV-01542';

Future<void> _loadReferenceFonts() async {
  final loaders = [
    FontLoader('NizamiArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf')),
    FontLoader('GESS')
      ..addFont(rootBundle.load('assets/fonts/GE_SS_Two_Bold.ttf')),
    FontLoader('ArialMTBlack')
      ..addFont(rootBundle.load('assets/fonts/Arial_MT_Black.ttf')),
  ];
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    final materialIcons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (materialIcons.existsSync()) {
      final bytes = materialIcons.readAsBytesSync();
      loaders.add(
        FontLoader('MaterialIcons')
          ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes))),
      );
    }
  }
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
        {
          'id': 'prd-3001',
          'sku': 'IT-3001',
          'name': 'شاشة 24 بوصة',
          'purchasePrice': 610.0,
          'salePrice': 760.0,
          'barcode': '6221000003001',
          'unitName': 'piece',
          'stockQuantity': 24.0,
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
    double devicePixelRatio = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = devicePixelRatio;
    final logicalSize = Size(
      size.width / devicePixelRatio,
      size.height / devicePixelRatio,
    );
    final logicalWidth = logicalSize.width;
    expect(
      logicalSize.width * devicePixelRatio,
      closeTo(size.width, 0.000001),
    );
    expect(
      logicalSize.height * devicePixelRatio,
      closeTo(size.height, 0.000001),
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await InvoiceHistoryStore().save(
      'NineSoft',
      'branch-preview',
      InvoiceDocument(
        number: 'INV-01542',
        customerName: 'مؤسسة النور للتجارة',
        customerPhone: '551234567',
        customerId: 'cus-1024',
        lines: const [
          InvoiceLine(
            name: 'لابتوب 15 بوصة',
            quantity: 30,
            unitPrice: 800,
            productId: 'prd-1001',
            displayUnit: 'حبة',
            lineDiscountMinor: 240000,
          ),
          InvoiceLine(
            name: 'ماوس لاسلكي',
            quantity: 30,
            unitPrice: 95,
            productId: 'prd-2005',
            displayUnit: 'حبة',
          ),
          InvoiceLine(
            name: 'لوحة مفاتيح',
            quantity: 5,
            unitPrice: 280,
            productId: 'prd-2006',
            displayUnit: 'حبة',
            lineDiscountMinor: 14000,
          ),
          InvoiceLine(
            name: 'شاشة 24 بوصة',
            quantity: 6,
            unitPrice: 760,
            productId: 'prd-3001',
            displayUnit: 'حبة',
          ),
        ],
        currency: 'YER',
        employeeName: 'أحمد سالم',
        branchLabel: 'المخزن الرئيسي',
        createdAt: DateTime(2025, 1, 30, 10, 24),
        paymentMode: 'cash',
        paidAmount: 20000,
        discountAmount: 2160,
        amountTendered: 20000,
        paymentChannel: 'cash',
        localOperationId: 'reference-sales-draft',
        isDraft: true,
      ),
    );

    final invoice = const Directionality(
      textDirection: TextDirection.rtl,
      child: InvoiceWorkspacePage(
        branchIds: ['branch-preview'],
        tenantName: 'NineSoft',
        employeeName: 'أحمد سالم',
        branchDisplayName: 'المخزن الرئيسي',
        token: '',
        roleCode: 'owner',
        permissions: [],
        nowProvider: _referenceNow,
        invoiceNumberFactory: _referenceInvoiceNumber,
      ),
    );
    const captureKey = Key('visual-capture-root');
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: NizamiTheme.light,
        locale: const Locale('ar', 'YE'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: child!,
        ),
        home: logicalWidth < 700
            ? Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: Column(
                    children: [
                      NineSoftReferenceMobileHeader(
                        title: 'المبيعات',
                        onMenu: () {},
                        onProfile: () {},
                      ),
                      Expanded(child: invoice),
                    ],
                  ),
                  bottomNavigationBar: NineSoftMobileDock(
                    currentIndex: 0,
                    contextLabel: 'العمليات',
                    contextIcon: Icons.layers_outlined,
                    centerAction: () {},
                    onSelected: (_) {},
                  ),
                ),
              )
            : invoice,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 700));

    await tester.tap(find.byKey(const Key('invoice-history-open-primary')));
    await tester.pumpAndSettle();
    final historyRow = find.byKey(
      const Key('invoice-history-row-reference-sales-draft'),
    );
    expect(historyRow, findsOneWidget);
    await tester.tap(
      find.descendant(
        of: historyRow,
        matching: find.byIcon(Icons.visibility_outlined),
      ),
    );
    await tester.pumpAndSettle();
    final historyModal = find.byKey(
      const Key('invoice-history-modal-content'),
    );
    if (historyModal.evaluate().isNotEmpty) {
      Navigator.of(tester.element(historyModal)).pop();
      await tester.pumpAndSettle();
    }

    final editorScroll = find.byKey(const ValueKey('invoice-document-editor'));
    if (editorScroll.evaluate().isNotEmpty) {
      final scrollable = find
          .descendant(of: editorScroll, matching: find.byType(Scrollable))
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(0, 0.001));
    }

    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(captureKey),
      );
      final image = await boundary.toImage(pixelRatio: devicePixelRatio);
      expect(image.width, size.width.round());
      expect(image.height, size.height.round());
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        fail('Failed to encode visual capture $name');
      }
      final captures = Directory('test/captures')..createSync(recursive: true);
      File('${captures.path}/$name.png').writeAsBytesSync(
        png.buffer.asUint8List(),
        flush: true,
      );
      File('${captures.path}/$name-metadata.json').writeAsStringSync(
        jsonEncode({
          'logical_width': logicalSize.width,
          'logical_height': logicalSize.height,
          'dpr': devicePixelRatio,
          'physical_width': image.width,
          'physical_height': image.height,
          'reference_width': size.width.round(),
          'reference_height': size.height.round(),
          'text_scale': 1.0,
          'locale': 'ar_YE',
          'direction': 'rtl',
          'scroll_offset': 0.0,
          'font_wait_ms': 700,
        }),
        flush: true,
      );
    });
  }

  testWidgets(
    'capture phone sales editor',
    (tester) async {
      await capture(
        tester,
        size: const Size(941, 1672),
        name: 'ninesoft-phone-sales',
        devicePixelRatio: 1.5,
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
    skip: true,
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
    skip: true,
  );
}
