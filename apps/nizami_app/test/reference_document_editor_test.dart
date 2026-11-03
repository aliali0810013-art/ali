import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/theme/ninesoft_entry_ui.dart';
import 'package:nizami/src/theme/nizami_theme.dart';

const _longProduct =
    'صنف طويل جدًا لاختبار التفاف الاسم العربي داخل بطاقة بند الفاتورة دون تجاوز الشاشة';
const _largeAmount = '1,234,567,890,123.45 ر.ي';

void main() {
  void setViewport(WidgetTester tester, double width, double height) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget fixture({
    bool busy = false,
    ValueChanged<String>? onScan,
    VoidCallback? onDeleteFirst,
    VoidCallback? onDeleteSecond,
    VoidCallback? onPrimary,
    VoidCallback? onSecondary,
  }) {
    final lines = [
      NineSoftEntryLineCells(
        product: const Text('كمون ناعم'),
        unit: const Text('كيلوجرام'),
        quantity: const Text('1.000'),
        price: const Text('5,000'),
        total: const Text('5,000 ر.ي'),
        onDelete: onDeleteFirst,
        semanticsLabel: 'حذف الكمون',
      ),
      NineSoftEntryLineCells(
        product: const Text(_longProduct),
        unit: const Text('جرام'),
        quantity: const Text('100'),
        price: const Text('5'),
        total: const Text('500 ر.ي'),
        onDelete: onDeleteSecond,
        semanticsLabel: 'حذف الصنف الطويل',
      ),
    ];

    return MaterialApp(
      theme: NizamiTheme.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: const Key('reference-document-editor-fixture'),
              child: NineSoftDocumentEditorScaffold(
                main: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NineSoftScannerStrip(
                      input: TextField(
                        key: const Key('scanner-input'),
                        textInputAction: TextInputAction.done,
                        onSubmitted: onScan,
                        decoration: const InputDecoration(
                          hintText: 'امسح الباركود أو اكتب اسم الصنف',
                        ),
                      ),
                    ),
                    NineSoftEntryLineTable(lines: lines),
                  ],
                ),
                summary: NineSoftEntrySummary(
                  rows: const [
                    NineSoftEntrySummaryRow(
                      id: 'subtotal',
                      label: 'المجموع',
                      value: '5,500 ر.ي',
                    ),
                    NineSoftEntrySummaryRow(
                      id: 'grand-total',
                      label: 'الإجمالي النهائي',
                      value: _largeAmount,
                      emphasized: true,
                    ),
                  ],
                  primaryLabel: 'حفظ الفاتورة',
                  onPrimary: onPrimary,
                  secondaryLabel: 'حفظ كمسودة',
                  onSecondary: onSecondary,
                  helpText:
                      'سيتم حفظ المبلغ كما هو دون إعادة حساب داخل الواجهة.',
                  busy: busy,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpAt(
    WidgetTester tester,
    double width,
    double height, {
    Widget? child,
  }) async {
    setViewport(tester, width, height);
    await tester.pumpWidget(child ?? fixture());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  Widget stickyFixture(ScrollController controller) => MaterialApp(
    theme: NizamiTheme.light,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SingleChildScrollView(
          controller: controller,
          child: Column(
            children: [
              const SizedBox(height: 220),
              NineSoftDocumentEditorScaffold(
                main: const SizedBox(
                  key: Key('sticky-main-content'),
                  height: 1200,
                ),
                summary: Container(
                  key: const Key('sticky-summary-content'),
                  height: 260,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 600),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('1440 and 980 keep RTL two-column editor and desktop table', (
    tester,
  ) async {
    await pumpAt(tester, 1440, 900);
    var main = tester.getRect(find.byKey(const Key('ninesoft-editor-main')));
    var summary = tester.getRect(
      find.byKey(const Key('ninesoft-editor-summary')),
    );
    expect(summary.width, closeTo(304, .01));
    expect(main.top, closeTo(summary.top, .01));
    expect(main.left, greaterThan(summary.right));
    expect(main.left - summary.right, closeTo(15, .01));
    expect(find.byKey(const Key('ninesoft-entry-line-table')), findsOneWidget);
    expect(find.byKey(const Key('ninesoft-entry-line-card-0')), findsNothing);

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await pumpAt(tester, 980, 900);
    main = tester.getRect(find.byKey(const Key('ninesoft-editor-main')));
    summary = tester.getRect(find.byKey(const Key('ninesoft-editor-summary')));
    expect(summary.width, closeTo(265, .01));
    expect(main.top, closeTo(summary.top, .01));
    expect(main.left - summary.right, closeTo(15, .01));
    expect(find.byKey(const Key('ninesoft-entry-line-table')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('700 stacks full-width editor and converts rows to cards', (
    tester,
  ) async {
    await pumpAt(tester, 700, 1000);
    final editor = tester.getRect(
      find.byKey(const Key('ninesoft-document-editor')),
    );
    final main = tester.getRect(find.byKey(const Key('ninesoft-editor-main')));
    final summary = tester.getRect(
      find.byKey(const Key('ninesoft-editor-summary')),
    );
    expect(main.width, closeTo(editor.width, .01));
    expect(summary.width, closeTo(editor.width, .01));
    expect(summary.top - main.bottom, closeTo(12, .01));
    expect(find.byKey(const Key('ninesoft-entry-line-table')), findsNothing);
    expect(find.byKey(const Key('ninesoft-entry-line-header')), findsNothing);
    expect(find.byKey(const Key('ninesoft-entry-line-card-0')), findsOneWidget);
    expect(find.byKey(const Key('ninesoft-entry-line-card-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop summary sticks at 102 while mobile summary remains in document flow',
    (tester) async {
      final desktopController = ScrollController();
      addTearDown(desktopController.dispose);
      await pumpAt(tester, 1440, 600, child: stickyFixture(desktopController));
      final summaryFinder = find.byKey(const Key('ninesoft-editor-summary'));
      expect(tester.getTopLeft(summaryFinder).dy, closeTo(220, .01));

      desktopController.jumpTo(300);
      await tester.pump();
      expect(tester.getTopLeft(summaryFinder).dy, closeTo(102, .01));
      desktopController.jumpTo(500);
      await tester.pump();
      expect(tester.getTopLeft(summaryFinder).dy, closeTo(102, .01));
      expect(tester.takeException(), isNull);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      final mobileController = ScrollController();
      addTearDown(mobileController.dispose);
      await pumpAt(tester, 390, 600, child: stickyFixture(mobileController));
      mobileController.jumpTo(0);
      await tester.pump();
      final mobileInitialTop = tester.getTopLeft(summaryFinder).dy;
      mobileController.jumpTo(300);
      await tester.pump();
      expect(
        tester.getTopLeft(summaryFinder).dy,
        closeTo(mobileInitialTop - 300, .01),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('390 and 320 contain Arabic cards without horizontal scrolling', (
    tester,
  ) async {
    for (final dimensions in const [Size(390, 844), Size(320, 850)]) {
      await pumpAt(tester, dimensions.width, dimensions.height);
      final root = tester.getRect(
        find.byKey(const Key('reference-document-editor-fixture')),
      );
      for (var index = 0; index < 2; index++) {
        final card = tester.getRect(
          find.byKey(Key('ninesoft-entry-line-card-$index')),
        );
        expect(card.left, greaterThanOrEqualTo(root.left - .01));
        expect(card.right, lessThanOrEqualTo(root.right + .01));
      }
      final editor = tester.getRect(
        find.byKey(const Key('ninesoft-document-editor')),
      );
      expect(editor.left, greaterThanOrEqualTo(root.left - .01));
      expect(editor.right, lessThanOrEqualTo(root.right + .01));
      expect(find.text(_longProduct), findsOneWidget);
      expect(find.byKey(const Key('ninesoft-scanner-shortcut')), findsNothing);
      final horizontalScrollers = find
          .byType(SingleChildScrollView)
          .evaluate()
          .map((element) => element.widget as SingleChildScrollView)
          .where((widget) => widget.scrollDirection == Axis.horizontal);
      expect(horizontalScrollers, isEmpty);
      expect(tester.takeException(), isNull);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  testWidgets('scanner delete and summary callbacks are exact and busy-safe', (
    tester,
  ) async {
    String? scanned;
    var deletedFirst = 0;
    var deletedSecond = 0;
    var primary = 0;
    var secondary = 0;

    Widget callbackFixture({bool busy = false}) => fixture(
      busy: busy,
      onScan: (value) => scanned = value,
      onDeleteFirst: () => deletedFirst++,
      onDeleteSecond: () => deletedSecond++,
      onPrimary: () => primary++,
      onSecondary: () => secondary++,
    );

    await pumpAt(tester, 1440, 900, child: callbackFixture());
    await tester.enterText(find.byKey(const Key('scanner-input')), 'BAR-100');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(scanned, 'BAR-100');

    final secondRow = find.byKey(const Key('ninesoft-entry-line-row-1'));
    await tester.tap(
      find.descendant(of: secondRow, matching: find.byType(IconButton)),
    );
    expect(deletedFirst, 0);
    expect(deletedSecond, 1);

    await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
    await tester.tap(find.byKey(const Key('ninesoft-summary-secondary')));
    expect(primary, 1);
    expect(secondary, 1);

    await tester.pumpWidget(callbackFixture(busy: true));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
    await tester.tap(find.byKey(const Key('ninesoft-summary-secondary')));
    expect(primary, 1);
    expect(secondary, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('summary renders preformatted values verbatim', (tester) async {
    await pumpAt(tester, 390, 844);
    expect(find.byKey(const Key('ninesoft-summary-subtotal')), findsOneWidget);
    expect(
      find.byKey(const Key('ninesoft-summary-grand-total')),
      findsOneWidget,
    );
    expect(find.text(_largeAmount), findsOneWidget);
    expect(find.text('5,500 ر.ي'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop table centrally constrains editable text and dropdown cells',
    (tester) async {
      final editableLine = NineSoftEntryLineCells(
        product: const TextField(
          key: Key('compact-product-input'),
          decoration: InputDecoration(hintText: 'الصنف'),
        ),
        unit: DropdownButtonFormField<String>(
          key: const Key('compact-unit-input'),
          initialValue: 'kg',
          items: const [DropdownMenuItem(value: 'kg', child: Text('كيلوجرام'))],
          onChanged: (_) {},
        ),
        quantity: const TextField(
          key: Key('compact-disabled-input'),
          enabled: false,
          decoration: InputDecoration(hintText: 'الكمية'),
        ),
        price: const TextField(
          key: Key('compact-price-input'),
          decoration: InputDecoration(hintText: 'السعر'),
        ),
        total: const Text('5,000 ر.ي'),
      );
      await pumpAt(
        tester,
        1440,
        600,
        child: MaterialApp(
          theme: NizamiTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: NineSoftEntryLineTable(lines: [editableLine]),
            ),
          ),
        ),
      );

      for (final key in const [
        'compact-product-input',
        'compact-unit-input',
        'compact-disabled-input',
        'compact-price-input',
      ]) {
        expect(tester.getSize(find.byKey(Key(key))).height, closeTo(43, .01));
        final decorator = tester.widget<InputDecorator>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(InputDecorator),
          ),
        );
        final border = decorator.decoration.border!;
        final resolvedBorder = border is WidgetStateInputBorder
            ? border.resolve(const <WidgetState>{})
            : border;
        expect(
          (resolvedBorder as OutlineInputBorder).borderRadius,
          BorderRadius.circular(10),
        );
      }

      final productDecorator = tester.widget<InputDecorator>(
        find.descendant(
          of: find.byKey(const Key('compact-product-input')),
          matching: find.byType(InputDecorator),
        ),
      );
      final stateBorder = productDecorator.decoration.border;
      expect(stateBorder, isA<WidgetStateInputBorder>());
      expect(
        (stateBorder! as WidgetStateInputBorder)
            .resolve(const {WidgetState.hovered})
            .borderSide
            .color,
        const Color(0xFFB9D9EA),
      );

      final disabledDecorator = tester.widget<InputDecorator>(
        find.descendant(
          of: find.byKey(const Key('compact-disabled-input')),
          matching: find.byType(InputDecorator),
        ),
      );
      expect(
        WidgetStateProperty.resolveAs<Color?>(
          disabledDecorator.decoration.fillColor,
          const {WidgetState.disabled},
        ),
        const Color(0xFFF4F7FA),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
