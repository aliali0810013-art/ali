import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('purchase editor exposes package conversion and sends it to API', () {
    final source = File(
      'lib/src/features/purchases/purchase_workspace_page.dart',
    ).readAsStringSync();

    expect(source, contains("'unit_name': line.unitName"));
    expect(source, contains("'purchase_unit_name': line.purchaseUnitName"));
    expect(source, contains("'units_per_package_milli'"));
    expect(source, contains("labelText: 'وحدة الشراء'"));
    expect(source, contains("'محتوى وحدة الشراء'"));
  });

  test('purchase history exposes edit and final delete actions', () {
    final source = File(
      'lib/src/features/purchases/purchase_workspace_page.dart',
    ).readAsStringSync();

    expect(source, contains("label: const Text('تعديل')"));
    expect(source, contains("label: const Text('حذف نهائي')"));
    expect(source, contains('initialInvoice: invoice'));
    expect(source, contains('_accounting.replacePurchase('));
  });
}
