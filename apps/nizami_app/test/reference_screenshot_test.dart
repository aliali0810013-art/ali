import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/invoices/invoice_workspace_page.dart';
import 'package:nizami/src/theme/nizami_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('capture phone sales editor', (tester) async {
    await capture(
      tester,
      size: const Size(390, 844),
      name: 'ninesoft-phone-sales',
    );
  });

  testWidgets('capture desktop sales editor', (tester) async {
    await capture(
      tester,
      size: const Size(1440, 900),
      name: 'ninesoft-desktop-sales',
    );
  });
}
