import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/theme/ninesoft_entry_ui.dart';
import 'package:nizami/src/theme/nizami_theme.dart';

void main() {
  void setViewport(WidgetTester tester, double width, [double height = 1000]) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget screen(Widget child) => MaterialApp(
    theme: NizamiTheme.light,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    ),
  );

  BoxDecoration decorationOf(WidgetTester tester, String key) {
    final container = tester.widget<Container>(find.byKey(Key(key)));
    return container.decoration! as BoxDecoration;
  }

  test('reference palette exposes exact cascade-resolved colors', () {
    expect(NizamiColors.navy, const Color(0xFF0B356F));
    expect(NizamiColors.navyDark, const Color(0xFF072A59));
    expect(NizamiColors.teal, const Color(0xFF14A966));
    expect(NizamiColors.tealDark, const Color(0xFF078B50));
    expect(NizamiColors.ink, const Color(0xFF10213F));
    expect(NizamiColors.canvas, const Color(0xFFF4F7FB));
    expect(NizamiColors.border, const Color(0xFFDCE4EF));
  });

  testWidgets('input theme and responsive field heights match reference', (
    tester,
  ) async {
    final theme = NizamiTheme.light.inputDecorationTheme;
    final enabled = theme.enabledBorder! as OutlineInputBorder;
    final focused = theme.focusedBorder! as OutlineInputBorder;
    expect(enabled.borderRadius.topLeft.x, 12);
    expect(enabled.borderSide.color, const Color(0xFFDCE4EF));
    expect(focused.borderRadius.topLeft.x, 12);
    expect(focused.borderSide.color, const Color(0xFF1769E8));

    Future<void> expectHeight(double width, double expected) async {
      setViewport(tester, width, 400);
      await tester.pumpWidget(
        screen(
          const NineSoftEntryFieldGrid(
            children: [
              TextField(
                key: Key('height-field'),
                decoration: InputDecoration(labelText: 'الحقل'),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const Key('height-field'))).height,
        expected,
      );
      final inputDecorator = tester.widget<InputDecorator>(
        find.descendant(
          of: find.byKey(const Key('height-field')),
          matching: find.byType(InputDecorator),
        ),
      );
      expect(
        inputDecorator.decoration.contentPadding,
        EdgeInsets.symmetric(
          horizontal: width <= 700 ? 9 : 12,
          vertical: 10,
        ),
      );
      expect(tester.takeException(), isNull);
    }

    await expectHeight(1440, 45);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await expectHeight(390, 43);
  });

  testWidgets('entry primitives expose exact radii borders and fills', (
    tester,
  ) async {
    setViewport(tester, 1440, 1400);
    await tester.pumpWidget(
      screen(
        Column(
          children: [
            const NineSoftEntryHeading(
              title: 'فاتورة بيع',
              subtitle: 'إدخال سريع',
              icon: Icons.receipt_long,
            ),
            const NineSoftEntrySection(
              title: 'بيانات المستند',
              icon: Icons.description_outlined,
              child: SizedBox(height: 10),
            ),
            const NineSoftEntrySteps(
              activeIndex: 0,
              steps: [
                NineSoftEntryStepData(title: 'المستند', subtitle: 'البيانات'),
                NineSoftEntryStepData(title: 'الأصناف', subtitle: 'البنود'),
                NineSoftEntryStepData(title: 'الدفع', subtitle: 'التسوية'),
                NineSoftEntryStepData(title: 'الحفظ', subtitle: 'المراجعة'),
              ],
            ),
            const NineSoftScannerStrip(input: TextField()),
            NineSoftEntrySummary(
              rows: const [
                NineSoftEntrySummaryRow(
                  id: 'total',
                  label: 'الإجمالي',
                  value: '1,000 ر.ي',
                  emphasized: true,
                ),
              ],
              primaryLabel: 'حفظ الفاتورة',
              onPrimary: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    final heading = decorationOf(tester, 'ninesoft-entry-heading');
    final section = decorationOf(tester, 'ninesoft-entry-section');
    final step = decorationOf(tester, 'ninesoft-entry-step-0');
    final scanner = decorationOf(tester, 'ninesoft-scanner-strip');
    final summary = decorationOf(tester, 'ninesoft-entry-summary');

    expect(heading.borderRadius, BorderRadius.circular(22));
    expect(section.borderRadius, BorderRadius.circular(17));
    expect((section.border! as Border).top.color, const Color(0xFFDCE4EF));
    expect(step.borderRadius, BorderRadius.circular(15));
    expect((step.border! as Border).top.color, const Color(0xFFBBD5FA));
    expect(scanner.borderRadius, BorderRadius.circular(15));
    expect(scanner.color, const Color(0xFFF4F8FF));
    expect((scanner.border! as Border).top.color, const Color(0xFFCFE0F7));
    expect(summary.borderRadius, BorderRadius.circular(17));
    expect((summary.border! as Border).top.color, const Color(0xFFDCE4EF));
    expect(tester.takeException(), isNull);
  });

  testWidgets('steps use four columns then exactly two by two at 700', (
    tester,
  ) async {
    const steps = NineSoftEntrySteps(
      activeIndex: 1,
      steps: [
        NineSoftEntryStepData(title: 'الأول', subtitle: 'أ'),
        NineSoftEntryStepData(title: 'الثاني', subtitle: 'ب'),
        NineSoftEntryStepData(title: 'الثالث', subtitle: 'ج'),
        NineSoftEntryStepData(title: 'الرابع', subtitle: 'د'),
      ],
    );

    Future<void> pumpAt(double width) async {
      setViewport(tester, width, 500);
      await tester.pumpWidget(screen(steps));
      await tester.pump();
    }

    await pumpAt(1440);
    var rects = List.generate(
      4,
      (index) => tester.getRect(find.byKey(Key('ninesoft-entry-step-$index'))),
    );
    expect(rects.map((rect) => rect.top).toSet(), hasLength(1));
    final ordered = [...rects]..sort((a, b) => a.left.compareTo(b.left));
    for (var index = 1; index < ordered.length; index++) {
      expect(ordered[index].left - ordered[index - 1].right, closeTo(9, .01));
    }
    expect(decorationOf(tester, 'ninesoft-entry-step-0').color, Colors.white);
    expect(
      (decorationOf(tester, 'ninesoft-entry-step-1').gradient!
              as LinearGradient)
          .colors,
      const [Color(0xFFEAF3FF), Color(0xFFFFFFFF)],
    );
    expect(
      decorationOf(tester, 'ninesoft-entry-step-number-0').color,
      const Color(0xFFE7F0FC),
    );
    expect(
      decorationOf(tester, 'ninesoft-entry-step-number-1').color,
      const Color(0xFF1769E8),
    );
    expect(tester.takeException(), isNull);

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await pumpAt(700);
    rects = List.generate(
      4,
      (index) => tester.getRect(find.byKey(Key('ninesoft-entry-step-$index'))),
    );
    expect(rects[0].top, closeTo(rects[1].top, .01));
    expect(rects[2].top, closeTo(rects[3].top, .01));
    expect(rects[2].top, greaterThan(rects[0].bottom));
    final firstRow = [rects[0], rects[1]]
      ..sort((a, b) => a.left.compareTo(b.left));
    expect(firstRow[1].left - firstRow[0].right, closeTo(7, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('field grid is 4, 2, 2 and 1 columns at reference widths', (
    tester,
  ) async {
    Widget grid() => screen(
      NineSoftEntryFieldGrid(
        children: List.generate(
          4,
          (index) => TextField(
            key: Key('grid-field-$index'),
            decoration: InputDecoration(labelText: 'حقل ${index + 1}'),
          ),
        ),
      ),
    );

    Future<List<Rect>> rectsAt(double width) async {
      setViewport(tester, width, 600);
      await tester.pumpWidget(grid());
      await tester.pump();
      final result = List.generate(
        4,
        (index) => tester.getRect(find.byKey(Key('grid-field-$index'))),
      );
      expect(tester.takeException(), isNull);
      return result;
    }

    var rects = await rectsAt(1440);
    expect(rects.map((rect) => rect.top).toSet(), hasLength(1));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();

    for (final width in [700.0, 390.0]) {
      rects = await rectsAt(width);
      expect(rects[0].top, closeTo(rects[1].top, .01));
      expect(rects[2].top, closeTo(rects[3].top, .01));
      expect(rects[2].top, greaterThan(rects[0].bottom));
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }

    rects = await rectsAt(320);
    expect(rects.map((rect) => rect.top).toSet(), hasLength(4));
  });

  testWidgets('legacy amount preview stays formatted and read only', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NineSoftEntryTotalPreview(label: 'الإجمالي', amount: 1250.5),
        ),
      ),
    );
    expect(find.text('1250.50 ر.ي'), findsOneWidget);
  });

  testWidgets('disabled footer does not submit', (tester) async {
    var clicks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NineSoftEntryFooter(
            label: 'ترحيل',
            enabled: false,
            onSave: () => clicks++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('ترحيل'));
    expect(clicks, 0);
  });
}
