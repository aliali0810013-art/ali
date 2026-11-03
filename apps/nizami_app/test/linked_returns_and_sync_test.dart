import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/accounting/accounting_api.dart';
import 'package:nizami/src/features/accounting/minor_allocation.dart';
import 'package:nizami/src/features/accounting/financial_projection.dart';
import 'package:nizami/src/features/invoices/invoice_history_store.dart';
import 'package:nizami/src/features/invoices/invoice_pdf_service.dart';
import 'package:nizami/src/features/purchases/purchase_invoice_store.dart';
import 'package:nizami/src/features/returns/return_quantity.dart';
import 'package:nizami/src/features/returns/returns_api.dart';
import 'package:nizami/src/features/sync/invoice_delta_router.dart';
import 'package:nizami/src/features/sync/product_unit_profile_outbox.dart';
import 'package:nizami/src/features/sync/realtime_sync_coordinator.dart';
import 'package:nizami/src/features/sync/sync_page_cursor.dart';
import 'package:nizami/src/features/products/product_sale_option_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'hidden ACL page advances consumed cursor even with no visible changes',
    () {
      expect(
        SyncPageCursor.next(
          previous: 3,
          lastApplied: 3,
          serverNext: 203,
          hasMore: true,
        ),
        203,
      );
    },
  );
  test('product option is durably committed before realtime cursor', () async {
    final store = ProductSaleOptionStore('tenant-order', 'branch-order');
    final timeline = <String>[];
    final cursor = await commitSyncPageAfterDurableChanges(
      previousCursor: 8,
      serverNext: 9,
      hasMore: false,
      applyChanges: () async {
        await store.applyRemoteChange('option-order', 'upsert', {
          'tenant_id': 'tenant-order',
          'branch_id': 'branch-order',
          'product_id': 'product-order',
          'identity_key': 'count:piece:1',
          'unit_code': 'piece',
          'quantity_per_option': '1',
          'option_price_minor': 10000,
          'price_numerator_minor': 10000,
          'price_denominator': 1,
          'is_derived': false,
        });
        timeline.add('option');
        return 9;
      },
      persistCursor: (value) async {
        expect(await store.readProduct('product-order'), hasLength(1));
        timeline.add('cursor');
        return true;
      },
    );

    expect(cursor, 9);
    expect(timeline, ['option', 'cursor']);
  });

  test('ID-less unit edit cannot become a server stock dependency', () async {
    final outbox = ProductUnitProfileOutbox(
      'tenant-dependency',
      'branch-dependency',
    );
    await outbox.stage(
      localProductKey: 'local-only-product',
      productId: '',
      operationId: 'profile-operation',
      restoreGeneration: 0,
      operationCreatedAt: DateTime.utc(2026, 11, 1),
      profile: const {
        'branch_id': 'branch-dependency',
        'measurement_type': 'count',
        'pricing_unit_code': 'carton',
        'pricing_price_minor': 1000000,
        'units_per_package': 100,
      },
    );

    expect(await outbox.count(), 0);
    final pending = (await outbox.listPendingCatalogEdits()).single;
    expect(pending.awaitingCanonicalProduct, isTrue);
    expect(pending.canCreateServerStockLine, isFalse);
    expect(pending.productId, isEmpty);
  });
  test('contact-only writers cannot flush product unit profiles', () {
    expect(
      canFlushProductUnitProfiles(
        roleCode: 'employee',
        permissions: const ['contacts.write'],
      ),
      isFalse,
    );
    expect(
      canFlushProductUnitProfiles(
        roleCode: 'employee',
        permissions: const ['catalog.write'],
      ),
      isTrue,
    );
    expect(
      canFlushProductUnitProfiles(roleCode: 'owner', permissions: const []),
      isTrue,
    );
  });

  test(
    'unit profile response guard invalidates session and restore changes',
    () {
      expect(
        unitProfileResponseIsCurrent(
          capturedCoordinatorGeneration: 7,
          currentCoordinatorGeneration: 7,
          capturedRestoreGeneration: 3,
          currentRestoreGeneration: 3,
          sameSession: true,
        ),
        isTrue,
      );
      expect(
        unitProfileResponseIsCurrent(
          capturedCoordinatorGeneration: 7,
          currentCoordinatorGeneration: 8,
          capturedRestoreGeneration: 3,
          currentRestoreGeneration: 3,
          sameSession: true,
        ),
        isFalse,
      );
      expect(
        unitProfileResponseIsCurrent(
          capturedCoordinatorGeneration: 7,
          currentCoordinatorGeneration: 7,
          capturedRestoreGeneration: 3,
          currentRestoreGeneration: 4,
          sameSession: true,
        ),
        isFalse,
      );
      expect(
        unitProfileResponseIsCurrent(
          capturedCoordinatorGeneration: 7,
          currentCoordinatorGeneration: 7,
          capturedRestoreGeneration: 3,
          currentRestoreGeneration: 3,
          sameSession: false,
        ),
        isFalse,
      );
    },
  );
  test('terminal empty page does not fabricate advancement', () {
    expect(
      SyncPageCursor.next(
        previous: 203,
        lastApplied: 203,
        serverNext: 203,
        hasMore: false,
      ),
      203,
    );
  });
  test(
    'cursor refuses backward, missing, lower-than-applied or stalled backlog',
    () {
      for (final next in [null, '50', 29, 30, 44]) {
        expect(
          () => SyncPageCursor.next(
            previous: 30,
            lastApplied: 45,
            serverNext: next,
            hasMore: true,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => SyncPageCursor.next(
          previous: 30,
          lastApplied: 30,
          serverNext: 30,
          hasMore: true,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'quantity supports Arabic and Persian digits without binary rounding',
    () {
      expect(ReturnQuantity.milli('١٢٫٣٤٥'), 12345);
      expect(ReturnQuantity.milli('۱۲.۳۴۵'), 12345);
      expect(ReturnQuantity.milli('0.001'), 1);
      expect(ReturnQuantity.milli('1000'), 1000000);
      expect(ReturnQuantity.milli('0'), 0);
    },
  );
  test('quantity rejects overprecision, exponent, negative and overlimit', () {
    for (final value in [
      '-1',
      '1e3',
      '0.0001',
      '1,500',
      'NaN',
      '1000.001',
      '1001',
      '',
      '1.',
    ]) {
      expect(ReturnQuantity.milli(value), isNull, reason: value);
    }
  });
  test(
    'invoice-wide discount may exceed the first line but not the whole invoice',
    () {
      expect(MinorAllocation.discount([100, 900], 500), [50, 450]);
      expect(
        () => MinorAllocation.discount([100, 900], 1001),
        throwsArgumentError,
      );
      expect(MinorAllocation.discount([0, 0], 0), [0, 0]);
    },
  );
  test(
    'discount partitions conserve minor units over deterministic randomized cases',
    () {
      final random = Random(20261028);
      for (var iteration = 0; iteration < 2000; iteration++) {
        final gross = List<int>.generate(
          1 + random.nextInt(20),
          (_) => random.nextInt(1000000),
        );
        final total = gross.fold<int>(0, (a, b) => a + b);
        final amount = random.nextInt(total + 1);
        final parts = MinorAllocation.discount(gross, amount);
        expect(parts.fold<int>(0, (a, b) => a + b), amount);
        for (var i = 0; i < gross.length; i++) {
          expect(parts[i], inInclusiveRange(0, gross[i]));
        }
      }
    },
  );
  test('large quantity price multiplication is exact on VM and web', () {
    expect(MinorAllocation.lineGross(1000000, 1000000000), 1000000000000);
    expect(MinorAllocation.lineGross(500, 1), 1);
  });
  test(
    'return deltas never contaminate original sales and purchases caches',
    () async {
      for (final type in ['sale_return', 'purchase_return']) {
        expect(
          await InvoiceDeltaRouter.apply(
            tenantId: 'tenant-r',
            invoiceId: 'return-r',
            value: {
              'id': 'return-r',
              'branch_id': 'branch-r',
              'type': type,
              'status': 'posted',
              'total_minor': 100,
            },
          ),
          'return_invoice',
        );
      }
      expect(await InvoiceHistoryStore().read('tenant-r', 'branch-r'), isEmpty);
      expect(
        await PurchaseInvoiceStore().read('tenant-r', 'branch-r'),
        isEmpty,
      );
    },
  );
  test(
    'live balance and tax-inclusive face value survive storage without mutating issue payment',
    () {
      final value = InvoiceDocument.fromServer({
        'id': 'i',
        'number': 'INV',
        'type': 'sale',
        'total_minor': 1100,
        'initial_paid_minor': 100,
        'paid_minor': 400,
        'due_minor': 200,
        'returned_minor': 500,
        'payment_mode_at_issue': 'credit',
        'occurred_at': '2026-10-28T00:00:00Z',
        'items': [
          {
            'product_name_snapshot': 'Item',
            'quantity_milli': 1000,
            'unit_price_minor': 1000,
          },
        ],
      });
      final stored = InvoiceDocument.fromJson(value.toJson());
      expect(stored.total, 11);
      expect(stored.paidAmount, 1);
      expect(stored.currentPaidAmount, 4);
      expect(stored.currentDueAmount, 2);
      expect(stored.returnedAmount, 5);
      expect(stored.paymentMode, 'credit');
    },
  );
  test(
    'return document is a negative dated report row, not a rewritten original',
    () {
      expect(
        FinancialProjection.invoiceAmount({
          'type': 'sale',
          'total_minor': 1100,
          'returned_minor': 500,
        }),
        1100,
      );
      expect(
        FinancialProjection.invoiceAmount({
          'type': 'sale_return',
          'total_minor': 500,
        }),
        -500,
      );
      expect(
        FinancialProjection.invoiceAmount({
          'type': 'purchase_return',
          'total_minor': 200,
        }),
        -200,
      );
    },
  );
  test(
    'cash projection uses ledger movements including refunds and settlements',
    () {
      expect(
        FinancialProjection.cashMovement({
          'lines': [
            {
              'account_code': '1100-CASH',
              'debit_minor': 0,
              'credit_minor': 400,
            },
            {'account_code': '1200-AR', 'debit_minor': 400, 'credit_minor': 0},
          ],
        }),
        -400,
      );
      expect(
        FinancialProjection.cashMovement({
          'lines': [
            {
              'account_code': '1100-CASH',
              'debit_minor': 100,
              'credit_minor': 0,
            },
            {
              'account_code': '1110-BANK',
              'debit_minor': 0,
              'credit_minor': 100,
            },
          ],
        }),
        0,
      );
    },
  );
  test(
    'successful return confirmation must match immutable operation and original',
    () async {
      final payload = {
        'device_id': 'device',
        'local_operation_id': 'op',
        'items': [],
      };
      final transport = _QueueTransport([
        const JsonResponse(statusCode: 201, body: '{"invoice":{"id":"r"}}'),
      ]);
      final api = ReturnsApi(
        token: 'test',
        baseUrl: 'https://example.invalid/api/v1',
        transport: transport,
      );
      await expectLater(
        api.post('original', payload),
        throwsA(
          isA<ReturnsApiError>().having(
            (e) => e.definitelyRejected,
            'safe to discard',
            false,
          ),
        ),
      );
    },
  );
  test(
    'retry submits identical operation body after uncertain server failure',
    () async {
      final payload = {
        'device_id': 'device',
        'local_operation_id': 'op',
        'items': [
          {'original_item_id': 'line', 'quantity_milli': 1000},
        ],
      };
      final transport = _QueueTransport([
        const JsonResponse(statusCode: 500, body: '{"message":"retry"}'),
        const JsonResponse(
          statusCode: 201,
          body:
              '{"invoice":{"id":"r","reversal_of_id":"original","type":"sale_return","status":"posted","device_id":"device","local_operation_id":"op"}}',
        ),
      ]);
      final api = ReturnsApi(
        token: 'test',
        baseUrl: 'https://example.invalid/api/v1',
        transport: transport,
      );
      await expectLater(
        api.post('original', payload),
        throwsA(isA<ReturnsApiError>()),
      );
      await api.post('original', payload);
      expect(transport.bodies[0], transport.bodies[1]);
      expect(
        (jsonDecode(transport.bodies[1]!) as Map)['local_operation_id'],
        'op',
      );
    },
  );
  test(
    'direct return confirmation requires matching immutable operation without original invoice',
    () async {
      final payload = {
        'type': 'sale_return',
        'device_id': 'device',
        'local_operation_id': 'op',
        'items': [
          {
            'product_id': 'product',
            'quantity_milli': 1000,
            'unit_price_minor': 200,
          },
        ],
      };
      final transport = _QueueTransport([
        const JsonResponse(
          statusCode: 201,
          body:
              '{"invoice":{"id":"r","reversal_of_id":null,"type":"sale_return","status":"posted","device_id":"device","local_operation_id":"op"}}',
        ),
      ]);
      final api = ReturnsApi(
        token: 'test',
        baseUrl: 'https://example.invalid/api/v1',
        transport: transport,
      );
      final result = await api.postDirect(payload);
      expect((result['invoice'] as Map)['id'], 'r');
      expect(
        transport.uris.single.path.endsWith('/accounting/returns/direct'),
        isTrue,
      );
    },
  );
  test(
    'auth, conflict and server errors never authorize replacing a pending operation',
    () {
      for (final status in [0, 401, 403, 404, 409, 429, 500, 502, 503]) {
        expect(ReturnsApiError('error', status).definitelyRejected, false);
      }
    },
  );
  test(
    'purchase API loads all pages and deduplicates overlapping rows',
    () async {
      final transport = _QueueTransport([
        const JsonResponse(
          statusCode: 200,
          body: '{"data":[{"id":"p1"}],"last_page":2}',
        ),
        const JsonResponse(
          statusCode: 200,
          body: '{"data":[{"id":"p1"},{"id":"p2"}],"last_page":2}',
        ),
      ]);
      final api = AccountingApi(
        token: 'test',
        baseUrl: 'https://example.invalid/api/v1',
        transport: transport,
      );
      expect(
        (await api.listPurchases(
          branchId: 'branch',
        )).map((row) => row['id']).toList(),
        ['p1', 'p2'],
      );
      expect(transport.uris[1].queryParameters['page'], '2');
    },
  );
}

class _QueueTransport implements JsonTransport {
  _QueueTransport(this.responses);
  final List<JsonResponse> responses;
  final List<String?> bodies = [];
  final List<Uri> uris = [];
  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    bodies.add(body);
    uris.add(uri);
    if (responses.isEmpty) throw StateError('Unexpected extra request');
    return responses.removeAt(0);
  }
}
