import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/modules/catalog_sync_api.dart';
import 'package:nizami/src/features/products/product_sale_option_store.dart';
import 'package:nizami/src/features/sync/realtime_sync_coordinator.dart';
import 'package:nizami/src/features/sync/restore_snapshot_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProductSaleOption option({
    required String id,
    required String tenant,
    required String product,
    String? branch,
    required String identity,
    required String unit,
    required int numerator,
    required int denominator,
    int previewMinor = 0,
    bool derived = false,
  }) => ProductSaleOption.fromJson({
    'id': id,
    'tenant_id': tenant,
    'branch_id': branch,
    'product_id': product,
    'identity_key': identity,
    'unit_code': unit,
    'quantity_per_option': '1',
    'option_price_minor': previewMinor,
    'price_numerator_minor': numerator,
    'price_denominator': denominator,
    'unit_barcode': '$id-barcode',
    'is_derived': derived,
    'version': 1,
  });

  test('snapshot replacement persists exact fields across restart', () async {
    final store = ProductSaleOptionStore('tenant-a', 'branch-a');
    await store.replaceSnapshot([
      option(
        id: 'gram',
        tenant: 'tenant-a',
        product: 'rice',
        identity: 'mass:gram:1',
        unit: 'gram',
        numerator: 500000,
        denominator: 1000,
        previewMinor: 500,
        derived: true,
      ),
    ]);

    final restored = await ProductSaleOptionStore(
      'tenant-a',
      'branch-a',
    ).readProduct('rice');
    expect(restored, hasLength(1));
    expect(restored.single.productId, 'rice');
    expect(restored.single.priceNumeratorMinor, 500000);
    expect(restored.single.priceDenominator, 1000);
    expect(restored.single.price, 5); // Legacy display compatibility only.
    expect(restored.single.unitBarcode, 'gram-barcode');
    expect(restored.single.isDerived, isTrue);
  });

  test('fractional exact price components are rejected, not truncated', () {
    expect(
      () => ProductSaleOption.fromJson({
        'id': 'fractional',
        'tenant_id': 'tenant-a',
        'product_id': 'rice',
        'unit_code': 'gram',
        'quantity_per_option': 1,
        'option_price_minor': 500,
        'price_numerator_minor': 500000.5,
        'price_denominator': 1000,
      }),
      throwsFormatException,
    );
  });

  test(
    'authoritative integers reject every double and noncanonical string',
    () {
      Map<String, dynamic> row() => {
        'id': 'strict',
        'tenant_id': 'tenant-a',
        'product_id': 'rice',
        'unit_code': 'gram',
        'quantity_per_option': '1',
        'option_price_minor': 500,
        'price_numerator_minor': '500000',
        'price_denominator': '1000',
        'version': '1',
      };

      for (final invalid in <({String field, Object value})>[
        (field: 'price_numerator_minor', value: 500000.0),
        (field: 'price_denominator', value: 1000.0),
        (field: 'version', value: 1.0),
        (field: 'id', value: 7.0),
        (field: 'product_id', value: 9.0),
        (field: 'price_numerator_minor', value: '0500000'),
        (field: 'price_denominator', value: '1e3'),
        (field: 'version', value: '9007199254740992'),
      ]) {
        expect(
          () => ProductSaleOption.fromJson({
            ...row(),
            invalid.field: invalid.value,
          }),
          throwsFormatException,
          reason: '${invalid.field} accepted ${invalid.value}',
        );
      }

      final parsed = ProductSaleOption.fromJson(row());
      expect(parsed.priceNumeratorMinor, 500000);
      expect(parsed.priceDenominator, 1000);
      expect(parsed.version, 1);
    },
  );

  test(
    'branch option deterministically overrides matching global identity',
    () async {
      final store = ProductSaleOptionStore('tenant-a', 'branch-a');
      await store.replaceSnapshot([
        option(
          id: 'global-kg',
          tenant: 'tenant-a',
          product: 'rice',
          identity: 'mass:kilogram:1',
          unit: 'kilogram',
          numerator: 500000,
          denominator: 1,
          previewMinor: 500000,
        ),
        option(
          id: 'branch-kg',
          tenant: 'tenant-a',
          product: 'rice',
          branch: 'branch-a',
          identity: 'mass:kilogram:1',
          unit: 'kilogram',
          numerator: 525000,
          denominator: 1,
          previewMinor: 525000,
        ),
        option(
          id: 'global-gram',
          tenant: 'tenant-a',
          product: 'rice',
          identity: 'mass:gram:1',
          unit: 'gram',
          numerator: 500000,
          denominator: 1000,
          previewMinor: 500,
          derived: true,
        ),
      ]);

      final values = await store.readProduct('rice');
      expect(values.map((value) => value.id), ['global-gram', 'branch-kg']);
    },
  );

  test('remote delete is durable and does not return after restart', () async {
    final store = ProductSaleOptionStore('tenant-a', 'branch-a');
    await store.replaceSnapshot([
      option(
        id: 'option-1',
        tenant: 'tenant-a',
        product: 'rice',
        identity: 'count:piece:1',
        unit: 'piece',
        numerator: 10000,
        denominator: 1,
        previewMinor: 10000,
      ),
    ]);
    await store.applyRemoteChange('option-1', 'delete', const {
      'id': 'option-1',
    });

    expect(
      await ProductSaleOptionStore('tenant-a', 'branch-a').readProduct('rice'),
      isEmpty,
    );
  });

  test(
    'tenant and branch scopes never leak and invalid refresh keeps cache',
    () async {
      final branchA = ProductSaleOptionStore('tenant-a', 'branch-a');
      await branchA.replaceSnapshot([
        option(
          id: 'safe',
          tenant: 'tenant-a',
          product: 'rice',
          identity: 'count:piece:1',
          unit: 'piece',
          numerator: 10000,
          denominator: 1,
          previewMinor: 10000,
        ),
      ]);

      expect(
        await ProductSaleOptionStore(
          'tenant-a',
          'branch-b',
        ).readProduct('rice'),
        isEmpty,
      );
      expect(
        await ProductSaleOptionStore(
          'tenant-b',
          'branch-a',
        ).readProduct('rice'),
        isEmpty,
      );
      await expectLater(
        branchA.replaceSnapshot([
          option(
            id: 'foreign',
            tenant: 'tenant-b',
            product: 'rice',
            identity: 'count:piece:1',
            unit: 'piece',
            numerator: 20000,
            denominator: 1,
          ),
        ]),
        throwsStateError,
      );
      await expectLater(
        branchA.replaceSnapshot([
          ProductSaleOption.fromJson({
            'id': 'unscoped',
            'product_id': 'rice',
            'identity_key': 'count:piece:1',
            'unit_code': 'piece',
            'quantity_per_option': 1,
            'option_price_minor': 10000,
            'price_numerator_minor': 10000,
            'price_denominator': 1,
          }),
        ]),
        throwsStateError,
      );
      expect((await branchA.readProduct('rice')).single.id, 'safe');
    },
  );

  test('paginated option bootstrap reads every Laravel page', () async {
    final transport = _SnapshotTransport([
      const JsonResponse(
        statusCode: 200,
        body:
            '{"data":[{"id":"one","tenant_id":"tenant-a","product_id":"rice","unit_code":"gram","quantity_per_option":"1","option_price_minor":500,"price_numerator_minor":500000,"price_denominator":1000,"is_derived":true}],"current_page":1,"last_page":2}',
      ),
      const JsonResponse(
        statusCode: 200,
        body:
            '{"data":[{"id":"two","tenant_id":"tenant-a","branch_id":"branch-a","product_id":"rice","unit_code":"kilogram","quantity_per_option":"1","option_price_minor":500000,"price_numerator_minor":500000,"price_denominator":1,"is_derived":false}],"current_page":2,"last_page":2}',
      ),
    ]);
    final api = CatalogSyncApi(token: 'test', transport: transport);

    final values = await api.productSaleOptionSnapshot(branchId: 'branch-a');

    expect(values.map((value) => value.id), ['one', 'two']);
    expect(transport.uris.map((uri) => uri.queryParameters['page']), [
      '1',
      '2',
    ]);
    for (final body in transport.responseBodies) {
      expect(jsonDecode(body), isA<Map>());
    }
  });

  test('product option refresh rejects a partial malformed response', () async {
    final api = CatalogSyncApi(
      token: 'test',
      transport: _ProductOptionsTransport(
        const JsonResponse(
          statusCode: 200,
          body:
              '{"data":[{"id":"one","tenant_id":"tenant-a","product_id":"rice","unit_code":"gram","quantity_per_option":"1","option_price_minor":500,"price_numerator_minor":500000,"price_denominator":1000},false]}',
        ),
      ),
    );

    await expectLater(
      api.saleOptions('rice', branchId: 'branch-a'),
      throwsFormatException,
    );
  });

  test('paginated snapshot rejects malformed rows and metadata', () async {
    for (final body in <String>[
      '{"data":[{"id":"one"},7],"current_page":1,"last_page":1}',
      '{"data":[]}',
      '{"data":[],"current_page":2,"last_page":1}',
      '{"data":[],"current_page":1.0,"last_page":1}',
      '{"data":[],"current_page":"01","last_page":"1"}',
    ]) {
      final api = CatalogSyncApi(
        token: 'test',
        transport: _SnapshotTransport([
          JsonResponse(statusCode: 200, body: body),
        ]),
      );
      await expectLater(
        api.productSaleOptionSnapshot(branchId: 'branch-a'),
        throwsFormatException,
        reason: body,
      );
    }
  });

  test('malformed later page retains the complete prior cache', () async {
    final store = ProductSaleOptionStore('tenant-a', 'branch-a');
    await store.replaceSnapshot([
      option(
        id: 'cached',
        tenant: 'tenant-a',
        product: 'rice',
        identity: 'count:piece:1',
        unit: 'piece',
        numerator: 10000,
        denominator: 1,
      ),
    ]);
    final api = CatalogSyncApi(
      token: 'test',
      transport: _SnapshotTransport([
        const JsonResponse(
          statusCode: 200,
          body:
              '{"data":[{"id":"new","tenant_id":"tenant-a","product_id":"rice","unit_code":"gram","quantity_per_option":"1","option_price_minor":500,"price_numerator_minor":"500000","price_denominator":"1000","version":"1"}],"current_page":1,"last_page":2}',
        ),
        const JsonResponse(
          statusCode: 200,
          body: '{"data":[false],"current_page":2,"last_page":2}',
        ),
      ]),
    );

    expect(
      await refreshProductSaleOptionCache(
        api: api,
        store: store,
        branchId: 'branch-a',
      ),
      isFalse,
    );
    expect((await store.readProduct('rice')).single.id, 'cached');
  });

  test(
    'offline refresh failure retains the last valid cached options',
    () async {
      final store = ProductSaleOptionStore('tenant-a', 'branch-a');
      await store.replaceSnapshot([
        option(
          id: 'cached',
          tenant: 'tenant-a',
          product: 'rice',
          identity: 'count:piece:1',
          unit: 'piece',
          numerator: 10000,
          denominator: 1,
        ),
      ]);
      final refreshed = await refreshProductSaleOptionCache(
        api: CatalogSyncApi(token: 'test', transport: _OfflineTransport()),
        store: store,
        branchId: 'branch-a',
      );

      expect(refreshed, isFalse);
      expect((await store.readProduct('rice')).single.id, 'cached');
    },
  );

  test(
    'restore snapshot atomically replaces option cache when included',
    () async {
      final store = ProductSaleOptionStore('tenant-a', 'branch-a');
      await store.replaceSnapshot([
        option(
          id: 'before-restore',
          tenant: 'tenant-a',
          product: 'rice',
          identity: 'count:piece:1',
          unit: 'piece',
          numerator: 10000,
          denominator: 1,
        ),
      ]);
      final snapshotStore = RestoreSnapshotStore(
        RestoreSnapshotScope(
          tenantId: 'tenant-a',
          userId: 'owner-a',
          roleCode: 'owner',
          restoreGeneration: 4,
          branchIds: const ['branch-a'],
          permissions: const ['catalog.read'],
        ),
      );
      await snapshotStore.stage({
        'snapshot_cursor': 40,
        'restore_generation': 4,
        'branch_ids': ['branch-a'],
        'products': <Object?>[],
        'contacts': <Object?>[],
        'invoices': <Object?>[],
        'purchase_invoices': <Object?>[],
        'business_documents': <Object?>[],
        'product_sale_options': [
          option(
            id: 'after-restore',
            tenant: 'tenant-a',
            product: 'rice',
            branch: 'branch-a',
            identity: 'count:piece:1',
            unit: 'piece',
            numerator: 12000,
            denominator: 1,
          ).toJson(),
        ],
      });

      await snapshotStore.resume();

      expect((await store.readProduct('rice')).single.id, 'after-restore');
    },
  );
}

class _SnapshotTransport implements JsonTransport {
  _SnapshotTransport(this.responses);

  final List<JsonResponse> responses;
  final List<Uri> uris = [];
  final List<String> responseBodies = [];

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    expect(method, 'GET');
    expect(uri.path, endsWith('/catalog/product-sale-options'));
    uris.add(uri);
    final response = responses.removeAt(0);
    responseBodies.add(response.body);
    return response;
  }
}

class _ProductOptionsTransport implements JsonTransport {
  _ProductOptionsTransport(this.response);

  final JsonResponse response;

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    expect(method, 'GET');
    expect(uri.path, endsWith('/catalog/products/rice/sale-options'));
    expect(uri.queryParameters['branch_id'], 'branch-a');
    return response;
  }
}

class _OfflineTransport implements JsonTransport {
  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) => throw StateError('offline');
}
