import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nizami/src/features/invoices/invoice_pdf_service.dart';
import 'package:nizami/src/features/sync/quarantined_operation_store.dart';
import 'package:nizami/src/features/sync/invoice_delta_router.dart';
import 'package:nizami/src/features/sync/restore_snapshot_store.dart';
import 'package:nizami/src/features/sync/restore_submission_policy.dart';
import 'package:nizami/src/features/invoices/invoice_history_store.dart';
import 'package:nizami/src/features/purchases/purchase_invoice_store.dart';

RestoreSnapshotScope snapshotScope({
  String user = 'owner-1',
  List<String> branches = const ['branch-1'],
  List<String> permissions = const ['invoices.read'],
  int restoreGeneration = 0,
}) => RestoreSnapshotScope(
  tenantId: 'tenant-snapshot',
  userId: user,
  roleCode: user == 'owner-1' ? 'owner' : 'cashier',
  restoreGeneration: restoreGeneration,
  branchIds: branches,
  permissions: permissions,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'invoice delete tombstone removes the correct local cache without refetching',
    () async {
      SharedPreferences.setMockInitialValues({});
      await InvoiceDeltaRouter.apply(
        tenantId: 'tenant-delete',
        invoiceId: 'sale-delete',
        value: {
          'id': 'sale-delete',
          'number': 'INV-1',
          'type': 'sale',
          'status': 'posted',
          'branch_id': 'branch-delete',
          'total_minor': 100,
          'paid_minor': 100,
          'due_minor': 0,
          'items': const [],
        },
      );
      await InvoiceDeltaRouter.delete(
        tenantId: 'tenant-delete',
        invoiceId: 'sale-delete',
        branchId: 'branch-delete',
        invoiceType: 'sale',
      );

      expect(
        await InvoiceHistoryStore().read('tenant-delete', 'branch-delete'),
        isEmpty,
      );
    },
  );

  test(
    'purchase delta is isolated from sales on web Windows and Android clients',
    () async {
      SharedPreferences.setMockInitialValues({});
      for (final client in const ['web', 'windows', 'android']) {
        final tenant = 'tenant-purchase-$client';
        final affected = await InvoiceDeltaRouter.apply(
          tenantId: tenant,
          invoiceId: 'purchase-1',
          value: {
            'id': 'purchase-1',
            'number': 'PUR-1',
            'type': 'purchase',
            'status': 'posted',
            'branch_id': 'branch-1',
            'total_minor': 900,
          },
        );

        expect(affected, 'purchase_invoice');
        expect(
          await PurchaseInvoiceStore().read(tenant, 'branch-1'),
          hasLength(1),
        );
        expect(await InvoiceHistoryStore().read(tenant, 'branch-1'), isEmpty);
      }
    },
  );

  test(
    'server invoice preserves fractional quantity, unit, and issue payment mode',
    () {
      final invoice = InvoiceDocument.fromServer({
        'id': 'invoice-1',
        'number': 'INV-1',
        'total_minor': 12500,
        'paid_minor': 12500,
        'initial_paid_minor': 0,
        'payment_mode_at_issue': 'credit',
        'occurred_at': '2026-10-26T10:00:00Z',
        'items': [
          {
            'product_name_snapshot': 'Rice',
            'quantity_milli': 1250,
            'unit_price_minor': 10000,
            'option_unit_code_snapshot': 'kilogram',
            'option_quantity_snapshot': '1.25',
            'option_mass_g_snapshot': '1250',
          },
        ],
      });

      expect(invoice.lines.single.quantity, 1.25);
      expect(invoice.lines.single.optionUnitCode, 'kilogram');
      expect(invoice.lines.single.optionQuantity, 1.25);
      expect(invoice.paymentMode, 'credit');
      expect(invoice.isCredit, isTrue);
      expect(invoice.paidAmount, 0);
    },
  );

  test(
    'restore-conflicting operation remains reviewable until explicit removal',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = QuarantinedOperationStore('tenant-a');
      await store.quarantine(
        operationId: 'operation-1',
        kind: 'invoice',
        reason: 'RESTORE_GENERATION_MISMATCH',
        payload: {'idempotency_key': 'operation-1', 'amount_minor': 1000},
      );

      final firstRead = await store.list();
      expect(firstRead, hasLength(1));
      expect(firstRead.single['reason'], 'RESTORE_GENERATION_MISMATCH');

      final secondStore = QuarantinedOperationStore('tenant-a');
      expect(await secondStore.list(), hasLength(1));

      await secondStore.remove('operation-1');
      expect(await store.list(), isEmpty);
    },
  );

  test('manual post lets the server reconcile a pre-restore invoice', () async {
    SharedPreferences.setMockInitialValues({});
    final invoice = InvoiceDocument(
      number: 'LOCAL-OLD',
      customerName: 'Customer',
      customerPhone: '770000001',
      lines: const [InvoiceLine(name: 'Item', quantity: 1, unitPrice: 10)],
      currency: 'YER',
      employeeName: 'Owner',
      branchLabel: 'Main',
      createdAt: DateTime.utc(2026, 10, 26, 8),
      localOperationId: 'old-operation',
      restoreGenerationAtCreation: 2,
    );
    final decision = await RestoreSubmissionPolicy.guardInvoice(
      tenantId: 'tenant-manual',
      invoice: invoice,
      currentGeneration: 3,
      restoreEpoch: DateTime.utc(2026, 10, 26, 9),
    );
    expect(decision.allowed, isTrue);
    final quarantined = await QuarantinedOperationStore('tenant-manual').list();
    expect(quarantined, isEmpty);
  });

  test(
    'restore snapshot removes stale remote invoice, adds restored invoice, and keeps draft',
    () async {
      SharedPreferences.setMockInitialValues({});
      final history = InvoiceHistoryStore();
      InvoiceDocument local(String id, {String serverId = ''}) =>
          InvoiceDocument(
            number: id,
            customerName: 'Customer',
            customerPhone: '',
            lines: const [
              InvoiceLine(name: 'Item', quantity: 1, unitPrice: 10),
            ],
            currency: 'YER',
            employeeName: 'Owner',
            branchLabel: 'Main',
            createdAt: DateTime.utc(2026, 10, 26),
            localOperationId: id,
            serverInvoiceId: serverId,
          );
      await history.save('tenant-snapshot', 'branch-1', local('draft'));
      await history.save(
        'tenant-snapshot',
        'branch-1',
        local('stale-C', serverId: 'server-C'),
      );
      final snapshot = <String, dynamic>{
        'snapshot_cursor': 50,
        'restore_generation': 2,
        'branch_ids': ['branch-1'],
        'products': <Object?>[],
        'contacts': <Object?>[],
        'business_documents': <Object?>[],
        'invoices': [
          {
            'id': 'server-B',
            'branch_id': 'branch-1',
            'number': 'INV-B',
            'local_operation_id': 'operation-B',
            'restore_generation': 1,
            'total_minor': 1000,
            'initial_paid_minor': 1000,
            'payment_mode_at_issue': 'cash',
            'occurred_at': '2026-10-25T10:00:00Z',
            'items': [
              {
                'product_name_snapshot': 'Restored item',
                'quantity_milli': 1000,
                'unit_price_minor': 1000,
              },
            ],
          },
        ],
      };
      final store = RestoreSnapshotStore(snapshotScope(restoreGeneration: 2));
      await store.stage(snapshot);
      expect(await store.pending(), isNotNull);
      // A fresh instance represents an application restart after the durable
      // journal was staged but before all local stores were replaced.
      final restartedStore = RestoreSnapshotStore(
        snapshotScope(restoreGeneration: 2),
      );
      await restartedStore.resume();
      expect(await store.pending(), isNull);
      final result = await history.read('tenant-snapshot', 'branch-1');
      expect(result.map((item) => item.serverInvoiceId), contains('server-B'));
      expect(
        result.map((item) => item.serverInvoiceId),
        isNot(contains('server-C')),
      );
      expect(result.map((item) => item.localOperationId), contains('draft'));
    },
  );

  test(
    'restore routes purchases away from sales history on every client',
    () async {
      SharedPreferences.setMockInitialValues({});
      final snapshot = <String, dynamic>{
        'snapshot_cursor': 80,
        'restore_generation': 3,
        'branch_ids': ['branch-1'],
        'products': <Object?>[],
        'contacts': <Object?>[],
        'business_documents': <Object?>[],
        'invoices': [
          {
            'id': 'sale-1',
            'type': 'sale',
            'branch_id': 'branch-1',
            'number': 'INV-1',
            'total_minor': 1000,
            'occurred_at': '2026-10-26T10:00:00Z',
            'items': [
              {
                'product_name_snapshot': 'Sold item',
                'quantity_milli': 1000,
                'unit_price_minor': 1000,
              },
            ],
          },
        ],
        'purchase_invoices': [
          {
            'id': 'purchase-1',
            'type': 'purchase',
            'branch_id': 'branch-1',
            'number': 'PUR-1',
            'total_minor': 500,
            'paid_minor': 200,
            'due_minor': 300,
            'supplier_name': 'Supplier',
            'items': [
              {
                'product_name_snapshot': 'Stock item',
                'quantity_milli': 1000,
                'unit_price_minor': 500,
              },
            ],
          },
        ],
      };
      final store = RestoreSnapshotStore(snapshotScope(restoreGeneration: 3));
      await store.stage(snapshot);
      await store.resume();

      final sales = await InvoiceHistoryStore().read(
        'tenant-snapshot',
        'branch-1',
      );
      final purchases = await PurchaseInvoiceStore().read(
        'tenant-snapshot',
        'branch-1',
      );
      expect(sales.map((item) => item.serverInvoiceId), ['sale-1']);
      expect(purchases.map((item) => item['id']), ['purchase-1']);
      expect(purchases.single['paid_minor'], 200);
      expect(purchases.single['due_minor'], 300);
    },
  );

  test(
    'restore journal is isolated by user branches and permissions',
    () async {
      SharedPreferences.setMockInitialValues({});
      final ownerScope = snapshotScope(
        branches: const ['branch-1', 'branch-2'],
        restoreGeneration: 4,
      );
      final employeeScope = snapshotScope(
        user: 'employee-2',
        branches: const ['branch-1'],
        permissions: const ['invoices.read'],
        restoreGeneration: 4,
      );
      final snapshot = <String, dynamic>{
        'snapshot_cursor': 90,
        'restore_generation': 4,
        'branch_ids': ['branch-1', 'branch-2'],
        'products': <Object?>[],
        'contacts': <Object?>[],
        'invoices': <Object?>[],
        'purchase_invoices': <Object?>[],
        'business_documents': <Object?>[],
      };
      final ownerStore = RestoreSnapshotStore(ownerScope);
      await ownerStore.stage(snapshot);

      final employeeStore = RestoreSnapshotStore(employeeScope);
      expect(await employeeStore.pending(), isNull);
      expect(await ownerStore.pending(), isNotNull);

      final newerGeneration = RestoreSnapshotStore(
        snapshotScope(
          branches: const ['branch-1', 'branch-2'],
          restoreGeneration: 5,
        ),
      );
      expect(await newerGeneration.pending(), isNull);
      expect(await ownerStore.pending(), isNotNull);

      final restartedOwner = RestoreSnapshotStore(ownerScope);
      await restartedOwner.resume();
      expect(await restartedOwner.pending(), isNull);
    },
  );

  test(
    'quarantine decisions are audited and never provide a repost action',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = QuarantinedOperationStore('tenant-review');
      await store.quarantine(
        operationId: 'review-1',
        kind: 'catalog',
        reason: 'created_before_restore',
        payload: {'name': 'Old item'},
      );
      await store.resolve(
        operationId: 'review-1',
        decision: 'discard',
        reviewer: 'Owner',
      );
      expect(await store.list(), isEmpty);
      final audit = await store.auditLog();
      expect(audit, hasLength(1));
      expect(audit.single['decision'], 'discard');
      expect(audit.single['reviewer'], 'Owner');
      expect(await store.isDiscarded('review-1', 'catalog'), isTrue);

      // Three later polling cycles and an application recreation cannot put
      // the terminally discarded operation back in the visible queue.
      for (var cycle = 0; cycle < 3; cycle++) {
        await QuarantinedOperationStore('tenant-review').quarantine(
          operationId: 'review-1',
          kind: 'catalog',
          reason: 'created_before_restore',
          payload: {'name': 'Old item'},
        );
      }
      final afterRestart = QuarantinedOperationStore('tenant-review');
      expect(await afterRestart.list(), isEmpty);
      expect(await afterRestart.isDiscarded('review-1', 'catalog'), isTrue);
    },
  );

  test(
    'keep decision remains visible without refreshing quarantine time',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = QuarantinedOperationStore('tenant-keep');
      await store.quarantine(
        operationId: 'keep-1',
        kind: 'invoice',
        reason: 'created_before_restore',
        payload: {'number': 'LOCAL-1'},
      );
      final originalTime = (await store.list()).single['quarantined_at'];
      await store.resolve(
        operationId: 'keep-1',
        decision: 'keep',
        reviewer: 'Owner',
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        await QuarantinedOperationStore('tenant-keep').quarantine(
          operationId: 'keep-1',
          kind: 'invoice',
          reason: 'created_before_restore',
          payload: {'number': 'LOCAL-1'},
        );
      }
      final visible = await QuarantinedOperationStore('tenant-keep').list();
      expect(visible, hasLength(1));
      expect(visible.single['quarantined_at'], originalTime);
    },
  );
}
