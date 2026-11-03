import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nizami/src/features/customers/customer_store.dart';
import 'package:nizami/src/features/products/product_catalog_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'same event ID is applied once; update then delete has no ghosts',
    () async {
      final store = ProductCatalogStore('tenant-x');
      final payload = <String, dynamic>{
        'name': 'رز',
        'barcode': 'R-1',
        'kind': 'stock',
        'unit_name': '25 كجم',
        'sale_price_minor': 12000,
        'purchase_price_minor': 5000,
      };
      await store.applyRemoteChange('server-1', 'upsert', payload);
      await store.applyRemoteChange('server-1', 'upsert', payload);
      expect((await store.read()).length, 1);
      await store.applyRemoteChange('server-1', 'upsert', {
        ...payload,
        'name': 'رز ممتاز',
        'sale_price_minor': 13000,
      });
      expect((await store.read()).single.name, 'رز ممتاز');
      expect((await store.read()).single.unitName, '25 كجم');
      expect((await store.read()).single.salePrice, 130);
      await store.applyRemoteChange('server-1', 'delete', payload);
      expect(await store.read(), isEmpty);
    },
  );

  test(
    'full snapshot removes deleted server records but keeps offline drafts',
    () async {
      final store = ProductCatalogStore('tenant-y');
      await store.save(
        const CatalogProduct(
          name: 'محلي غير مرسل',
          barcode: 'LOCAL-1',
          purchasePrice: 0,
          salePrice: 10,
        ),
      );
      await store.applyRemoteChange('server-2', 'upsert', {
        'name': 'قديم',
        'barcode': 'T-2',
        'kind': 'stock',
        'sale_price_minor': 20,
        'purchase_price_minor': 0,
      });
      await store.replaceRemoteSnapshot(const []);
      final remaining = await store.read();
      expect(remaining.length, 1);
      expect(remaining.single.name, 'محلي غير مرسل');
    },
  );

  test('contact type transitions do not duplicate customers', () async {
    final store = CustomerStore('tenant-z');
    final payload = {'name': 'علي', 'phone': '777', 'type': 'customer'};
    await store.applyRemoteChange('contact-1', 'upsert', payload);
    await store.applyRemoteChange('contact-1', 'upsert', {
      ...payload,
      'phone': '778',
    });
    expect((await store.read()).single.phone, '778');
    await store.applyRemoteChange('contact-1', 'upsert', {
      ...payload,
      'type': 'supplier',
    });
    expect(await store.read(), isEmpty);
    await store.applyRemoteChange('contact-1', 'upsert', {
      ...payload,
      'type': 'both',
    });
    expect((await store.read()).single.id, 'contact-1');
  });
}
