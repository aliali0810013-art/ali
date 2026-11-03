import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/modules/catalog_sync_api.dart';
import 'package:nizami/src/features/products/product_sale_option_store.dart';
import 'package:nizami/src/features/sync/product_unit_profile_outbox.dart';
import 'package:nizami/src/features/sync/quarantined_operation_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Map<String, dynamic> profile({int price = 500000}) => {
    'branch_id': 'branch-a',
    'measurement_type': 'mass',
    'pricing_unit_code': 'kilogram',
    'pricing_price_minor': price,
    'unit_barcodes': {'kilogram': 'KG-1', 'gram': 'G-1'},
  };

  Future<void> stage(
    ProductUnitProfileOutbox outbox, {
    String productId = 'product-a',
    String operationId = 'operation-a',
    int generation = 2,
    int price = 500000,
  }) => outbox.stage(
    localProductKey: 'local-product-a',
    productId: productId,
    operationId: operationId,
    restoreGeneration: generation,
    operationCreatedAt: DateTime.utc(2026, 11, 1, 8),
    profile: profile(price: price),
  );

  Future<void> expectAckRejectedWithoutMutation(
    Map<String, dynamic> malformed,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final outbox = ProductUnitProfileOutbox('tenant-a', 'branch-a');
    await stage(outbox);
    final store = ProductSaleOptionStore('tenant-a', 'branch-a');
    await store.replaceSnapshot([_cachedOption('before')]);
    final transport = _ProfileTransport(
      responseBody: _ackBody([_optionJson(id: 'valid-first'), malformed]),
    );

    final result = await outbox.flush(
      api: CatalogSyncApi(token: 'test', transport: transport),
      currentRestoreGeneration: 2,
    );

    expect(result.sent, 0);
    expect(result.error, isNotNull);
    expect(await outbox.count(), 1);
    expect((await store.readProduct('product-a')).map((value) => value.id), [
      'before',
    ]);
  }

  test(
    'lost acknowledgement retries the exact persisted request bytes',
    () async {
      final outbox = ProductUnitProfileOutbox('tenant-a', 'branch-a');
      await stage(outbox);
      final firstBody = (await outbox.list()).single.requestBody;
      final transport = _ProfileTransport(failFirst: true);
      final api = CatalogSyncApi(token: 'test', transport: transport);

      final failed = await outbox.flush(api: api, currentRestoreGeneration: 2);
      expect(failed.sent, 0);
      expect(await outbox.count(), 1);

      final sent = await ProductUnitProfileOutbox(
        'tenant-a',
        'branch-a',
      ).flush(api: api, currentRestoreGeneration: 2);
      expect(sent.sent, 1);
      expect(await outbox.count(), 0);
      expect(transport.bodies, [firstBody, firstBody]);
      final cached = await ProductSaleOptionStore(
        'tenant-a',
        'branch-a',
      ).readProduct('product-a');
      expect(cached.single.priceNumeratorMinor, 500000);
      expect(cached.single.priceDenominator, 1000);
    },
  );

  test('immutable HTTP body carries the restore barrier fields', () async {
    final outbox = ProductUnitProfileOutbox('tenant-a', 'branch-a');
    await stage(outbox, generation: 9);

    final body = Map<String, dynamic>.from(
      jsonDecode((await outbox.list()).single.requestBody) as Map,
    );

    expect(body['restore_generation'], 9);
    expect(body['operation_created_at'], '2026-11-01T08:00:00.000Z');
  });

  test(
    'same operation rejects changed content without replacing original',
    () async {
      final outbox = ProductUnitProfileOutbox('tenant-a', 'branch-a');
      await stage(outbox);
      await expectLater(stage(outbox, price: 600000), throwsStateError);
      expect(await outbox.count(), 1);
      expect(
        jsonDecode((await outbox.list()).single.requestBody),
        containsPair('pricing_price_minor', 500000),
      );
    },
  );

  test('same operation conflict is tenant-wide across branch queues', () async {
    final branchA = ProductUnitProfileOutbox('tenant-a', 'branch-a');
    final branchB = ProductUnitProfileOutbox('tenant-a', 'branch-b');
    await stage(branchA, operationId: 'tenant-operation');

    await expectLater(
      branchB.stage(
        localProductKey: 'local-product-a',
        productId: 'product-a',
        operationId: 'tenant-operation',
        restoreGeneration: 2,
        operationCreatedAt: DateTime.utc(2026, 11, 1, 8),
        profile: {...profile(price: 600000), 'branch_id': 'branch-b'},
      ),
      throwsStateError,
    );
    expect(await branchA.count(), 1);
    expect(await branchB.count(), 0);
  });

  test(
    'pending profile and encoded body survive application restart',
    () async {
      final outbox = ProductUnitProfileOutbox('tenant-a', 'branch-a');
      await stage(outbox);
      final before = (await outbox.list()).single;

      final after = (await ProductUnitProfileOutbox(
        'tenant-a',
        'branch-a',
      ).list()).single;
      expect(after.operationId, before.operationId);
      expect(after.requestBody, before.requestBody);
      expect(after.productId, 'product-a');
    },
  );

  test('restore mismatch quarantines and clears the active queue', () async {
    final outbox = ProductUnitProfileOutbox('tenant-a', 'branch-a');
    await stage(outbox, generation: 1);
    final transport = _ProfileTransport();

    final result = await outbox.flush(
      api: CatalogSyncApi(token: 'test', transport: transport),
      currentRestoreGeneration: 2,
      restoreEpoch: DateTime.utc(2026, 11, 1, 9),
    );

    expect(result.quarantined, 1);
    expect(await outbox.count(), 0);
    expect(transport.bodies, isEmpty);
    final quarantined = await QuarantinedOperationStore('tenant-a').list();
    expect(quarantined.single['kind'], 'product_unit_profile');
    expect(quarantined.single['operation_id'], 'operation-a');
  });

  test('restore mismatch quarantines a durable ID-less catalog edit', () async {
    final outbox = ProductUnitProfileOutbox('tenant-a', 'branch-a');
    await stage(outbox, productId: '', generation: 1);

    expect(await outbox.count(), 0);
    expect(await outbox.listPendingCatalogEdits(), hasLength(1));

    final result = await outbox.flush(
      api: CatalogSyncApi(token: 'test', transport: _ProfileTransport()),
      currentRestoreGeneration: 2,
    );

    expect(result.quarantined, 1);
    expect(await outbox.count(), 0);
    expect(await outbox.listPendingCatalogEdits(), isEmpty);
    expect(
      (await QuarantinedOperationStore('tenant-a').list()).single['kind'],
      'product_unit_profile',
    );
  });

  test('malformed success cannot acknowledge the immutable request', () async {
    final outbox = ProductUnitProfileOutbox('tenant-a', 'branch-a');
    await stage(outbox);
    final transport = _ProfileTransport(malformedSuccess: true);

    final result = await outbox.flush(
      api: CatalogSyncApi(token: 'test', transport: transport),
      currentRestoreGeneration: 2,
    );

    expect(result.sent, 0);
    expect(result.error, isNotNull);
    expect(await outbox.count(), 1);
  });

  test(
    'ID-less profile stays outside outbox until canonical product binding',
    () async {
      final outbox = ProductUnitProfileOutbox('tenant-a', 'branch-a');
      await stage(outbox, productId: '');
      expect(await outbox.count(), 0);
      final pending = (await outbox.listPendingCatalogEdits()).single;
      expect(pending.awaitingCanonicalProduct, isTrue);
      expect(pending.canCreateServerStockLine, isFalse);
      final transport = _ProfileTransport();
      final api = CatalogSyncApi(token: 'test', transport: transport);

      expect(
        (await outbox.flush(api: api, currentRestoreGeneration: 2)).sent,
        0,
      );
      expect(transport.bodies, isEmpty);
      expect(await outbox.count(), 0);

      await outbox.attachCanonicalProduct('operation-a', 'product-a');
      expect(await outbox.listPendingCatalogEdits(), isEmpty);
      expect(await outbox.count(), 1);
      expect((await outbox.list()).single.awaitingCanonicalProduct, isFalse);
      expect(
        (await outbox.flush(api: api, currentRestoreGeneration: 2)).sent,
        1,
      );
    },
  );

  for (final status in [403, 409, 422]) {
    test(
      '$status rejection becomes durable needs_review and is not retried',
      () async {
        final outbox = ProductUnitProfileOutbox('tenant-a', 'branch-a');
        await stage(outbox);
        final before = (await outbox.list()).single.requestBody;
        final transport = _ProfileTransport(statusCode: status);
        final api = CatalogSyncApi(token: 'test', transport: transport);

        final first = await outbox.flush(api: api, currentRestoreGeneration: 2);
        final second = await outbox.flush(
          api: api,
          currentRestoreGeneration: 2,
        );

        expect(first.needsReview, 1);
        expect(second.sent, 0);
        expect(transport.bodies, hasLength(1));
        final retained = (await outbox.list()).single;
        expect(retained.state, ProductUnitProfileState.needsReview);
        expect(retained.requestBody, before);
        expect(retained.rejectionStatus, status);
      },
    );
  }

  test('timeout and 5xx remain queued for automatic retry', () async {
    for (final transport in <_ProfileTransport>[
      _ProfileTransport(throwTransportError: true),
      _ProfileTransport(statusCode: 503),
    ]) {
      SharedPreferences.setMockInitialValues({});
      final outbox = ProductUnitProfileOutbox('tenant-a', 'branch-a');
      await stage(outbox);

      final result = await outbox.flush(
        api: CatalogSyncApi(token: 'test', transport: transport),
        currentRestoreGeneration: 2,
      );

      expect(result.needsReview, 0);
      expect(result.error, isNotNull);
      expect(
        (await outbox.list()).single.state,
        ProductUnitProfileState.queued,
      );
    }
  });

  test(
    'response invalidated while in flight cannot mutate cache or ACK',
    () async {
      final outbox = ProductUnitProfileOutbox('tenant-a', 'branch-a');
      await stage(outbox);
      final transport = _DelayedProfileTransport();
      var valid = true;
      final flushing = outbox.flush(
        api: CatalogSyncApi(token: 'test', transport: transport),
        currentRestoreGeneration: 2,
        isResponseValid: () => valid,
      );
      await transport.started.future;
      valid = false; // Models stop/start or a newer restore generation.
      transport.completeSuccess();

      final result = await flushing;

      expect(result.sent, 0);
      expect(result.invalidated, 1);
      expect(await outbox.count(), 1);
      expect(
        await ProductSaleOptionStore(
          'tenant-a',
          'branch-a',
        ).readProduct('product-a'),
        isEmpty,
      );
    },
  );

  test(
    'invalidated deterministic rejection stays queued for the new session',
    () async {
      final outbox = ProductUnitProfileOutbox('tenant-a', 'branch-a');
      await stage(outbox);
      final transport = _DelayedProfileTransport();
      var valid = true;
      final flushing = outbox.flush(
        api: CatalogSyncApi(token: 'old-session', transport: transport),
        currentRestoreGeneration: 2,
        isResponseValid: () => valid,
      );
      await transport.started.future;
      valid = false; // Models session replacement while PUT is in flight.
      transport.completeRejected(422);

      final staleResult = await flushing;

      expect(staleResult.invalidated, 1);
      expect(staleResult.needsReview, 0);
      final retained = (await outbox.list()).single;
      expect(retained.state, ProductUnitProfileState.queued);
      expect(retained.rejectionStatus, isNull);

      final retried = await outbox.flush(
        api: CatalogSyncApi(
          token: 'new-session',
          transport: _ProfileTransport(),
        ),
        currentRestoreGeneration: 2,
      );
      expect(retried.sent, 1);
      expect(await outbox.count(), 0);
    },
  );

  test('per-option product mismatch cannot mutate cache or ACK', () async {
    final outbox = ProductUnitProfileOutbox('tenant-a', 'branch-a');
    await stage(outbox);
    final store = ProductSaleOptionStore('tenant-a', 'branch-a');
    await store.replaceSnapshot([_cachedOption('before')]);
    final transport = _ProfileTransport(
      responseBody: _ackBody([
        _optionJson(id: 'wrong-product', productId: 'product-b'),
      ]),
    );

    final result = await outbox.flush(
      api: CatalogSyncApi(token: 'test', transport: transport),
      currentRestoreGeneration: 2,
    );

    expect(result.sent, 0);
    expect(await outbox.count(), 1);
    expect((await store.readProduct('product-a')).single.id, 'before');
    expect(await store.readProduct('product-b'), isEmpty);
  });

  test('later malformed ACK row causes no partial cache mutation', () async {
    final outbox = ProductUnitProfileOutbox('tenant-a', 'branch-a');
    await stage(outbox);
    final store = ProductSaleOptionStore('tenant-a', 'branch-a');
    await store.replaceSnapshot([_cachedOption('before')]);
    final malformed = _optionJson(id: 'second')..['id'] = 2;
    final transport = _ProfileTransport(
      responseBody: _ackBody([_optionJson(id: 'first'), malformed]),
    );

    final result = await outbox.flush(
      api: CatalogSyncApi(token: 'test', transport: transport),
      currentRestoreGeneration: 2,
    );

    expect(result.sent, 0);
    expect(await outbox.count(), 1);
    expect((await store.readProduct('product-a')).map((value) => value.id), [
      'before',
    ]);
  });

  test('ACK missing price numerator cannot mutate cache or acknowledge', () {
    final malformed = _optionJson(id: 'missing-numerator')
      ..remove('price_numerator_minor');
    return expectAckRejectedWithoutMutation(malformed);
  });

  test('ACK missing price denominator cannot mutate cache or acknowledge', () {
    final malformed = _optionJson(id: 'missing-denominator')
      ..remove('price_denominator');
    return expectAckRejectedWithoutMutation(malformed);
  });

  test('ACK missing version cannot mutate cache or acknowledge', () {
    final malformed = _optionJson(id: 'missing-version')..remove('version');
    return expectAckRejectedWithoutMutation(malformed);
  });

  test(
    'ACK zero authoritative values cannot mutate cache or acknowledge',
    () async {
      for (final field in const [
        'price_numerator_minor',
        'price_denominator',
        'version',
      ]) {
        final malformed = _optionJson(id: 'zero-$field')..[field] = '0';
        await expectAckRejectedWithoutMutation(malformed);
      }
    },
  );
}

Map<String, dynamic> _optionJson({
  required String id,
  String productId = 'product-a',
}) => {
  'id': id,
  'tenant_id': 'tenant-a',
  'branch_id': 'branch-a',
  'product_id': productId,
  'identity_key': 'mass:gram:$id',
  'unit_code': 'gram',
  'quantity_per_option': '1',
  'option_price_minor': 500,
  'price_numerator_minor': '500000',
  'price_denominator': '1000',
  'is_derived': true,
  'version': '1',
};

String _ackBody(List<Map<String, dynamic>> options) => jsonEncode({
  'product': {'id': 'product-a'},
  'sale_options': options,
});

ProductSaleOption _cachedOption(String id) =>
    ProductSaleOption.fromJson(_optionJson(id: id));

class _ProfileTransport implements JsonTransport {
  _ProfileTransport({
    this.failFirst = false,
    this.malformedSuccess = false,
    this.statusCode = 200,
    this.throwTransportError = false,
    this.responseBody,
  });

  final bool failFirst;
  final bool malformedSuccess;
  final int statusCode;
  final bool throwTransportError;
  final String? responseBody;
  final List<String> bodies = [];

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    expect(method, 'PUT');
    expect(uri.path, endsWith('/catalog/products/product-a/unit-profile'));
    bodies.add(body ?? '');
    jsonDecode(body!);
    if (throwTransportError) throw StateError('network timeout');
    if (failFirst && bodies.length == 1) {
      throw StateError('simulated response lost after commit');
    }
    if (malformedSuccess) {
      return const JsonResponse(
        statusCode: 200,
        body: '{"product":{"id":"another-product"},"sale_options":[]}',
      );
    }
    return JsonResponse(
      statusCode: statusCode,
      body:
          responseBody ??
          (statusCode >= 200 && statusCode < 300
              ? _ackBody([_optionJson(id: 'gram')])
              : '{"message":"rejected"}'),
    );
  }
}

class _DelayedProfileTransport implements JsonTransport {
  final started = Completer<void>();
  final _response = Completer<JsonResponse>();

  void completeSuccess() => _response.complete(
    JsonResponse(statusCode: 200, body: _ackBody([_optionJson(id: 'gram')])),
  );

  void completeRejected(int statusCode) => _response.complete(
    JsonResponse(statusCode: statusCode, body: '{"message":"rejected"}'),
  );

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) {
    started.complete();
    return _response.future;
  }
}
