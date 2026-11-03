import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/auth_api.dart';
import 'package:nizami/src/features/accounting/accounting_api.dart';
import 'package:nizami/src/features/invoices/invoice_history_store.dart';
import 'package:nizami/src/features/invoices/invoice_pdf_service.dart';
import 'package:nizami/src/features/sync/pending_invoice_sync.dart';
import 'package:nizami/src/features/sync/quarantined_operation_store.dart';
import 'package:nizami/src/features/sync/realtime_sync_coordinator.dart';
import 'package:nizami/src/features/sync/sales_invoice_outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenant = 'tenant-sales-a';
  const branch = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Map<String, dynamic> request({
    String operation = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    int generation = 2,
    String createdAt = '2026-11-01T08:00:00.000Z',
    String replacement = '',
    int numerator = 500000,
  }) => <String, dynamic>{
    'branch_id': branch,
    'device_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'local_operation_id': operation,
    'restore_generation': generation,
    'operation_created_at': createdAt,
    if (replacement.isNotEmpty) 'replacement_invoice_id': replacement,
    'customer_name': 'Exact customer',
    'customer_phone': '770000111',
    'contact_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'paid_minor': 125,
    'payment_mode': 'cash',
    'amount_tendered_minor': 200,
    'payment_channel': 'bank',
    'payment_account_code': '1190-BANK-TEST',
    'notes': 'immutable sale',
    'items': [
      {
        'name': 'Measured product',
        'product_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        'sale_option_id': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
        'quantity_milli': 250000,
        'unit_price_minor': 1,
        'price_numerator_minor': numerator,
        'price_denominator': 1000000,
        'discount_minor': 0,
        'kind': 'stock',
      },
    ],
  };

  Map<String, dynamic> acknowledgement({String number = 'SAL-2026-1'}) => {
    'id': '11111111-1111-4111-8111-111111111111',
    'number': number,
    'branch_id': branch,
    'total_minor': 125,
    'returned_minor': 0,
    'paid_minor': 125,
    'due_minor': 0,
    'initial_paid_minor': 125,
    'payment_mode_at_issue': 'cash',
    'amount_tendered_minor': 200,
    'payment_channel': 'bank',
    'payment_account_code': '1190-BANK-TEST',
    'status': 'posted',
  };

  test(
    'lost acknowledgement retries the byte-identical persisted body',
    () async {
      final outbox = SalesInvoiceOutbox(tenant, branch);
      final body = request();
      await outbox.enqueue(body);
      await outbox.enqueue(Map<String, dynamic>.from(body));
      final persisted = (await outbox.list()).single.requestBody;
      final api = _FakeAccountingApi(
        responses: [StateError('lost ACK after commit'), acknowledgement()],
      );

      final failed = await outbox.flush(api: api, currentRestoreGeneration: 2);
      final restarted = SalesInvoiceOutbox(tenant, branch);
      final posted = await restarted.flush(
        api: api,
        currentRestoreGeneration: 2,
      );

      expect(failed.sent, 0);
      expect(failed.error, isNotNull);
      expect(posted.sent, 1);
      expect(await outbox.count(), 0);
      expect(api.requestBodies, [persisted, persisted]);
    },
  );

  test('concurrent flush is a single FIFO flight', () async {
    final outbox = SalesInvoiceOutbox(tenant, branch);
    await outbox.enqueue(request());
    final api = _DelayedAccountingApi(acknowledgement());

    final first = outbox.flush(api: api, currentRestoreGeneration: 2);
    await api.started.future;
    final second = await SalesInvoiceOutbox(
      tenant,
      branch,
    ).flush(api: api, currentRestoreGeneration: 2);
    api.complete();

    expect(second.sent, 0);
    expect((await first).sent, 1);
    expect(api.calls, 1);
    expect(await outbox.count(), 0);
  });

  test('entry and endpoint intent survive application restart', () async {
    final outbox = SalesInvoiceOutbox(tenant, branch);
    await outbox.enqueue(
      request(replacement: '22222222-2222-4222-8222-222222222222'),
    );

    final restarted = (await SalesInvoiceOutbox(tenant, branch).list()).single;

    expect(restarted.operationId, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
    expect(
      restarted.endpointPath,
      'accounting/invoices/22222222-2222-4222-8222-222222222222/replace',
    );
    expect(
      jsonDecode(restarted.requestBody),
      containsPair(
        'replacement_invoice_id',
        '22222222-2222-4222-8222-222222222222',
      ),
    );
  });

  test('same operation rejects changed content and retains original', () async {
    final outbox = SalesInvoiceOutbox(tenant, branch);
    await outbox.enqueue(request());

    await expectLater(
      outbox.enqueue(request(numerator: 600000)),
      throwsStateError,
    );

    expect(await outbox.count(), 1);
    expect(
      jsonDecode((await outbox.list()).single.requestBody),
      containsPair(
        'items',
        contains(containsPair('price_numerator_minor', 500000)),
      ),
    );
  });

  test(
    'manual price marker is validated and immutable in persisted bytes',
    () async {
      final outbox = SalesInvoiceOutbox(tenant, branch);
      final manual = request();
      final item = Map<String, dynamic>.from((manual['items'] as List).single)
        ..['unit_price_minor'] = 2
        ..['price_numerator_minor'] = 2
        ..['price_denominator'] = 1
        ..['price_overridden'] = true;
      manual['items'] = [item];

      await outbox.enqueue(manual, snapshot: _manualOverrideInvoice());
      final persisted = (await outbox.list()).single.requestBody;
      expect(
        (jsonDecode(persisted)['items'] as List).single['price_overridden'],
        isTrue,
      );

      final changed = jsonDecode(persisted) as Map<String, dynamic>;
      (changed['items'] as List).single['price_overridden'] = false;
      await expectLater(outbox.enqueue(changed), throwsStateError);

      final malformed = jsonDecode(persisted) as Map<String, dynamic>
        ..['local_operation_id'] = 'abababab-abab-4bab-8bab-abababababab';
      (malformed['items'] as List).single['price_numerator_minor'] = 3;
      await expectLater(outbox.enqueue(malformed), throwsArgumentError);
    },
  );

  test('manual price intent requires matching durable server ACK', () async {
    final outbox = SalesInvoiceOutbox(tenant, branch);
    final manual = request();
    final item = Map<String, dynamic>.from((manual['items'] as List).single)
      ..['unit_price_minor'] = 2
      ..['price_numerator_minor'] = 2
      ..['price_denominator'] = 1
      ..['price_overridden'] = true;
    manual['items'] = [item];
    await outbox.enqueue(manual, snapshot: _manualOverrideInvoice());
    final ack = acknowledgement()
      ..['items'] = [
        {
          'product_name_snapshot': 'Measured product',
          'product_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          'sale_option_id': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
          'quantity_milli': 250000,
          'unit_price_minor': 2,
          'discount_minor': 0,
          'price_numerator_minor_snapshot': 2,
          'price_denominator_snapshot': 1,
          'price_overridden': false,
        },
      ];

    final result = await outbox.flush(
      api: _FakeAccountingApi(responses: [ack]),
      currentRestoreGeneration: 2,
    );

    expect(result.sent, 0);
    expect(result.error, contains('acknowledgement line mismatch'));
    expect(await outbox.count(), 1);
    expect(await InvoiceHistoryStore().read(tenant, branch), isEmpty);
  });

  test('same operation conflict is tenant-wide across branch queues', () async {
    final first = SalesInvoiceOutbox(tenant, branch);
    await first.enqueue(request());
    final secondBranch = SalesInvoiceOutbox(
      tenant,
      '99999999-9999-4999-8999-999999999999',
    );
    final changed = request(numerator: 600000)
      ..['branch_id'] = '99999999-9999-4999-8999-999999999999';

    await expectLater(secondBranch.enqueue(changed), throwsStateError);
    expect(await first.count(), 1);
    expect(await secondBranch.count(), 0);
  });

  test('restore mismatch is sent for canonical acknowledgement', () async {
    final outbox = SalesInvoiceOutbox(tenant, branch);
    await outbox.enqueue(
      request(generation: 1),
      snapshot: _exactInvoice(generation: 1),
    );
    final api = _FakeAccountingApi(responses: [acknowledgement()]);

    final result = await outbox.flush(
      api: api,
      currentRestoreGeneration: 2,
      restoreEpoch: DateTime.utc(2026, 11, 1, 9),
    );

    expect(result.quarantined, 0);
    expect(result.sent, 1);
    expect(api.requestBodies, hasLength(1));
    expect(await outbox.count(), 0);
    expect(await QuarantinedOperationStore(tenant).list(), isEmpty);
    final persistedAfterRestart = await InvoiceHistoryStore().read(
      tenant,
      branch,
    );
    expect(persistedAfterRestart, hasLength(1));
    expect(persistedAfterRestart.single.isQuarantined, isFalse);
    expect(persistedAfterRestart.single.postedToServer, isTrue);
  });

  test(
    'post-restore invoice is rebased to the current generation and posted',
    () async {
      final outbox = SalesInvoiceOutbox(tenant, branch);
      await outbox.enqueue(
        request(generation: 1, createdAt: '2026-11-01T10:00:00.000Z'),
        snapshot: _exactInvoice(
          generation: 1,
          createdAt: DateTime.utc(2026, 11, 1, 10),
        ),
      );
      final api = _FakeAccountingApi(responses: [acknowledgement()]);

      final result = await outbox.flush(
        api: api,
        currentRestoreGeneration: 2,
        restoreEpoch: DateTime.utc(2026, 11, 1, 9),
      );

      expect(result.sent, 1);
      expect(result.quarantined, 0);
      expect(await outbox.count(), 0);
      expect(
        (jsonDecode(api.requestBodies.single) as Map)['restore_generation'],
        2,
      );
      expect(
        (jsonDecode(api.requestBodies.single) as Map)['local_operation_id'],
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      );
      expect(await QuarantinedOperationStore(tenant).list(), isEmpty);
      expect(
        (await InvoiceHistoryStore().read(
          tenant,
          branch,
        )).single.restoreGenerationAtCreation,
        2,
      );
    },
  );

  test(
    'existing restore-mismatch quarantine is recovered and posted automatically',
    () async {
      final outbox = SalesInvoiceOutbox(tenant, branch);
      await outbox.enqueue(
        request(generation: 1, createdAt: '2026-11-01T10:00:00.000Z'),
        snapshot: _exactInvoice(
          generation: 1,
          createdAt: DateTime.utc(2026, 11, 1, 10),
        ),
      );
      final entry = (await outbox.list()).single;
      await QuarantinedOperationStore(tenant).quarantine(
        operationId: entry.operationId,
        kind: 'sales_invoice',
        reason: 'RESTORE_GENERATION_MISMATCH',
        payload: entry.toJson(),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'ninesoft.sales_invoice.outbox.v1.$tenant.$branch',
        '[]',
      );
      await InvoiceHistoryStore().markQuarantined(
        tenant,
        branch,
        entry.operationId,
        'RESTORE_GENERATION_MISMATCH',
        fallback: entry.documentSnapshot,
      );
      final api = _FakeAccountingApi(responses: [acknowledgement()]);

      final result = await outbox.flush(
        api: api,
        currentRestoreGeneration: 2,
        restoreEpoch: DateTime.utc(2026, 11, 1, 9),
      );

      expect(result.sent, 1);
      expect(await QuarantinedOperationStore(tenant).list(), isEmpty);
      final history = await InvoiceHistoryStore().read(tenant, branch);
      expect(history.single.isQuarantined, isFalse);
      expect(history.single.postedToServer, isTrue);
    },
  );

  test(
    'pre-restore sale is sent for canonical acknowledgement instead of review',
    () async {
      final outbox = SalesInvoiceOutbox(tenant, branch);
      await outbox.enqueue(
        request(generation: 1, createdAt: '2026-11-01T08:00:00.000Z'),
        snapshot: _exactInvoice(
          generation: 1,
          createdAt: DateTime.utc(2026, 11, 1, 8),
        ),
      );
      final api = _FakeAccountingApi(responses: [acknowledgement()]);

      final result = await outbox.flush(
        api: api,
        currentRestoreGeneration: 2,
        restoreEpoch: DateTime.utc(2026, 11, 1, 9),
      );

      expect(result.sent, 1);
      expect(result.quarantined, 0);
      expect(api.requestBodies, hasLength(1));
      expect(await outbox.count(), 0);
      expect(await QuarantinedOperationStore(tenant).list(), isEmpty);
    },
  );

  test(
    'post-restore quarantine with a missing request timestamp is repaired and posted',
    () async {
      final outbox = SalesInvoiceOutbox(tenant, branch);
      await outbox.enqueue(
        request(generation: 1, createdAt: '2026-11-01T10:00:00.000Z'),
        snapshot: _exactInvoice(
          generation: 1,
          createdAt: DateTime.utc(2026, 11, 1, 10),
        ),
      );
      final entry = (await outbox.list()).single;
      final quarantinedPayload = entry.toJson();
      final incompleteRequest = Map<String, dynamic>.from(
        jsonDecode(entry.requestBody) as Map,
      )..remove('operation_created_at');
      quarantinedPayload['request_body'] = jsonEncode(incompleteRequest);
      await QuarantinedOperationStore(tenant).quarantine(
        operationId: entry.operationId,
        kind: 'sales_invoice',
        reason: 'OPERATION_CREATION_TIME_REQUIRED_AFTER_RESTORE',
        payload: quarantinedPayload,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'ninesoft.sales_invoice.outbox.v1.$tenant.$branch',
        '[]',
      );
      await InvoiceHistoryStore().markQuarantined(
        tenant,
        branch,
        entry.operationId,
        'OPERATION_CREATION_TIME_REQUIRED_AFTER_RESTORE',
        fallback: entry.documentSnapshot,
      );
      final api = _FakeAccountingApi(responses: [acknowledgement()]);

      final result = await outbox.flush(
        api: api,
        currentRestoreGeneration: 2,
        restoreEpoch: DateTime.utc(2026, 11, 1, 9),
      );

      expect(result.sent, 1);
      expect(await QuarantinedOperationStore(tenant).list(), isEmpty);
      final sent = jsonDecode(api.requestBodies.single) as Map;
      expect(sent['restore_generation'], 2);
      expect(sent['operation_created_at'], '2026-11-01T10:00:00.000Z');
      final history = await InvoiceHistoryStore().read(tenant, branch);
      expect(history.single.isQuarantined, isFalse);
      expect(history.single.postedToServer, isTrue);
    },
  );

  test(
    'complete acknowledgement cache is durable before queue removal',
    () async {
      final outbox = SalesInvoiceOutbox(tenant, branch);
      await outbox.enqueue(request(), snapshot: _exactInvoice());
      final api = _FakeAccountingApi(responses: [acknowledgement()]);

      final result = await outbox.flush(api: api, currentRestoreGeneration: 2);

      expect(result.sent, 1);
      expect(await outbox.count(), 0);
      final cached = (await InvoiceHistoryStore().read(tenant, branch)).single;
      expect(cached.serverInvoiceId, '11111111-1111-4111-8111-111111111111');
      expect(cached.serverNumber, 'SAL-2026-1');
      expect(cached.paymentAccountCode, '1190-BANK-TEST');
      expect(cached.customerId, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd');
      expect(cached.customerName, 'Exact customer');
      expect(cached.lines, hasLength(1));
      expect(
        cached.lines.single.productId,
        'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      );
      expect(cached.lines.single.priceNumeratorMinorSnapshot, 500000);
      expect(cached.lines.single.priceDenominatorSnapshot, 1000000);
      expect(
        cached.lines.single.saleOptionId,
        'ffffffff-ffff-4fff-8fff-ffffffffffff',
      );
      expect(cached.lines.single.optionUnitCode, 'milligram');
      expect(cached.lines.single.optionQuantity, 1);
      expect(cached.lines.single.optionMassG, 0.001);
      expect(cached.lines.single.displayUnit, isNotEmpty);
      expect(cached.lines.single.exactQuantityMilli, 250000);
    },
  );

  test('mismatched acknowledgement line is retained before dequeue', () async {
    final outbox = SalesInvoiceOutbox(tenant, branch);
    await outbox.enqueue(request(), snapshot: _exactInvoice());
    final ack = acknowledgement()
      ..['items'] = [
        {
          'product_name_snapshot': 'Measured product',
          'product_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          'sale_option_id': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
          'quantity_milli': 999000,
          'unit_price_minor': 1,
          'discount_minor': 0,
          'price_numerator_minor_snapshot': 500000,
          'price_denominator_snapshot': 1000000,
        },
      ];

    final result = await outbox.flush(
      api: _FakeAccountingApi(responses: [ack]),
      currentRestoreGeneration: 2,
    );

    expect(result.sent, 0);
    expect(result.error, contains('acknowledgement line mismatch'));
    expect(await outbox.count(), 1);
    expect(await InvoiceHistoryStore().read(tenant, branch), isEmpty);
  });

  test(
    'cash acknowledgement may durably snapshot an empty account code',
    () async {
      final outbox = SalesInvoiceOutbox(tenant, branch);
      final body = request()
        ..remove('payment_account_code')
        ..['payment_channel'] = 'cash';
      final ack = acknowledgement()
        ..['payment_account_code'] = ''
        ..['payment_channel'] = 'cash';
      await outbox.enqueue(body);

      final result = await outbox.flush(
        api: _FakeAccountingApi(responses: [ack]),
        currentRestoreGeneration: 2,
      );

      expect(result.sent, 1);
      expect(
        (await InvoiceHistoryStore().read(
          tenant,
          branch,
        )).single.paymentAccountCode,
        isEmpty,
      );
    },
  );

  for (final malformed in <Map<String, dynamic>>[
    {'number': 'SAL-1', 'payment_account_code': '1190-BANK-TEST'},
    {'id': 'invoice-id', 'payment_account_code': '1190-BANK-TEST'},
    {'id': 'invoice-id', 'number': 'SAL-1'},
  ]) {
    test(
      'partial success never mutates history or removes the request',
      () async {
        final outbox = SalesInvoiceOutbox(tenant, branch);
        await outbox.enqueue(request());

        final result = await outbox.flush(
          api: _FakeAccountingApi(responses: [malformed]),
          currentRestoreGeneration: 2,
        );

        expect(result.sent, 0);
        expect(result.error, isNotNull);
        expect(await outbox.count(), 1);
        expect(await InvoiceHistoryStore().read(tenant, branch), isEmpty);
      },
    );
  }

  for (final status in [400, 403, 404, 422]) {
    test(
      '$status becomes durable needs_review and is never reported posted',
      () async {
        final outbox = SalesInvoiceOutbox(tenant, branch);
        await outbox.enqueue(request());
        final api = _FakeAccountingApi(
          responses: [AccountingApiError('rejected', statusCode: status)],
        );

        final first = await outbox.flush(api: api, currentRestoreGeneration: 2);
        final second = await outbox.flush(
          api: api,
          currentRestoreGeneration: 2,
        );

        expect(first.sent, 0);
        expect(first.needsReview, 1);
        expect(second.sent, 0);
        expect(api.requestBodies, hasLength(1));
        final retained = (await outbox.list()).single;
        expect(retained.state, SalesInvoiceOutboxState.needsReview);
        expect(retained.rejectionStatus, status);
        expect(await InvoiceHistoryStore().read(tenant, branch), isEmpty);
      },
    );
  }

  test('deterministic non-restore 409 becomes durable needs_review', () async {
    final outbox = SalesInvoiceOutbox(tenant, branch);
    await outbox.enqueue(request());
    final api = _FakeAccountingApi(
      responses: [
        const AccountingApiError('OPERATION_CONTENT_CONFLICT', statusCode: 409),
      ],
    );

    final result = await outbox.flush(api: api, currentRestoreGeneration: 2);

    expect(result.needsReview, 1);
    expect(
      (await outbox.list()).single.state,
      SalesInvoiceOutboxState.needsReview,
    );
  });

  test(
    'expired authentication stays queued and retries with the same body',
    () async {
      final outbox = SalesInvoiceOutbox(tenant, branch);
      await outbox.enqueue(request(), snapshot: _exactInvoice());
      final persisted = (await outbox.list()).single.requestBody;
      final api = _FakeAccountingApi(
        responses: [
          const AccountingApiError('Unauthenticated.', statusCode: 401),
          acknowledgement(),
        ],
      );

      final expired = await outbox.flush(api: api, currentRestoreGeneration: 2);
      final renewed = await outbox.flush(api: api, currentRestoreGeneration: 2);

      expect(expired.needsReview, 0);
      expect(expired.error, isNotNull);
      expect(renewed.sent, 1);
      expect(api.requestBodies, [persisted, persisted]);
      expect(await outbox.count(), 0);
    },
  );

  for (final code in const [
    'RESTORE_GENERATION_REQUIRED',
    'OPERATION_CREATION_TIME_REQUIRED_AFTER_RESTORE',
    'OPERATION_CREATED_BEFORE_RESTORE',
  ]) {
    test('$code response is repaired and retried automatically', () async {
      final outbox = SalesInvoiceOutbox(tenant, branch);
      await outbox.enqueue(request(), snapshot: _exactInvoice());
      final api = _FakeAccountingApi(
        responses: [
          AccountingApiError(code, statusCode: 409),
          acknowledgement(),
        ],
      );

      final first = await outbox.flush(api: api, currentRestoreGeneration: 2);
      final second = await outbox.flush(api: api, currentRestoreGeneration: 2);

      expect(first.quarantined, 0);
      expect(first.needsReview, 0);
      expect(second.sent, 1);
      expect(api.requestBodies, hasLength(2));
      expect(await outbox.count(), 0);
      expect(await QuarantinedOperationStore(tenant).list(), isEmpty);
      final history = await InvoiceHistoryStore().read(tenant, branch);
      expect(history.single.isQuarantined, isFalse);
      expect(history.single.postedToServer, isTrue);
    });
  }

  test(
    'server generation race stays queued until the sync feed refreshes generation',
    () async {
      final outbox = SalesInvoiceOutbox(tenant, branch);
      await outbox.enqueue(
        request(generation: 2, createdAt: '2026-11-01T10:00:00.000Z'),
        snapshot: _exactInvoice(
          generation: 2,
          createdAt: DateTime.utc(2026, 11, 1, 10),
        ),
      );
      final api = _FakeAccountingApi(
        responses: [
          const AccountingApiError(
            'RESTORE_GENERATION_MISMATCH',
            statusCode: 409,
          ),
          acknowledgement(),
        ],
      );

      final raced = await outbox.flush(
        api: api,
        currentRestoreGeneration: 2,
        restoreEpoch: DateTime.utc(2026, 11, 1, 9),
      );
      final refreshed = await outbox.flush(
        api: api,
        currentRestoreGeneration: 3,
        restoreEpoch: DateTime.utc(2026, 11, 1, 9),
      );

      expect(raced.sent, 0);
      expect(raced.quarantined, 0);
      expect(refreshed.sent, 1);
      expect(await QuarantinedOperationStore(tenant).list(), isEmpty);
      expect(api.requestBodies, hasLength(2));
      expect(
        (jsonDecode(api.requestBodies.last) as Map)['restore_generation'],
        3,
      );
    },
  );

  test('timeout and 5xx remain queued for automatic retry', () async {
    for (final failure in <Object>[
      TimeoutException('offline'),
      const AccountingApiError('temporary', statusCode: 503),
    ]) {
      SharedPreferences.setMockInitialValues({});
      final outbox = SalesInvoiceOutbox(tenant, branch);
      await outbox.enqueue(request());

      final result = await outbox.flush(
        api: _FakeAccountingApi(responses: [failure]),
        currentRestoreGeneration: 2,
      );

      expect(result.needsReview, 0);
      expect(result.error, isNotNull);
      expect(
        (await outbox.list()).single.state,
        SalesInvoiceOutboxState.queued,
      );
    }
  });

  test('invalidated success cannot cache or acknowledge', () async {
    final outbox = SalesInvoiceOutbox(tenant, branch);
    await outbox.enqueue(request());
    final api = _DelayedAccountingApi(acknowledgement());
    var valid = true;

    final flushing = outbox.flush(
      api: api,
      currentRestoreGeneration: 2,
      isResponseValid: () => valid,
    );
    await api.started.future;
    valid = false;
    api.complete();
    final result = await flushing;

    expect(result.invalidated, 1);
    expect(result.sent, 0);
    expect(await outbox.count(), 1);
    expect(await InvoiceHistoryStore().read(tenant, branch), isEmpty);
  });

  test(
    'invalidated rejection remains queued without needs_review mutation',
    () async {
      final outbox = SalesInvoiceOutbox(tenant, branch);
      await outbox.enqueue(request());
      final api = _DelayedAccountingApi(
        const AccountingApiError('validation', statusCode: 422),
      );
      var valid = true;

      final flushing = outbox.flush(
        api: api,
        currentRestoreGeneration: 2,
        isResponseValid: () => valid,
      );
      await api.started.future;
      valid = false;
      api.complete();
      final result = await flushing;

      expect(result.invalidated, 1);
      expect(result.needsReview, 0);
      expect(
        (await outbox.list()).single.state,
        SalesInvoiceOutboxState.queued,
      );
    },
  );

  test('legacy scanner skips operations owned by the sales outbox', () async {
    final invoice = _invoice();
    final outbox = SalesInvoiceOutbox(tenant, branch);
    await outbox.enqueue(request());

    expect(
      await PendingInvoiceSync.isLegacyPending(
        tenantId: tenant,
        branchId: branch,
        invoice: invoice,
      ),
      isFalse,
    );
    expect(
      await PendingInvoiceSync.isLegacyPending(
        tenantId: tenant,
        branchId: branch,
        invoice: _invoice(operation: 'legacy-operation'),
      ),
      isTrue,
    );
  });

  test(
    'legacy pre-restore invoice is retained for automatic delivery',
    () async {
      final legacy = _invoice(operation: 'legacy-pre-restore', generation: 1);
      await InvoiceHistoryStore().save(tenant, branch, legacy);
      final changed = await PendingInvoiceSync.flush(
        const AuthSession(
          token: 'token',
          userId: 'user',
          username: 'owner',
          displayName: 'Owner',
          roleCode: 'owner',
          tenantId: tenant,
          tenantName: 'Tenant',
          tenantSlug: 'tenant',
          branchIds: [branch],
          mustChangePassword: false,
          permissions: ['invoices.create'],
        ),
        restoreGeneration: 2,
        createdAfter: DateTime.utc(2026, 11, 1, 9),
      );

      final persisted = (await InvoiceHistoryStore().read(
        tenant,
        branch,
      )).single;
      expect(changed, isFalse);
      expect(persisted.isQuarantined, isFalse);
    },
  );

  test(
    'coordinator permission gate admits create or update without crossing',
    () {
      expect(
        canFlushSalesInvoiceOutbox(
          roleCode: 'employee',
          permissions: const ['invoices.update'],
        ),
        isTrue,
      );
      expect(
        canFlushSalesInvoiceOutbox(
          roleCode: 'employee',
          permissions: const ['invoices.create'],
        ),
        isTrue,
      );
      expect(
        canFlushSalesInvoiceOutbox(
          roleCode: 'employee',
          permissions: const ['invoices.view'],
        ),
        isFalse,
      );
    },
  );

  test(
    'update-only drains replacement but cannot send a new invoice',
    () async {
      final replacement = SalesInvoiceOutbox(tenant, branch);
      await replacement.enqueue(
        request(replacement: '22222222-2222-4222-8222-222222222222'),
      );
      final replacementApi = _FakeAccountingApi(responses: [acknowledgement()]);

      final replacementResult = await replacement.flush(
        api: replacementApi,
        currentRestoreGeneration: 2,
        canSend: (entry) => canSendSalesInvoiceEntry(
          entry: entry,
          roleCode: 'employee',
          permissions: const ['invoices.update'],
        ),
      );

      expect(replacementResult.sent, 1);
      expect(replacementApi.requestBodies, hasLength(1));

      SharedPreferences.setMockInitialValues({});
      final creation = SalesInvoiceOutbox(tenant, branch);
      await creation.enqueue(request());
      final creationApi = _FakeAccountingApi(responses: [acknowledgement()]);

      final creationResult = await creation.flush(
        api: creationApi,
        currentRestoreGeneration: 2,
        canSend: (entry) => canSendSalesInvoiceEntry(
          entry: entry,
          roleCode: 'employee',
          permissions: const ['invoices.update'],
        ),
      );

      expect(creationResult.sent, 0);
      expect(creationApi.requestBodies, isEmpty);
      expect(await creation.count(), 1);
    },
  );

  test('create-only cannot send a replacement request', () async {
    final outbox = SalesInvoiceOutbox(tenant, branch);
    await outbox.enqueue(
      request(replacement: '22222222-2222-4222-8222-222222222222'),
    );
    final api = _FakeAccountingApi(responses: [acknowledgement()]);

    final result = await outbox.flush(
      api: api,
      currentRestoreGeneration: 2,
      canSend: (entry) => canSendSalesInvoiceEntry(
        entry: entry,
        roleCode: 'employee',
        permissions: const ['invoices.create'],
      ),
    );

    expect(result.sent, 0);
    expect(api.requestBodies, isEmpty);
    expect(await outbox.count(), 1);
  });
}

InvoiceDocument _invoice({
  String operation = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  int generation = 2,
}) => InvoiceDocument(
  number: 'LOCAL-1',
  customerName: 'Exact customer',
  customerPhone: '770000111',
  customerId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  lines: const [
    InvoiceLine(name: 'Measured product', quantity: 250, unitPrice: 0.005),
  ],
  currency: 'YER',
  employeeName: 'Owner',
  branchLabel: 'Main',
  createdAt: DateTime.utc(2026, 11, 1, 8),
  localOperationId: operation,
  restoreGenerationAtCreation: generation,
);

InvoiceDocument _exactInvoice({int generation = 2, DateTime? createdAt}) =>
    InvoiceDocument(
      number: 'LOCAL-EXACT-1',
      customerName: 'Exact customer',
      customerPhone: '770000111',
      customerId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      lines: const [
        InvoiceLine(
          name: 'Measured product',
          quantity: 250,
          unitPrice: 0.01,
          productId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          saleOptionId: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
          optionUnitCode: 'milligram',
          optionQuantity: 1,
          optionMassG: 0.001,
          displayUnit: 'milligram',
          exactQuantityMilli: 250000,
          priceNumeratorMinor: 500000,
          priceDenominator: 1000000,
        ),
      ],
      currency: 'YER',
      employeeName: 'Owner',
      branchLabel: 'Main',
      createdAt: createdAt ?? DateTime.utc(2026, 11, 1, 8),
      paymentMode: 'cash',
      paidAmount: 1.25,
      amountTendered: 2,
      paymentChannel: 'bank',
      paymentAccountCode: '1190-BANK-TEST',
      notes: 'immutable sale',
      localOperationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      restoreGenerationAtCreation: generation,
    );

InvoiceDocument _manualOverrideInvoice() => InvoiceDocument(
  number: 'LOCAL-MANUAL-1',
  customerName: 'Exact customer',
  customerPhone: '770000111',
  customerId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  lines: const [
    InvoiceLine(
      name: 'Measured product',
      quantity: 250,
      unitPrice: 0.02,
      productId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      saleOptionId: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
      exactQuantityMilli: 250000,
      priceNumeratorMinor: 2,
      priceDenominator: 1,
      priceOverridden: true,
    ),
  ],
  currency: 'YER',
  employeeName: 'Owner',
  branchLabel: 'Main',
  createdAt: DateTime.utc(2026, 11, 1, 8),
  paymentMode: 'cash',
  paidAmount: 1.25,
  amountTendered: 2,
  paymentChannel: 'bank',
  paymentAccountCode: '1190-BANK-TEST',
  notes: 'immutable sale',
  localOperationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  restoreGenerationAtCreation: 2,
);

class _FakeAccountingApi extends AccountingApi {
  _FakeAccountingApi({required this.responses}) : super(token: 'test');

  final List<Object> responses;
  final List<String> requestBodies = [];

  @override
  Future<Map<String, dynamic>> postInvoiceRequest(
    Map<String, dynamic> request,
  ) async {
    requestBodies.add(jsonEncode(request));
    final response = responses.removeAt(0);
    if (response is Error) throw response;
    if (response is Exception) throw response;
    return Map<String, dynamic>.from(response as Map);
  }
}

class _DelayedAccountingApi extends AccountingApi {
  _DelayedAccountingApi(this.response) : super(token: 'test');

  final Object response;
  final started = Completer<void>();
  final _finish = Completer<void>();
  int calls = 0;

  void complete() => _finish.complete();

  @override
  Future<Map<String, dynamic>> postInvoiceRequest(
    Map<String, dynamic> request,
  ) async {
    calls++;
    started.complete();
    await _finish.future;
    if (response is Error) throw response;
    if (response is Exception) throw response;
    return Map<String, dynamic>.from(response as Map);
  }
}
