import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/accounting/accounting_api.dart';
import 'package:nizami/src/features/purchases/purchase_invoice_store.dart';
import 'package:nizami/src/features/purchases/purchase_workspace_page.dart';
import 'package:nizami/src/features/sync/purchase_outbox.dart';
import 'package:nizami/src/features/sync/quarantined_operation_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _branchA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _branchB = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaab';
const _device = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _product = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _option = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _secondProduct = 'dddddddd-dddd-4ddd-8ddd-ddddddddddde';
const _secondOption = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeef';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('typed v1-compatible storage', () {
    test(
      'migrates a complete v1 row once without changing request bytes',
      () async {
        final data = _request(_operation(1));
        final body = jsonEncode(data);
        final key = 'ninesoft.purchase.outbox.v1.tenant-migration.$_branchA';
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(
          key,
          jsonEncode([
            {'request': data, 'enqueued_at': '2026-11-01T00:00:00.000Z'},
          ]),
        );

        final entries = await PurchaseOutbox(
          'tenant-migration',
          _branchA,
        ).list();

        expect(entries, hasLength(1));
        expect(entries.single.operationId, _operation(1));
        expect(entries.single.requestBody, body);
        expect(entries.single.state, PurchaseOutboxState.queued);
        final persisted = jsonDecode(preferences.getString(key)!) as List;
        expect((persisted.single as Map)['request_body'], body);
        expect((persisted.single as Map).containsKey('request'), isFalse);
      },
    );

    test(
      'malformed mixed v1 storage fails closed without rewriting it',
      () async {
        final key = 'ninesoft.purchase.outbox.v1.tenant-corrupt.$_branchA';
        final original = jsonEncode([
          {
            'request': _request(_operation(2)),
            'enqueued_at': '2026-11-01T00:00:00.000Z',
          },
          {'unexpected': true},
        ]);
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(key, original);

        await expectLater(
          PurchaseOutbox('tenant-corrupt', _branchA).list(),
          throwsFormatException,
        );
        expect(preferences.getString(key), original);
      },
    );

    test(
      'operation identity conflicts are detected across tenant branches',
      () async {
        final operation = _operation(3);
        await PurchaseOutbox(
          'tenant-conflict',
          _branchA,
        ).enqueue(_request(operation));

        await expectLater(
          PurchaseOutbox(
            'tenant-conflict',
            _branchB,
          ).enqueue(_request(operation, branchId: _branchB)),
          throwsStateError,
        );
        expect(await PurchaseOutbox('tenant-conflict', _branchB).count(), 0);
      },
    );
  });

  group('immutable delivery and canonical acknowledgement', () {
    test('concurrent flushes are one tenant-wide flight', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final transport = _ScriptedTransport((
        transport,
        uri,
        method,
        body,
      ) async {
        if (method == 'POST') {
          started.complete();
          await release.future;
          final request = jsonDecode(body!) as Map<String, dynamic>;
          return _postAck(request);
        }
        return _getAck(transport.lastRequest!);
      });
      final queue = PurchaseOutbox('tenant-single-flight', _branchA);
      await queue.enqueue(_request(_operation(4)));
      final api = _api(transport);

      final first = queue.flush(api: api, currentRestoreGeneration: 0);
      await started.future;
      final second = queue.flush(api: api, currentRestoreGeneration: 0);
      release.complete();

      expect((await first).sent, 1);
      expect((await second).sent, 0);
      expect(transport.postBodies, hasLength(1));
      expect(transport.getCount, 1);
    });

    test(
      'lost POST acknowledgement retries byte-identical body after restart',
      () async {
        var firstPost = true;
        final transport = _ScriptedTransport((
          transport,
          uri,
          method,
          body,
        ) async {
          if (method == 'POST') {
            if (firstPost) {
              firstPost = false;
              throw StateError('response lost after commit');
            }
            return _postAck(jsonDecode(body!) as Map<String, dynamic>);
          }
          return _getAck(transport.lastRequest!);
        });
        final request = _request(_operation(5));
        final queue = PurchaseOutbox('tenant-lost-ack', _branchA);
        await queue.enqueue(request);
        final persistedBody = (await queue.list()).single.requestBody;

        final failed = await queue.flush(
          api: _api(transport),
          currentRestoreGeneration: 0,
        );
        expect(failed.sent, 0);
        expect(await queue.count(), 1);

        final restarted = PurchaseOutbox('tenant-lost-ack', _branchA);
        final posted = await restarted.flush(
          api: _api(transport),
          currentRestoreGeneration: 0,
        );
        expect(posted.sent, 1);
        expect(transport.postBodies, [persistedBody, persistedBody]);
        expect(await restarted.count(), 0);
      },
    );

    test(
      'POST success followed by GET failure remains queued across restart',
      () async {
        var firstGet = true;
        final transport = _ScriptedTransport((
          transport,
          uri,
          method,
          body,
        ) async {
          if (method == 'POST') {
            return _postAck(jsonDecode(body!) as Map<String, dynamic>);
          }
          if (firstGet) {
            firstGet = false;
            throw StateError('canonical read response lost');
          }
          return _getAck(transport.lastRequest!);
        });
        final queue = PurchaseOutbox('tenant-get-retry', _branchA);
        await queue.enqueue(_request(_operation(6)));

        expect(
          (await queue.flush(
            api: _api(transport),
            currentRestoreGeneration: 0,
          )).sent,
          0,
        );
        expect(await queue.count(), 1);
        expect(
          (await PurchaseOutbox(
            'tenant-get-retry',
            _branchA,
          ).flush(api: _api(transport), currentRestoreGeneration: 0)).sent,
          1,
        );
        expect(transport.postBodies, hasLength(2));
        expect(transport.postBodies[0], transport.postBodies[1]);
        expect(transport.getCount, 2);
      },
    );

    test(
      'canonical GET snapshots are cached verbatim before dequeue',
      () async {
        final transport = _successTransport();
        final request = _request(_operation(7));
        (request['items'] as List).single['name'] = 'client display name';
        final queue = PurchaseOutbox('tenant-canonical-cache', _branchA);
        await queue.enqueue(request);

        final result = await queue.flush(
          api: _api(transport),
          currentRestoreGeneration: 0,
        );

        expect(result.sent, 1);
        expect(await queue.count(), 0);
        final cached = await PurchaseInvoiceStore().read(
          'tenant-canonical-cache',
          _branchA,
        );
        final item = (cached.single['items'] as List).single as Map;
        expect(item['product_name_snapshot'], 'Canonical cumin carton');
        expect(item['sale_option_id'], _option);
        expect(item['option_unit_code_snapshot'], 'carton');
        expect(item['transaction_unit_name_snapshot'], 'carton');
        expect(item['purchase_unit_name_snapshot'], 'carton');
        expect(item['stock_unit_name_snapshot'], 'piece');
        expect(item['option_quantity_snapshot'], '24.000000');
        expect(item['option_mass_g_snapshot'], isNull);
        expect(item['stock_factor_milli_snapshot'], 24000);
        expect(item['price_numerator_minor_snapshot'], 2500);
        expect(item['price_denominator_snapshot'], 1000);
      },
    );

    test(
      'canonical GET lines match request identities even when UUID order differs',
      () async {
        final request = _request(_operation(25));
        (request['items'] as List<Map<String, dynamic>>).add(<String, dynamic>{
          'product_id': _secondProduct,
          'sale_option_id': _secondOption,
          'name': 'Second product',
          'kind': 'stock',
          'quantity_milli': 1000,
          'unit_price_minor': 700,
          'price_numerator_minor': 700,
          'price_denominator': 1,
          'discount_minor': 0,
          'tax_minor': 0,
        });
        request['paid_minor'] = 3100;
        final transport = _successTransport(
          mutateDetail: (invoice) {
            final first = Map<String, dynamic>.from(
              (invoice['items'] as List).single as Map,
            );
            final second = <String, dynamic>{
              ...first,
              'id': '00000000-0000-4000-8000-000000000001',
              'product_id': _secondProduct,
              'sale_option_id': _secondOption,
              'product_name_snapshot': 'Second canonical product',
              'quantity_milli': 1000,
              'stock_quantity_milli': 1000,
              'stock_factor_milli_snapshot': 1000,
              'stock_factor_milli': 1000,
              'units_per_package_milli': 1000,
              'unit_price_minor': 700,
              'price_numerator_minor_snapshot': 700,
              'price_denominator_snapshot': 1,
              'line_total_minor': 700,
              'unit_cost_minor': 700,
              'line_cost_minor': 700,
            };
            first['id'] = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
            invoice['total_minor'] = 3100;
            invoice['paid_minor'] = 3100;
            invoice['items'] = <Map<String, dynamic>>[second, first];
            return invoice;
          },
        );
        final queue = PurchaseOutbox('tenant-line-order', _branchA);
        await queue.enqueue(request);

        final result = await queue.flush(
          api: _api(transport),
          currentRestoreGeneration: 0,
        );

        expect(result.sent, 1);
        expect(await queue.count(), 0);
        final cached = await PurchaseInvoiceStore().read(
          'tenant-line-order',
          _branchA,
        );
        final cachedItems = cached.single['items'] as List;
        expect(cachedItems.map((item) => (item as Map)['product_id']), [
          _secondProduct,
          _product,
        ]);
      },
    );

    test('mass option accepts a mass snapshot with null quantity', () async {
      final transport = _successTransport(
        mutateDetail: (invoice) {
          final item =
              (invoice['items'] as List).single as Map<String, dynamic>;
          item['option_unit_code_snapshot'] = 'gram';
          item['transaction_unit_name_snapshot'] = 'gram';
          item['purchase_unit_name_snapshot'] = 'gram';
          item['stock_unit_name_snapshot'] = 'kilogram';
          item['option_quantity_snapshot'] = null;
          item['option_mass_g_snapshot'] = '1.000000';
          item['stock_quantity_milli'] = 2;
          item['stock_factor_milli_snapshot'] = 1;
          item['stock_factor_milli'] = 1;
          item['units_per_package_milli'] = 1;
          return invoice;
        },
      );
      final queue = PurchaseOutbox('tenant-mass-option', _branchA);
      await queue.enqueue(_request(_operation(24)));

      final result = await queue.flush(
        api: _api(transport),
        currentRestoreGeneration: 0,
      );

      expect(result.sent, 1);
      expect(await queue.count(), 0);
    });

    test('cache write failure never acknowledges the queue row', () async {
      final transport = _successTransport();
      final queue = PurchaseOutbox(
        'tenant-cache-failure',
        _branchA,
        invoiceStore: _FailingPurchaseInvoiceStore(),
      );
      await queue.enqueue(_request(_operation(8)));

      final result = await queue.flush(
        api: _api(transport),
        currentRestoreGeneration: 0,
      );

      expect(result.sent, 0);
      expect(result.error, contains('simulated cache failure'));
      expect(await queue.count(), 1);
    });

    test(
      'corrupt purchase cache is never overwritten or acknowledged',
      () async {
        const tenant = 'tenant-corrupt-purchase-cache';
        final preferences = await SharedPreferences.getInstance();
        final key = 'ninesoft.purchases.v1.$tenant.$_branchA';
        const corrupt = '{"not":"an invoice list"}';
        await preferences.setString(key, corrupt);
        final queue = PurchaseOutbox(tenant, _branchA);
        await queue.enqueue(_request(_operation(26)));

        final result = await queue.flush(
          api: _api(_successTransport()),
          currentRestoreGeneration: 0,
        );

        expect(result.sent, 0);
        expect(result.error, isNotNull);
        expect(preferences.getString(key), corrupt);
        expect(await queue.count(), 1);
        expect((await queue.list()).single.state, PurchaseOutboxState.queued);
      },
    );
  });

  group('error state machine', () {
    for (final rejectedStatus in const [400, 403, 404, 409, 422]) {
      test(
        '$rejectedStatus marks first row needsReview and continues',
        () async {
          final rejected = _operation(9);
          final accepted = _operation(10);
          final transport = _ScriptedTransport((
            transport,
            uri,
            method,
            body,
          ) async {
            if (method == 'POST') {
              final request = jsonDecode(body!) as Map<String, dynamic>;
              if (request['local_operation_id'] == rejected) {
                return JsonResponse(
                  statusCode: rejectedStatus,
                  body: '{"message":"OPERATION_CONTENT_CONFLICT"}',
                );
              }
              return _postAck(request);
            }
            return _getAck(transport.lastRequest!);
          });
          final queue = PurchaseOutbox('tenant-review-continue', _branchA);
          await queue.enqueue(_request(rejected));
          await queue.enqueue(_request(accepted));
          final originalBody = (await queue.list()).first.requestBody;

          final result = await queue.flush(
            api: _api(transport),
            currentRestoreGeneration: 0,
          );

          expect(result.needsReview, 1);
          expect(result.sent, 1);
          final remaining = await queue.list();
          expect(remaining, hasLength(1));
          expect(remaining.single.state, PurchaseOutboxState.needsReview);
          expect(remaining.single.rejectionStatus, rejectedStatus);
          expect(remaining.single.requestBody, originalBody);
          final postCount = transport.postBodies.length;
          await queue.flush(api: _api(transport), currentRestoreGeneration: 0);
          expect(transport.postBodies, hasLength(postCount));
        },
      );
    }

    for (final testCase in <({String name, int? status})>[
      (name: '401', status: 401),
      (name: '408', status: 408),
      (name: '425', status: 425),
      (name: '429', status: 429),
      (name: '500', status: 500),
      (name: 'transport', status: null),
    ]) {
      test(
        '${testCase.name} keeps FIFO head queued and does not send next',
        () async {
          final transport = _ScriptedTransport((
            transport,
            uri,
            method,
            body,
          ) async {
            if (method != 'POST') {
              throw StateError('GET must not run after a failed POST');
            }
            if (testCase.status == null) throw StateError('offline');
            return JsonResponse(
              statusCode: testCase.status!,
              body: '{"message":"TEMPORARY_PURCHASE_FAILURE"}',
            );
          });
          final queue = PurchaseOutbox(
            'tenant-transient-${testCase.name}',
            _branchA,
          );
          await queue.enqueue(_request(_operation(11)));
          await queue.enqueue(_request(_operation(12)));

          final result = await queue.flush(
            api: _api(transport),
            currentRestoreGeneration: 0,
          );

          expect(result.sent, 0);
          expect(result.needsReview, 0);
          expect(result.error, isNotNull);
          expect(transport.postBodies, hasLength(1));
          expect(
            (await queue.list()).map((entry) => entry.state),
            everyElement(PurchaseOutboxState.queued),
          );
        },
      );
    }

    test(
      'local restore mismatch is sent for canonical acknowledgement',
      () async {
        final transport = _successTransport();
        final queue = PurchaseOutbox('tenant-local-restore', _branchA);
        await queue.enqueue(_request(_operation(13)));

        final result = await queue.flush(
          api: _api(transport),
          currentRestoreGeneration: 1,
        );

        expect(result.sent, 1);
        expect(result.quarantined, 0);
        expect(await queue.count(), 0);
        expect(transport.postBodies, hasLength(1));
        expect(
          await QuarantinedOperationStore('tenant-local-restore').list(),
          isEmpty,
        );
      },
    );

    test('post-restore purchase is rebased and posted automatically', () async {
      final transport = _successTransport();
      final queue = PurchaseOutbox('tenant-safe-rebase', _branchA);
      final request = _request(_operation(130))
        ..['restore_generation'] = 1
        ..['operation_created_at'] = '2026-11-01T10:00:00.000Z';
      await queue.enqueue(request);

      final result = await queue.flush(
        api: _api(transport),
        currentRestoreGeneration: 2,
        restoreEpoch: DateTime.utc(2026, 11, 1, 9),
      );

      expect(result.sent, 1);
      expect(result.quarantined, 0);
      expect(await queue.count(), 0);
      expect(
        (jsonDecode(transport.postBodies.single) as Map)['restore_generation'],
        2,
      );
      expect(
        await QuarantinedOperationStore('tenant-safe-rebase').list(),
        isEmpty,
      );
    });

    test(
      'operation at or before restore epoch is sent for canonical acknowledgement',
      () async {
        final transport = _successTransport();
        final queue = PurchaseOutbox('tenant-restore-epoch', _branchA);
        await queue.enqueue(_request(_operation(14)));

        final result = await queue.flush(
          api: _api(transport),
          currentRestoreGeneration: 0,
          restoreEpoch: DateTime.utc(2026, 11, 1, 1),
        );

        expect(result.sent, 1);
        expect(result.quarantined, 0);
        expect(await queue.count(), 0);
        expect(transport.postBodies, hasLength(1));
        expect(
          await QuarantinedOperationStore('tenant-restore-epoch').list(),
          isEmpty,
        );
      },
    );

    for (final code in const [
      'RESTORE_GENERATION_REQUIRED',
      'OPERATION_CREATION_TIME_REQUIRED_AFTER_RESTORE',
      'OPERATION_CREATED_BEFORE_RESTORE',
    ]) {
      test('server restore code $code is repaired and retried', () async {
        var posts = 0;
        final transport = _ScriptedTransport((
          transport,
          uri,
          method,
          body,
        ) async {
          if (method == 'POST' && posts++ == 0) {
            return JsonResponse(
              statusCode: 409,
              body: jsonEncode({'message': code}),
            );
          }
          if (method == 'POST') {
            return _postAck(jsonDecode(body!) as Map<String, dynamic>);
          }
          return _getAck(transport.lastRequest!);
        });
        final tenant = 'tenant-server-${code.toLowerCase()}';
        final queue = PurchaseOutbox(tenant, _branchA);
        await queue.enqueue(_request(_operation(15)));

        final first = await queue.flush(
          api: _api(transport),
          currentRestoreGeneration: 0,
        );
        final retried = await queue.flush(
          api: _api(transport),
          currentRestoreGeneration: 0,
        );

        expect(first.quarantined, 0);
        expect(retried.sent, 1);
        expect(await queue.count(), 0);
        expect(await QuarantinedOperationStore(tenant).list(), isEmpty);
      });
    }

    test(
      'server generation race remains queued for the refreshed cycle',
      () async {
        var posts = 0;
        final transport = _ScriptedTransport((
          transport,
          uri,
          method,
          body,
        ) async {
          if (method == 'POST' && posts++ == 0) {
            return const JsonResponse(
              statusCode: 409,
              body: '{"message":"RESTORE_GENERATION_MISMATCH"}',
            );
          }
          if (method == 'POST') {
            return _postAck(jsonDecode(body!) as Map<String, dynamic>);
          }
          return _getAck(transport.lastRequest!);
        });
        final queue = PurchaseOutbox('tenant-purchase-race', _branchA);
        final request = _request(_operation(131))
          ..['restore_generation'] = 2
          ..['operation_created_at'] = '2026-11-01T10:00:00.000Z';
        await queue.enqueue(request);

        final raced = await queue.flush(
          api: _api(transport),
          currentRestoreGeneration: 2,
          restoreEpoch: DateTime.utc(2026, 11, 1, 9),
        );
        final refreshed = await queue.flush(
          api: _api(transport),
          currentRestoreGeneration: 3,
          restoreEpoch: DateTime.utc(2026, 11, 1, 9),
        );

        expect(raced.quarantined, 0);
        expect(refreshed.sent, 1);
        expect(await queue.count(), 0);
        expect(
          (jsonDecode(transport.postBodies.last) as Map)['restore_generation'],
          3,
        );
      },
    );

    test(
      'post-restore server timestamp rejection is repaired instead of quarantined',
      () async {
        var posts = 0;
        final transport = _ScriptedTransport((
          transport,
          uri,
          method,
          body,
        ) async {
          if (method == 'POST' && posts++ == 0) {
            return const JsonResponse(
              statusCode: 409,
              body:
                  '{"message":"OPERATION_CREATION_TIME_REQUIRED_AFTER_RESTORE"}',
            );
          }
          if (method == 'POST') {
            return _postAck(jsonDecode(body!) as Map<String, dynamic>);
          }
          return _getAck(transport.lastRequest!);
        });
        final queue = PurchaseOutbox('tenant-purchase-timestamp', _branchA);
        final request = _request(_operation(132))
          ..['restore_generation'] = 2
          ..['operation_created_at'] = '2026-11-01T10:00:00.000Z';
        await queue.enqueue(request);

        final first = await queue.flush(
          api: _api(transport),
          currentRestoreGeneration: 2,
          restoreEpoch: DateTime.utc(2026, 11, 1, 9),
        );
        final retried = await queue.flush(
          api: _api(transport),
          currentRestoreGeneration: 2,
          restoreEpoch: DateTime.utc(2026, 11, 1, 9),
        );

        expect(first.quarantined, 0);
        expect(retried.sent, 1);
        expect(await queue.count(), 0);
        expect(
          await QuarantinedOperationStore('tenant-purchase-timestamp').list(),
          isEmpty,
        );
        final sent = jsonDecode(transport.postBodies.last) as Map;
        expect(sent['restore_generation'], 2);
        expect(
          DateTime.parse(
            sent['operation_created_at'] as String,
          ).isAfter(DateTime.utc(2026, 11, 1, 9)),
          isTrue,
        );
      },
    );

    test('unknown RESTORE-prefixed 409 is review, not quarantine', () async {
      final transport = _ScriptedTransport((
        transport,
        uri,
        method,
        body,
      ) async {
        return const JsonResponse(
          statusCode: 409,
          body: '{"message":"RESTORE_GENERATION_UNRECOGNIZED"}',
        );
      });
      final queue = PurchaseOutbox('tenant-unknown-restore-code', _branchA);
      await queue.enqueue(_request(_operation(25)));

      final result = await queue.flush(
        api: _api(transport),
        currentRestoreGeneration: 0,
      );

      expect(result.quarantined, 0);
      expect(result.needsReview, 1);
      expect(
        (await queue.list()).single.state,
        PurchaseOutboxState.needsReview,
      );
      expect(
        await QuarantinedOperationStore('tenant-unknown-restore-code').list(),
        isEmpty,
      );
    });

    test('stale successful response cannot read cache or dequeue', () async {
      var valid = true;
      final transport = _ScriptedTransport((
        transport,
        uri,
        method,
        body,
      ) async {
        valid = false;
        return _postAck(jsonDecode(body!) as Map<String, dynamic>);
      });
      final queue = PurchaseOutbox('tenant-stale-success', _branchA);
      await queue.enqueue(_request(_operation(16)));

      final result = await queue.flush(
        api: _api(transport),
        currentRestoreGeneration: 0,
        isResponseValid: () => valid,
      );

      expect(result.invalidated, 1);
      expect(result.sent, 0);
      expect(await queue.count(), 1);
      expect(transport.getCount, 0);
      expect(
        await PurchaseInvoiceStore().read('tenant-stale-success', _branchA),
        isEmpty,
      );
    });

    test('stale deterministic error cannot change queued state', () async {
      var valid = true;
      final transport = _ScriptedTransport((
        transport,
        uri,
        method,
        body,
      ) async {
        valid = false;
        return const JsonResponse(
          statusCode: 422,
          body: '{"message":"REJECTED"}',
        );
      });
      final queue = PurchaseOutbox('tenant-stale-error', _branchA);
      await queue.enqueue(_request(_operation(17)));

      final result = await queue.flush(
        api: _api(transport),
        currentRestoreGeneration: 0,
        isResponseValid: () => valid,
      );

      expect(result.invalidated, 1);
      expect(result.needsReview, 0);
      expect((await queue.list()).single.state, PurchaseOutboxState.queued);
    });
  });

  group('canonical response rejection', () {
    test('malformed POST summary leaves immutable row queued', () async {
      final transport = _ScriptedTransport((
        transport,
        uri,
        method,
        body,
      ) async {
        return const JsonResponse(
          statusCode: 201,
          body: '{"invoice":{"number":"PUR-1"}}',
        );
      });
      final queue = PurchaseOutbox('tenant-bad-summary', _branchA);
      await queue.enqueue(_request(_operation(18)));

      final result = await queue.flush(
        api: _api(transport),
        currentRestoreGeneration: 0,
      );

      expect(result.sent, 0);
      expect(await queue.count(), 1);
      expect(transport.getCount, 0);
    });

    test('empty canonical item list leaves immutable row queued', () async {
      final transport = _successTransport(
        mutateDetail: (invoice) => invoice..['items'] = <Object?>[],
      );
      final queue = PurchaseOutbox('tenant-empty-items', _branchA);
      await queue.enqueue(_request(_operation(19)));

      expect(
        (await queue.flush(
          api: _api(transport),
          currentRestoreGeneration: 0,
        )).sent,
        0,
      );
      expect(await queue.count(), 1);
    });

    for (final mismatch in const [
      'branch_id',
      'device_id',
      'local_operation_id',
    ]) {
      test(
        '$mismatch mismatch leaves canonical response unacknowledged',
        () async {
          final transport = _successTransport(
            mutateDetail: (invoice) => invoice..[mismatch] = 'wrong-value',
          );
          final tenant = 'tenant-mismatch-$mismatch';
          final queue = PurchaseOutbox(tenant, _branchA);
          await queue.enqueue(_request(_operation(20)));

          final result = await queue.flush(
            api: _api(transport),
            currentRestoreGeneration: 0,
          );

          expect(result.sent, 0);
          expect(await queue.count(), 1);
          expect(await PurchaseInvoiceStore().read(tenant, _branchA), isEmpty);
        },
      );
    }

    test('missing selected-option snapshot leaves row queued', () async {
      final transport = _successTransport(
        mutateDetail: (invoice) {
          final item =
              (invoice['items'] as List).single as Map<String, dynamic>;
          item.remove('stock_factor_milli_snapshot');
          return invoice;
        },
      );
      final queue = PurchaseOutbox('tenant-missing-snapshot', _branchA);
      await queue.enqueue(_request(_operation(21)));

      final result = await queue.flush(
        api: _api(transport),
        currentRestoreGeneration: 0,
      );

      expect(result.sent, 0);
      expect(await queue.count(), 1);
    });

    test('guarded purchase cache refuses an invalidated write', () async {
      final store = PurchaseInvoiceStore();
      final invoice = _canonicalInvoice(_request(_operation(22)));

      await expectLater(
        store.save(
          'tenant-store-guard',
          _branchA,
          invoice,
          isValid: () => false,
        ),
        throwsA(isA<PurchaseInvoiceWriteInvalidated>()),
      );
      expect(await store.read('tenant-store-guard', _branchA), isEmpty);
    });
  });

  group('send permissions', () {
    test('purchase canonical ACK requires create and read unless owner', () {
      expect(
        canSendPurchaseOutbox(roleCode: 'owner', permissions: const []),
        isTrue,
      );
      expect(
        canSendPurchaseOutbox(
          roleCode: 'cashier',
          permissions: const ['invoices.create', 'invoices.read'],
        ),
        isTrue,
      );
      expect(
        canSendPurchaseOutbox(
          roleCode: 'cashier',
          permissions: const ['invoices.create'],
        ),
        isFalse,
      );
      expect(
        canSendPurchaseOutbox(
          roleCode: 'cashier',
          permissions: const ['invoices.read'],
        ),
        isFalse,
      );
    });

    test(
      'denied canSend leaves queued row without a network request',
      () async {
        final transport = _successTransport();
        final queue = PurchaseOutbox('tenant-permission', _branchA);
        await queue.enqueue(_request(_operation(23)));

        final result = await queue.flush(
          api: _api(transport),
          currentRestoreGeneration: 0,
          canSend: (_) => false,
        );

        expect(result.sent, 0);
        expect(await queue.count(), 1);
        expect(transport.postBodies, isEmpty);
      },
    );

    test('delivery session binds tenant token branch role and ACL', () {
      const session = PurchaseDeliverySession(
        tenantId: 'tenant-session',
        token: 'token-a',
        branchId: _branchA,
        roleCode: 'cashier',
        permissions: <String>['invoices.create', 'invoices.read'],
      );

      bool current({
        String tenant = 'tenant-session',
        String token = 'token-a',
        String branch = _branchA,
        String role = 'cashier',
        List<String> permissions = const <String>[
          'invoices.read',
          'invoices.create',
        ],
      }) => session.matches(
        tenantId: tenant,
        token: token,
        branchId: branch,
        roleCode: role,
        permissions: permissions,
      );

      expect(current(), isTrue);
      expect(current(tenant: 'other-tenant'), isFalse);
      expect(current(token: 'token-b'), isFalse);
      expect(current(branch: _branchB), isFalse);
      expect(current(role: 'auditor'), isFalse);
      expect(current(permissions: const ['invoices.create']), isFalse);
    });

    test('invalid session guard prevents durable enqueue', () async {
      final queue = PurchaseOutbox('tenant-enqueue-guard', _branchA);

      await expectLater(
        queue.enqueue(_request(_operation(27)), isValid: () => false),
        throwsA(isA<PurchaseOutboxResponseInvalidated>()),
      );

      expect(await queue.count(), 0);
    });
  });

  group('truthful pending and current-operation status', () {
    test('summary separates queued work from needs-review work', () async {
      final rejected = _operation(28);
      final queue = PurchaseOutbox('tenant-status-summary', _branchA);
      await queue.enqueue(_request(rejected));
      final transport = _ScriptedTransport((
        transport,
        uri,
        method,
        body,
      ) async {
        if (method == 'POST') {
          return const JsonResponse(
            statusCode: 422,
            body: '{"message":"INVALID_PURCHASE"}',
          );
        }
        throw StateError('GET is not expected');
      });
      await queue.flush(api: _api(transport), currentRestoreGeneration: 0);
      await queue.enqueue(_request(_operation(29)));

      final summary = await queue.summary();

      expect(summary.queued, 1);
      expect(summary.needsReview, 1);
      expect(summary.total, 2);
      expect(
        purchaseQueueSubtitle(offline: false, queued: 0, needsReview: 1),
        allOf(
          contains('تحتاج إلى مراجعة'),
          isNot(contains('بانتظار إرسال الخادم')),
        ),
      );
    });

    test(
      'posting an older row never describes the current row as posted',
      () async {
        final older = _operation(30);
        final current = _operation(31);
        final queue = PurchaseOutbox('tenant-current-operation', _branchA);
        await queue.enqueue(_request(older));
        await queue.enqueue(_request(current));

        final result = await queue.flush(
          api: _api(_successTransport()),
          currentRestoreGeneration: 0,
          maxPerCycle: 1,
        );
        final currentEntry = await queue.find(current);
        final message = purchaseCurrentOperationMessage(
          state: currentEntry?.state,
          sent: result.sentOperationIds.contains(current),
          quarantined: result.quarantinedOperationIds.contains(current),
          permitted: true,
        );

        expect(result.sent, 1);
        expect(result.sentOperationIds, contains(older));
        expect(result.sentOperationIds, isNot(contains(current)));
        expect(currentEntry?.state, PurchaseOutboxState.queued);
        expect(message, contains('محليًا'));
        expect(message, isNot(contains('تم ترحيل')));
      },
    );
  });
}

AccountingApi _api(JsonTransport transport) => AccountingApi(
  token: 'test-only',
  transport: transport,
  baseUrl: 'https://staging.example/api/v1',
);

String _operation(int suffix) =>
    'cccccccc-cccc-4ccc-8ccc-${suffix.toString().padLeft(12, '0')}';

Map<String, dynamic> _request(String operation, {String branchId = _branchA}) =>
    <String, dynamic>{
      'branch_id': branchId,
      'device_id': _device,
      'local_operation_id': operation,
      'restore_generation': 0,
      'operation_created_at': '2026-11-01T00:30:00.000Z',
      'supplier_name': 'Canonical supplier',
      'supplier_phone': '777000111',
      'payment_mode': 'cash',
      'paid_minor': 2400,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'product_id': _product,
          'sale_option_id': _option,
          'name': 'Client cumin name',
          'kind': 'stock',
          'quantity_milli': 2000,
          'unit_price_minor': 1200,
          'price_numerator_minor': 2500,
          'price_denominator': 1000,
          'discount_minor': 0,
          'tax_minor': 0,
        },
      ],
    };

Map<String, dynamic> _canonicalInvoice(
  Map<String, dynamic> request, {
  String? invoiceId,
}) => <String, dynamic>{
  'id': invoiceId ?? 'invoice-${request['local_operation_id']}',
  'number': 'PUR-2026-1',
  'branch_id': request['branch_id'],
  'type': 'purchase',
  'status': 'posted',
  'device_id': request['device_id'],
  'local_operation_id': request['local_operation_id'],
  'contact_id': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
  'supplier_name': 'Canonical supplier',
  'supplier_phone': '777000111',
  'total_minor': 2400,
  'paid_minor': 2400,
  'due_minor': 0,
  'items': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'item-${request['local_operation_id']}',
      'tenant_id': 'tenant-server',
      'invoice_id': invoiceId ?? 'invoice-${request['local_operation_id']}',
      'product_id': _product,
      'original_item_id': null,
      'sale_option_id': _option,
      'product_name_snapshot': 'Canonical cumin carton',
      'option_unit_code_snapshot': 'carton',
      'transaction_unit_name_snapshot': 'carton',
      'purchase_unit_name_snapshot': 'carton',
      'stock_unit_name_snapshot': 'piece',
      'option_quantity_snapshot': '24.000000',
      'option_mass_g_snapshot': null,
      'quantity_milli': 2000,
      'stock_quantity_milli': 48000,
      'stock_factor_milli_snapshot': 24000,
      'stock_factor_milli': 24000,
      'units_per_package_milli': 24000,
      'unit_price_minor': 1200,
      'price_numerator_minor_snapshot': 2500,
      'price_denominator_snapshot': 1000,
      'discount_minor': 0,
      'tax_minor': 0,
      'line_total_minor': 2400,
      'unit_cost_minor': 1200,
      'line_cost_minor': 2400,
    },
  ],
};

JsonResponse _postAck(Map<String, dynamic> request) => JsonResponse(
  statusCode: 201,
  body: jsonEncode({
    'invoice': {
      'id': 'invoice-${request['local_operation_id']}',
      'number': 'PUR-2026-1',
    },
  }),
);

JsonResponse _getAck(
  Map<String, dynamic> request, {
  Map<String, dynamic> Function(Map<String, dynamic>)? mutate,
}) {
  final invoice = _canonicalInvoice(request);
  mutate?.call(invoice);
  final items = invoice.remove('items');
  return JsonResponse(
    statusCode: 200,
    body: jsonEncode({'invoice': invoice, 'items': items}),
  );
}

_ScriptedTransport _successTransport({
  Map<String, dynamic> Function(Map<String, dynamic>)? mutateDetail,
}) => _ScriptedTransport((transport, uri, method, body) async {
  if (method == 'POST') {
    return _postAck(jsonDecode(body!) as Map<String, dynamic>);
  }
  return _getAck(transport.lastRequest!, mutate: mutateDetail);
});

typedef _TransportHandler =
    Future<JsonResponse> Function(
      _ScriptedTransport transport,
      Uri uri,
      String method,
      String? body,
    );

class _ScriptedTransport implements JsonTransport {
  _ScriptedTransport(this.handler);

  final _TransportHandler handler;
  final List<String> postBodies = <String>[];
  Map<String, dynamic>? lastRequest;
  int getCount = 0;

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const <String, String>{},
    String? body,
  }) async {
    if (method == 'POST') {
      postBodies.add(body ?? '');
      final decoded = jsonDecode(body!);
      if (decoded is! Map) throw StateError('POST body must be an object');
      lastRequest = Map<String, dynamic>.from(decoded);
    } else if (method == 'GET') {
      getCount++;
    }
    return handler(this, uri, method, body);
  }
}

class _FailingPurchaseInvoiceStore extends PurchaseInvoiceStore {
  @override
  Future<void> save(
    String tenant,
    String branch,
    Map<String, dynamic> invoice, {
    bool Function()? isValid,
  }) async {
    throw StateError('simulated cache failure');
  }
}
