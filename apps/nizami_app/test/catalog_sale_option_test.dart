import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nizami/src/features/invoices/invoice_pdf_service.dart';
import 'package:nizami/src/features/products/product_catalog_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'server-imported product remains without generated price or barcode',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = ProductCatalogStore('tenant-a');
      final saved = await store.save(
        const CatalogProduct(
          id: 'server-product-id',
          name: 'زبيب يمني',
          purchasePrice: 0,
          salePrice: 0,
          barcode: '',
          category: 'الأغذية اليمنية',
          subcategory: 'الزبيب',
          hasPurchasePrice: false,
          hasSalePrice: false,
        ),
      );

      expect(saved.barcode, isEmpty);
      expect(saved.hasPurchasePrice, isFalse);
      expect(saved.hasSalePrice, isFalse);
      expect((await store.read()).single.subcategory, 'الزبيب');
    },
  );

  test('invoice line preserves its independent sale-option snapshot', () {
    const line = InvoiceLine(
      name: 'زبيب يمني',
      quantity: 3,
      unitPrice: 200,
      productId: 'product-1',
      saleOptionId: 'option-100g',
      optionUnitCode: 'gram',
      optionQuantity: 100,
      optionMassG: 100,
    );
    final restored = InvoiceLine.fromJson(line.toJson());

    expect(restored.saleOptionId, 'option-100g');
    expect(restored.optionMassG, 100);
    expect(restored.total, 600);
    expect(restored.displayName, contains('100 جرام'));
  });
}
