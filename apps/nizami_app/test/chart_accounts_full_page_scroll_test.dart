import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nizami/src/features/accounting/chart_accounts_page.dart';
import 'package:nizami/src/theme/ninesoft_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('شجرة الحسابات تستخدم تمرير الصفحة وتحرك رأس الصفحة معها', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ChartAccountsPage(token: '', branchIds: [], roleCode: 'owner'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pageHeader = find.descendant(
      of: find.byType(NineSoftPageHeader),
      matching: find.text('شجرة الحسابات'),
    );
    final initialTop = tester.getTopLeft(pageHeader).dy;

    await tester.drag(
      find.byKey(const Key('chart-accounts-page-scroll')),
      const Offset(0, -360),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(pageHeader).dy, lessThan(initialTop - 80));
    expect(tester.takeException(), isNull);
  });
}
