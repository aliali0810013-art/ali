import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nizami/src/features/products/product_catalog_store.dart';
import 'package:nizami/src/features/customers/customer_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'offline product gets collision-safe temporary barcode and keeps it',
    () async {
      final a = ProductCatalogStore('tenant-a');
      final p1 = await a.save(
        const CatalogProduct(
          name: 'صنف جديد',
          purchasePrice: 80,
          salePrice: 100,
          barcode: '',
        ),
      );
      expect(p1.barcode, startsWith('LOCAL-'));
      final updated = await a.save(
        const CatalogProduct(
          name: 'صنف جديد',
          purchasePrice: 0,
          salePrice: 110,
          barcode: '',
        ),
      );
      expect(updated.barcode, p1.barcode);
      expect(updated.purchasePrice, 80);
      final p2 = await a.save(
        const CatalogProduct(
          name: 'صنف آخر',
          purchasePrice: 1,
          salePrice: 2,
          barcode: '',
        ),
      );
      expect(p2.barcode, startsWith('LOCAL-'));
      expect(p2.barcode, isNot(p1.barcode));
      expect(await ProductCatalogStore('tenant-b').read(), isEmpty);
    },
  );

  test(
    'customer name and phone are reusable without duplicating the client',
    () async {
      final store = CustomerStore('tenant-a');
      await store.save('أحمد عبدالله', '777123456');
      await store.save('أحمد عبدالله', '777654321');
      final records = await store.read();
      expect(records.length, 1);
      expect(records.first.phone, '777654321');
      expect(await CustomerStore('tenant-b').read(), isEmpty);
    },
  );
}
