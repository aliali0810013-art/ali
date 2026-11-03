import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nizami/src/features/customers/customer_store.dart';
import 'package:nizami/src/features/products/product_catalog_store.dart';
import 'package:nizami/src/features/invoices/invoice_history_store.dart';
import 'package:nizami/src/features/invoices/invoice_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'identical company display names with distinct UUIDs cannot share the new caches',
    () async {
      const firstTenant = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      const secondTenant = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      final productsA = ProductCatalogStore(firstTenant);
      await productsA.save(
        const CatalogProduct(
          name: 'منتج تجريبي',
          purchasePrice: 10,
          salePrice: 20,
          barcode: '',
        ),
      );
      await CustomerStore(firstTenant).save('عميل خاص', '777000000');
      expect(await ProductCatalogStore(secondTenant).read(), isEmpty);
      expect(await CustomerStore(secondTenant).read(), isEmpty);

      final invoices = InvoiceHistoryStore();
      await invoices.save(
        firstTenant,
        'branch-a',
        InvoiceDocument(
          number: 'LOCAL-TEST-1',
          customerName: 'عميل خاص',
          customerPhone: '777000000',
          lines: [
            const InvoiceLine(name: 'منتج تجريبي', quantity: 1, unitPrice: 20),
          ],
          currency: 'YER',
          employeeName: 'مختبر',
          branchLabel: 'فرع 1',
          createdAt: DateTime(2026, 10, 15),
        ),
      );
      expect(await invoices.read(secondTenant, 'branch-a'), isEmpty);
      expect(await invoices.read(firstTenant, 'branch-b'), isEmpty);
      expect(
        (await invoices.read(firstTenant, 'branch-a')).single.number,
        'LOCAL-TEST-1',
      );
    },
  );

  test('editing an existing product price keeps its serial barcode', () async {
    final store = ProductCatalogStore('tenant-id');
    final original = await store.save(
      const CatalogProduct(
        name: 'قلم',
        purchasePrice: 10,
        salePrice: 15,
        barcode: '',
      ),
    );
    final changed = await store.save(
      CatalogProduct(
        name: original.name,
        purchasePrice: 0,
        salePrice: 19,
        barcode: '',
      ),
    );
    expect(changed.barcode, original.barcode);
    expect(changed.salePrice, 19);
    expect(changed.purchasePrice, 10);
    expect((await store.read()).length, 1);
  });
}
