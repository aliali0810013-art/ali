import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/theme/ninesoft_financial_ui.dart';

void main() {
  test('compactDocumentNumber keeps the meaningful trailing reference', () {
    expect(compactDocumentNumber('INV-20261031-000003'), '#3');
    expect(compactDocumentNumber('PUR-100'), '#100');
    expect(compactDocumentNumber('MANUAL-REFERENCE'), '#REFERENCE');
    expect(
      compactDocumentNumber('A-VERY-LONG-NONNUMERIC-REFERENCE'),
      '#…REFERENCE',
    );
  });

  group('NineSoftFinancialSummaryStrip', () {
    testWidgets('uses four wide columns and preserves preformatted values', (
      tester,
    ) async {
      await _setSurface(tester, const Size(900, 700));
      await tester.pumpWidget(_app(summary: _summary()));

      final first = tester.getTopLeft(find.byKey(const Key('summary-0')));
      final fourth = tester.getTopLeft(find.byKey(const Key('summary-3')));
      expect(first.dy, fourth.dy);
      expect(find.text('9,999,999,999,999 د.ع'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses two phone columns without overflow', (tester) async {
      await _setSurface(tester, const Size(390, 900));
      await tester.pumpWidget(_app(summary: _summary()));

      final first = tester.getTopLeft(find.byKey(const Key('summary-0')));
      final second = tester.getTopLeft(find.byKey(const Key('summary-1')));
      final third = tester.getTopLeft(find.byKey(const Key('summary-2')));
      expect(first.dy, second.dy);
      expect(third.dy, greaterThan(first.dy));
      expect(find.text('9,999,999,999,999 د.ع'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('NineSoftResponsiveFinancialTable', () {
    testWidgets('renders a flex table at 900 without horizontal scrolling', (
      tester,
    ) async {
      await _setSurface(tester, const Size(900, 900));
      await tester.pumpWidget(_app(table: _table()));

      expect(
        find.byKey(const Key('ninesoft-financial-table-desktop')),
        findsOneWidget,
      );
      expect(find.byType(DataTable), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders tappable cards at 390 without overflow', (
      tester,
    ) async {
      var taps = 0;
      await _setSurface(tester, const Size(390, 1000));
      await tester.pumpWidget(_app(table: _table(onTap: () => taps++)));

      expect(
        find.byKey(const Key('ninesoft-financial-table-mobile')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('financial-row')), findsOneWidget);
      await tester.tap(find.byKey(const Key('financial-row')));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the supplied empty description', (tester) async {
      await tester.pumpWidget(
        _app(
          table: const NineSoftResponsiveFinancialTable(
            columns: [NineSoftFinancialColumn(label: 'المستند')],
            rows: [],
            emptyDescription: 'لا توجد حركات مالية لهذه الفترة.',
          ),
        ),
      );

      expect(find.text('لا توجد حركات مالية لهذه الفترة.'), findsOneWidget);
    });
  });
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _app({Widget? summary, Widget? table}) => MaterialApp(
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(12),
      child: summary ?? table ?? const SizedBox.shrink(),
    ),
  ),
);

NineSoftFinancialSummaryStrip _summary() => const NineSoftFinancialSummaryStrip(
  items: [
    NineSoftFinancialSummaryItem(
      key: Key('summary-0'),
      label: 'الإجمالي',
      value: '9,999,999,999,999 د.ع',
      icon: Icons.account_balance_wallet_rounded,
    ),
    NineSoftFinancialSummaryItem(
      key: Key('summary-1'),
      label: 'المدفوع',
      value: '750,000 د.ع',
      icon: Icons.payments_rounded,
    ),
    NineSoftFinancialSummaryItem(
      key: Key('summary-2'),
      label: 'المتبقي',
      value: '250,000 د.ع',
      icon: Icons.schedule_rounded,
    ),
    NineSoftFinancialSummaryItem(
      key: Key('summary-3'),
      label: 'الحالة',
      value: 'مرحل',
      icon: Icons.verified_rounded,
    ),
  ],
);

NineSoftResponsiveFinancialTable _table({VoidCallback? onTap}) =>
    NineSoftResponsiveFinancialTable(
      columns: const [
        NineSoftFinancialColumn(label: 'المستند', flex: 2),
        NineSoftFinancialColumn(label: 'القيمة', flex: 2),
        NineSoftFinancialColumn(
          label: 'الحالة',
          alignment: AlignmentDirectional.center,
        ),
      ],
      rows: [
        NineSoftFinancialRow(
          key: const Key('financial-row'),
          onTap: onTap,
          cells: const [
            Tooltip(message: 'INV-20261031-000003', child: Text('#3')),
            Text('9,999,999,999,999 د.ع'),
            Icon(Icons.verified_rounded),
          ],
        ),
      ],
      emptyDescription: 'لا توجد حركات.',
    );
