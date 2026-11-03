/// Single source of truth for deciding whether a NineSoft module can be
/// opened by the current session.
///
/// A write permission does not implicitly grant the list permission used by
/// the screen. Settlement creation is the one deliberate composite case: the
/// user needs both the settlement create permission and `invoices.read`,
/// because the workflow starts by loading the source invoices.
abstract final class NineSoftModuleAccessPolicy {
  static bool canOpen({
    required String moduleKey,
    required String roleCode,
    required Iterable<String> permissions,
    Iterable<String> branchIds = const <String>[],
  }) {
    if (roleCode == 'owner') return true;

    final granted = permissions is Set<String>
        ? permissions
        : permissions.toSet();
    bool has(String permission) => granted.contains(permission);
    bool hasAny(Iterable<String> required) => required.any(has);

    final canCreateReceipt = has('invoices.read') && has('receipts.create');
    final canCreatePayment = has('invoices.read') && has('payments.create');

    return switch (moduleKey) {
      // Invoice editors may still be useful to a create-only cashier. Their
      // history/list controls remain protected by the API permissions.
      'sales' || 'purchases.invoices' => hasAny(const [
        'invoices.read',
        'invoices.create',
      ]),
      'purchases' => hasAny(const [
        'invoices.read',
        'invoices.create',
        'documents.read',
      ]),
      // Return workspaces begin by listing source invoices.
      'sales.returns' || 'purchases.returns' => has('invoices.read'),
      // Purchase orders remain descriptive; accounting opening/year screens now
      // use the protected real-ledger endpoints (writes stay owner-only).
      'purchases.orders' => has('documents.read'),
      'accounts.years' || 'accounts.opening' => has('invoices.read'),
      'purchases.receiving' => has('invoices.read') || has('invoices.create'),

      // These screens are list/report driven and therefore require read.
      'accounts' => hasAny(const ['invoices.read', 'documents.read']),
      'accounts.accounts' ||
      'accounts.journals' ||
      'accounts.statements' ||
      'accounts.financial' ||
      'accounts.transfers' ||
      'reports' => has('invoices.read'),
      _ when moduleKey.startsWith('reports.') => has('invoices.read'),
      'cashbox' => has('invoices.read'),
      'products' => has('catalog.read'),
      'customers' || 'suppliers' => has('contacts.read'),
      'payroll' => hasAny(const [
        'payroll.read',
        'payroll.manage',
        'payroll.advance',
        'payroll.approve',
        'payroll.pay',
      ]),

      'debts' =>
        has('invoices.read') ||
            has('receipts.read') ||
            canCreateReceipt ||
            has('payments.read') ||
            canCreatePayment ||
            has('documents.read'),
      'debts.dues' => has('invoices.read'),
      'debts.receipts' => has('receipts.read') || canCreateReceipt,
      'debts.payments' => has('payments.read') || canCreatePayment,
      'debts.exchange' => has('documents.read'),

      'inventory' => hasAny(const [
        'invoices.read',
        'documents.read',
        'catalog.read',
      ]),
      'inventory.inquiry' => has('catalog.read'),
      'inventory.movements' ||
      'inventory.valuation' ||
      'inventory.reports' => has('invoices.read'),
      'inventory.warehouses' => has('documents.read'),
      'inventory.transfers' || 'inventory.counts' =>
        has('catalog.read') && (has('catalog.write') || has('invoices.read')),

      'settings' => has('branch.identity.update'),
      'whatsapp' => branchIds.isNotEmpty,
      'wasl' => granted.any((value) => value.startsWith('wasl.')),

      // Administration remains owner-only.
      'users' || 'branches' || 'backup' => false,
      _ => false,
    };
  }

  static bool canCreateSettlement({
    required String moduleKey,
    required String roleCode,
    required Iterable<String> permissions,
  }) {
    if (roleCode == 'owner') return true;
    final granted = permissions is Set<String>
        ? permissions
        : permissions.toSet();
    if (!granted.contains('invoices.read')) return false;
    return switch (moduleKey) {
      'debts.receipts' => granted.contains('receipts.create'),
      'debts.payments' => granted.contains('payments.create'),
      _ => false,
    };
  }
}
