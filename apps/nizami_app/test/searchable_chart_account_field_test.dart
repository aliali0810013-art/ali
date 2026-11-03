import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/accounting/chart_accounts_api.dart';
import 'package:nizami/src/features/accounting/searchable_chart_account_field.dart';

void main() {
  const accounts = [
    ChartAccount(
      id: 'cash-main',
      code: 'LIQUID-001-1060',
      nameAr: 'الصندوق الرئيسي',
      type: 'asset',
      normalBalance: 'debit',
      balanceMinor: 0,
    ),
    ChartAccount(
      id: 'cash-branch',
      code: 'LIQUID-002-1060',
      nameAr: 'صندوق الكاشير',
      type: 'asset',
      normalBalance: 'debit',
      balanceMinor: 0,
    ),
  ];

  testWidgets('searches accounts inline without opening a modal', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SearchableChartAccountField(
              accounts: accounts,
              value: selected,
              label: 'الحساب',
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    await tester.tap(find.text('اختر الحساب'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inline-account-search')), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.enterText(find.byType(TextField), 'الرئيسي');
    await tester.pumpAndSettle();

    expect(find.text('الصندوق الرئيسي'), findsOneWidget);
    expect(find.text('LIQUID-001-1060'), findsOneWidget);
    expect(find.text('صندوق الكاشير'), findsNothing);

    await tester.tap(find.text('الصندوق الرئيسي'));
    await tester.pumpAndSettle();
    expect(selected, 'LIQUID-001-1060');
    expect(find.text('الصندوق الرئيسي'), findsOneWidget);
    expect(find.text('LIQUID-001-1060'), findsOneWidget);
  });
}
