import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/accounting/product_inquiry_page.dart';

void main() {
  testWidgets(
    'product inventory result stays readable without horizontal scroll',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProductInquiryResultCard(
                item: {
                  'name': 'صنف طويل الاسم لاختبار شاشة الهاتف الصغيرة',
                  'sku': 'SKU-123456789',
                  'barcode': '12345678901234567890',
                  'unit_name': 'كيلوجرام',
                  'quantity_milli': 12500,
                  'warehouses': [
                    {
                      'branch_name': 'المستودع الرئيسي طويل الاسم',
                      'quantity_milli': 12500,
                    },
                  ],
                  'last_purchase': {
                    'invoice_number': 'PUR-20261101-000001',
                    'supplier_name': 'مورد ذو اسم طويل لاختبار الالتفاف',
                    'occurred_at': '2026-11-01T10:00:00Z',
                    'unit_price_minor': 500000,
                    'net_unit_price_minor': 480000,
                  },
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(DataTable), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
      );
      expect(find.textContaining('12.500'), findsWidgets);
    },
  );
}
