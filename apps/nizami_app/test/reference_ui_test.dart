import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/theme/nizami_theme.dart';
import 'package:nizami/src/theme/ninesoft_ui.dart';

void main() {
  test('reference colors remain defined', () {
    expect(NizamiColors.navy, const Color(0xFF092B50));
    expect(NizamiColors.teal, const Color(0xFF00AF95));
    expect(NizamiColors.canvas, const Color(0xFFF3FAFF));
  });

  testWidgets('mobile dock retains original callbacks', (tester) async {
    var selected = -1;
    var saleOpened = false;
    await tester.pumpWidget(MaterialApp(
      theme: NizamiTheme.light,
      home: Scaffold(
        bottomNavigationBar: NineSoftMobileDock(
          currentIndex: 0,
          onSelected: (index) => selected = index,
          centerAction: () => saleOpened = true,
        ),
      ),
    ));
    expect(find.text('الرئيسية'), findsOneWidget);
    await tester.tap(find.text('المبيعات'));
    expect(saleOpened, isTrue);
    await tester.tap(find.text('التقارير'));
    expect(selected, 2);
  });
}
