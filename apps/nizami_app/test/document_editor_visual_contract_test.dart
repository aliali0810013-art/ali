import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/theme/ninesoft_entry_ui.dart';

void main() {
  testWidgets(
    'document command bar stays compact on phone and exposes actions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(
              body: NineSoftDocumentCommandBar(
                actions: [
                  NineSoftDocumentCommandAction(
                    key: const ValueKey('command-one'),
                    label: 'بحث عن صنف',
                    shortcut: 'F3',
                    icon: Icons.search_rounded,
                    color: const Color(0xFF1594E8),
                    onPressed: () {},
                  ),
                  NineSoftDocumentCommandAction(
                    key: const ValueKey('command-two'),
                    label: 'تطبيق خصم',
                    shortcut: 'F5',
                    icon: Icons.sell_rounded,
                    color: const Color(0xFF18AA55),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('document-command-bar')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('command-one')), findsOneWidget);
      expect(find.text('F3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('document type switch identifies receipt payment and journal', (
    tester,
  ) async {
    var selected = 'receipt';
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: NineSoftDocumentTypeSwitch(
              value: selected,
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('document-type-receipt')), findsOneWidget);
    expect(find.byKey(const ValueKey('document-type-payment')), findsOneWidget);
    expect(find.byKey(const ValueKey('document-type-journal')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('document-type-payment')));
    await tester.pump();
    expect(selected, 'payment');
  });

  test(
    'sales purchase and voucher editors expose the unified visual hooks',
    () {
      final sales = File(
        'lib/src/features/invoices/invoice_workspace_page.dart',
      ).readAsStringSync();
      final purchases = File(
        'lib/src/features/purchases/purchase_workspace_page.dart',
      ).readAsStringSync();
      final vouchers = File(
        'lib/src/features/modules/module_workspace_page.dart',
      ).readAsStringSync();

      expect(sales, contains('NineSoftDocumentCommandBar'));
      expect(purchases, contains('NineSoftDocumentCommandBar'));
      expect(purchases, contains("ValueKey('purchase-command-add-line')"));
      expect(vouchers, contains('NineSoftDocumentTypeSwitch'));
      expect(vouchers, contains("ValueKey('voucher-document-shell')"));
    },
  );
}
