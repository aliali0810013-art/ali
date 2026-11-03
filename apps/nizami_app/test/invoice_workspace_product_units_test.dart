import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/accounting/chart_accounts_api.dart';
import 'package:nizami/src/features/invoices/invoice_workspace_page.dart';
import 'package:nizami/src/features/modules/catalog_sync_api.dart';
import 'package:nizami/src/features/products/product_catalog_store.dart';
import 'package:nizami/src/features/products/product_sale_option_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'previously synchronized unit profile is selectable offline and durable delta refreshes it',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog = ProductCatalogStore('tenant-a');
      await catalog.save(
        const CatalogProduct(
          id: 'product-a',
          name: 'Rice',
          purchasePrice: 4,
          salePrice: 5,
          barcode: 'RICE-1',
          unitName: 'gram',
        ),
      );
      final store = ProductSaleOptionStore('tenant-a', 'branch-a');
      await store.replaceSnapshot([_option(version: 1, numerator: 500000)]);
      final events = StreamController<Set<String>>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(
        MaterialApp(
          builder: _compactTestText,
          home: InvoiceWorkspacePage(
            branchIds: const ['branch-a'],
            tenantName: 'Tenant A',
            tenantId: 'tenant-a',
            employeeName: 'Owner',
            token: 'offline',
            roleCode: 'owner',
            permissions: const ['catalog.read', 'catalog.write'],
            catalogApi: CatalogSyncApi(
              token: 'offline',
              transport: _OfflineTransport(),
            ),
            chartAccountsLoader: (_) async => [_cashAccount],
            identityLoader: (_, _) async {},
            syncChanges: events.stream,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('invoice-product-input')),
        'Rice',
      );
      await tester.pump();
      await tester.tap(find.text('Rice').last);
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const Key('invoice-sale-option-gram-v1'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('empty-option')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(_option(version: 1, numerator: 500000).label).last,
      );
      await tester.pumpAndSettle();

      await store.applyRemoteChange('gram', 'upsert', {
        ..._option(version: 2, numerator: 525000).toJson(),
        'version': '2',
        'price_numerator_minor': '525000',
        'price_denominator': '1000',
      });
      events.add({'product_sale_option'});
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('gram')),
            )
            .initialValue,
        'gram',
      );

      expect(
        find.byKey(
          const Key('invoice-sale-option-gram-v2'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    },
  );

  test('unit barcode lookup resolves one cache snapshot directly', () async {
    final store = ProductSaleOptionStore('tenant-a', 'branch-a');
    final options = <ProductSaleOption>[
      for (var index = 0; index < 1500; index++)
        ProductSaleOption.fromJson({
          'id': 'option-$index',
          'tenant_id': 'tenant-a',
          'branch_id': 'branch-a',
          'product_id': 'product-$index',
          'identity_key': 'piece:$index',
          'unit_code': 'piece',
          'quantity_per_option': '1',
          'option_price_minor': 100,
          'price_numerator_minor': '100',
          'price_denominator': '1',
          'unit_barcode': index == 1499 ? 'TARGET-UNIT' : 'UNIT-$index',
          'version': '1',
        }),
    ];
    await store.replaceSnapshot(options);

    final found = await store.findByUnitBarcode(' TARGET-UNIT ');

    expect(found?.id, 'option-1499');
    expect(found?.productId, 'product-1499');
  });

  testWidgets('local stock line stays visibly pending canonical sync', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: _compactTestText,
        home: InvoiceWorkspacePage(
          branchIds: const ['branch-a'],
          tenantName: 'Tenant A',
          tenantId: 'tenant-a',
          employeeName: 'Owner',
          token: 'offline',
          roleCode: 'owner',
          permissions: const ['catalog.read', 'catalog.write'],
          catalogApi: CatalogSyncApi(
            token: 'offline',
            transport: _OfflineTransport(),
          ),
          chartAccountsLoader: (_) async => [_cashAccount],
          identityLoader: (_, _) async {},
          syncChanges: const Stream.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('invoice-product-input')),
      'Offline stock',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('invoice-quantity-input')),
      '1',
    );
    await tester.enterText(find.byKey(const Key('invoice-price-input')), '10');
    await tester.tap(find.byKey(const Key('invoice-add-line')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('invoice-line-pending-catalog-0')),
      findsOneWidget,
    );
    expect(await ProductCatalogStore('tenant-a').read(), hasLength(1));
    expect((await ProductCatalogStore('tenant-a').read()).single.id, isEmpty);
  });
}

Widget _compactTestText(BuildContext context, Widget? child) => MediaQuery(
  data: MediaQuery.of(
    context,
  ).copyWith(textScaler: const TextScaler.linear(0.5)),
  child: child!,
);

ProductSaleOption _option({required int version, required int numerator}) =>
    ProductSaleOption.fromJson({
      'id': 'gram',
      'tenant_id': 'tenant-a',
      'branch_id': 'branch-a',
      'product_id': 'product-a',
      'identity_key': 'mass:gram:1',
      'unit_code': 'gram',
      'quantity_per_option': '1',
      'option_price_minor': 500,
      'price_numerator_minor': '$numerator',
      'price_denominator': '1000',
      'is_derived': true,
      'version': '$version',
    });

const _cashAccount = ChartAccount(
  id: 'cash-id',
  code: '1110-CASH',
  nameAr: 'Cash',
  type: 'asset',
  normalBalance: 'debit',
  balanceMinor: 0,
  isCashEquivalent: true,
);

class _OfflineTransport implements JsonTransport {
  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) => throw StateError('offline');
}
