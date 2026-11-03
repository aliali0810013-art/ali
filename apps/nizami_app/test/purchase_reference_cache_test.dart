import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nizami/src/features/purchases/purchase_reference_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('offline directory persists selected supplier ID and name', () async {
    final store = PurchaseReferenceCache('tenant-a', 'branch-1');
    await store.write('suppliers', [
      {'id': 'supplier-id-1', 'name': 'مورد', 'phone': '777'},
    ]);
    final offline = await PurchaseReferenceCache('tenant-a', 'branch-1')
        .read('suppliers');
    expect(offline, hasLength(1));
    expect(offline.single['id'], 'supplier-id-1');
  });

  test('offline reference snapshots are isolated by tenant and branch', () async {
    await PurchaseReferenceCache('tenant-a', 'branch-1').write('products', [
      {'id': 'product-a', 'name': 'منتج'},
    ]);
    expect(await PurchaseReferenceCache('tenant-b', 'branch-1')
        .read('products'), isEmpty);
    expect(await PurchaseReferenceCache('tenant-a', 'branch-2')
        .read('products'), isEmpty);
  });
}
