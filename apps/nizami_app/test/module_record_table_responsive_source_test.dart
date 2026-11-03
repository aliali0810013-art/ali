import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'module record table uses responsive flex layout without inner scroll',
    () {
      final source = File(
        'lib/src/features/modules/module_workspace_page.dart',
      ).readAsStringSync();
      final start = source.indexOf('class _RecordTable');
      final end = source.indexOf('class _RecordCard', start);

      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final recordTable = source.substring(start, end);

      expect(
        source,
        contains("import '../../theme/ninesoft_financial_ui.dart';"),
      );
      expect(recordTable, contains('NineSoftResponsiveFinancialTable('));
      expect(recordTable, contains('NineSoftFinancialRow('));
      expect(recordTable, isNot(contains('DataTable(')));
      expect(recordTable, isNot(contains('Axis.horizontal')));
    },
  );
}
