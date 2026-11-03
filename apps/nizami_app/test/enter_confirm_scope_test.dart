import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/theme/ninesoft_confirm_shortcuts.dart';

void main() {
  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('Enter accepts a confirmation dialog', (tester) async {
    var accepted = false;

    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (dialogContext) => NineSoftEnterConfirmScope(
                  onConfirm: () {
                    accepted = true;
                    Navigator.pop(dialogContext);
                  },
                  child: const AlertDialog(
                    title: Text('تأكيد'),
                    content: Text('هل أنت متأكد؟'),
                  ),
                ),
              );
            },
            child: const Text('فتح'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(accepted, isTrue);
    expect(find.text('هل أنت متأكد؟'), findsNothing);
  });

  testWidgets('Enter in a multiline field inserts text without confirming', (
    tester,
  ) async {
    var accepted = false;
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      app(
        NineSoftEnterConfirmScope(
          onConfirm: () => accepted = true,
          child: AlertDialog(
            content: TextField(
              key: const Key('notes'),
              controller: controller,
              autofocus: true,
              maxLines: 3,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('notes')), 'سطر');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(accepted, isFalse);
  });

  test('critical confirmations use the shared Enter shortcut scope', () {
    const files = <String>[
      'lib/src/features/administration/administration_page.dart',
      'lib/src/features/accounting/accounting_periods_page.dart',
      'lib/src/features/accounting/simple_journal_page.dart',
      'lib/src/features/accounting/opening_balances_page.dart',
      'lib/src/features/backup/backup_page.dart',
      'lib/src/features/payroll/employee_payroll_page.dart',
      'lib/src/features/whatsapp/whatsapp_page.dart',
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('NineSoftEnterConfirmScope('),
        reason: '$path must support Enter on its confirmation dialog',
      );
    }
  });
}
