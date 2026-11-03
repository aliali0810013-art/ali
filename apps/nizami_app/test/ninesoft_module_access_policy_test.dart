import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/navigation/ninesoft_module_access_policy.dart';

void main() {
  test(
    'payroll module accepts read or exact delegated workflow permissions',
    () {
      for (final permission in const [
        'payroll.read',
        'payroll.manage',
        'payroll.advance',
        'payroll.approve',
        'payroll.pay',
      ]) {
        expect(
          NineSoftModuleAccessPolicy.canOpen(
            moduleKey: 'payroll',
            roleCode: 'cashier',
            permissions: [permission],
          ),
          isTrue,
          reason: permission,
        );
      }
      expect(
        NineSoftModuleAccessPolicy.canOpen(
          moduleKey: 'payroll',
          roleCode: 'cashier',
          permissions: const ['invoices.read'],
        ),
        isFalse,
      );
      expect(
        NineSoftModuleAccessPolicy.canOpen(
          moduleKey: 'payroll',
          roleCode: 'owner',
          permissions: const [],
        ),
        isTrue,
      );
    },
  );

  bool canOpen(String key, List<String> permissions) =>
      NineSoftModuleAccessPolicy.canOpen(
        moduleKey: key,
        roleCode: 'cashier',
        permissions: permissions,
        branchIds: const ['branch-1'],
      );

  group('read-driven modules', () {
    final cases = <({String key, String read, String write})>[
      (key: 'accounts', read: 'invoices.read', write: 'invoices.create'),
      (key: 'reports.sales', read: 'invoices.read', write: 'invoices.create'),
      (key: 'cashbox', read: 'invoices.read', write: 'invoices.create'),
      (key: 'products', read: 'catalog.read', write: 'catalog.write'),
      (key: 'customers', read: 'contacts.read', write: 'contacts.write'),
      (
        key: 'inventory.movements',
        read: 'invoices.read',
        write: 'documents.create',
      ),
    ];

    for (final item in cases) {
      test('${item.key} accepts read-only and rejects write-only', () {
        expect(canOpen(item.key, [item.read]), isTrue);
        expect(canOpen(item.key, [item.write]), isFalse);
      });
    }
  });

  group('invoice editors', () {
    test(
      'sales and purchase invoice editors remain available to create-only',
      () {
        expect(canOpen('sales', const ['invoices.create']), isTrue);
        expect(
          canOpen('purchases.invoices', const ['invoices.create']),
          isTrue,
        );
      },
    );

    test('return workspaces require source invoice read access', () {
      expect(canOpen('sales.returns', const ['invoices.create']), isFalse);
      expect(canOpen('sales.returns', const ['invoices.read']), isTrue);
      expect(canOpen('purchases.returns', const ['invoices.create']), isFalse);
      expect(canOpen('purchases.returns', const ['invoices.read']), isTrue);
    });
  });

  group('business document modules', () {
    test('purchase orders require document read rather than create', () {
      expect(canOpen('purchases.orders', const ['documents.read']), isTrue);
      expect(canOpen('purchases.orders', const ['documents.create']), isFalse);
      expect(canOpen('purchases.orders', const ['invoices.read']), isFalse);
    });

    test('real-ledger administration screens require accounting read', () {
      for (final key in const ['accounts.opening', 'accounts.years']) {
        expect(canOpen(key, const ['invoices.read']), isTrue);
        expect(canOpen(key, const ['documents.read']), isFalse);
      }
    });

    test('purchase receiving follows the canonical invoice workflow', () {
      expect(canOpen('purchases.receiving', const ['invoices.read']), isTrue);
      expect(canOpen('purchases.receiving', const ['invoices.create']), isTrue);
      expect(canOpen('purchases.receiving', const ['documents.read']), isFalse);
    });

    test('parent hubs admit the read permission of any visible child', () {
      expect(canOpen('purchases', const ['documents.read']), isTrue);
      expect(canOpen('accounts', const ['documents.read']), isTrue);
      expect(canOpen('accounts', const ['invoices.read']), isTrue);
    });
  });

  group('settlement permissions', () {
    test('read-only can list its canonical settlement register', () {
      expect(canOpen('debts.receipts', const ['receipts.read']), isTrue);
      expect(canOpen('debts.payments', const ['payments.read']), isTrue);
    });

    test('create-only cannot start a workflow that must list invoices', () {
      expect(canOpen('debts.receipts', const ['receipts.create']), isFalse);
      expect(canOpen('debts.payments', const ['payments.create']), isFalse);
      expect(
        NineSoftModuleAccessPolicy.canCreateSettlement(
          moduleKey: 'debts.receipts',
          roleCode: 'cashier',
          permissions: const ['receipts.create'],
        ),
        isFalse,
      );
    });

    test('invoice read plus create admits the matching settlement only', () {
      final permissions = const ['invoices.read', 'receipts.create'];
      expect(canOpen('debts.receipts', permissions), isTrue);
      expect(canOpen('debts.payments', permissions), isFalse);
      expect(
        NineSoftModuleAccessPolicy.canCreateSettlement(
          moduleKey: 'debts.receipts',
          roleCode: 'cashier',
          permissions: permissions,
        ),
        isTrue,
      );
      expect(
        NineSoftModuleAccessPolicy.canCreateSettlement(
          moduleKey: 'debts.payments',
          roleCode: 'cashier',
          permissions: permissions,
        ),
        isFalse,
      );
    });
  });

  test('owner access remains unrestricted', () {
    expect(
      NineSoftModuleAccessPolicy.canOpen(
        moduleKey: 'backup',
        roleCode: 'owner',
        permissions: const [],
      ),
      isTrue,
    );
  });
}
