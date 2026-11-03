import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../theme/nizami_theme.dart';
import '../../theme/ninesoft_ui.dart';
import '../customers/customer_store.dart';
import '../invoices/invoice_history_store.dart';
import '../invoices/invoice_pdf_service.dart';
import '../modules/module_workspace_page.dart';
import '../products/product_catalog_store.dart';
import '../purchases/purchase_invoice_store.dart';
import '../sync/realtime_sync_coordinator.dart';

/// NineSoft reference identity, UI only. Reads the LOCAL synchronized cache.
/// This class never posts an invoice, changes a balance or touches the API.
class NineSoftReferenceDashboard extends StatefulWidget {
  const NineSoftReferenceDashboard({
    super.key,
    required this.tenantName,
    required this.tenantId,
    required this.displayName,
    required this.branchIds,
    required this.modules,
    required this.onOpen,
    required this.statusIndicator,
    this.onOpenApps,
    this.onSearchApps,
  });

  final String tenantName;
  final String tenantId;
  final String displayName;
  final List<String> branchIds;
  final List<ModuleDefinition> modules;
  final ValueChanged<String> onOpen;
  final Widget statusIndicator;
  final VoidCallback? onOpenApps;
  final ValueChanged<String>? onSearchApps;

  @override
  State<NineSoftReferenceDashboard> createState() =>
      _NineSoftReferenceDashboardState();
}

class _NineSoftReferenceDashboardState
    extends State<NineSoftReferenceDashboard> {
  late Future<_LocalOverview> _overview;
  StreamSubscription<Set<String>>? _changeListener;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _overview = _loadOverview();
    // The existing sync coordinator owns the protocol. We only refresh the UI.
    _changeListener = RealtimeSyncCoordinator.instance.changes.listen((types) {
      if (types.intersection({
            'invoice',
            'purchase',
            'product',
            'contact',
          }).isNotEmpty &&
          mounted) {
        setState(() => _overview = _loadOverview());
      }
    });
  }

  @override
  void didUpdateWidget(covariant NineSoftReferenceDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId ||
        oldWidget.tenantName != widget.tenantName ||
        !_sameBranches(oldWidget.branchIds, widget.branchIds) ||
        !_sameModules(oldWidget.modules, widget.modules)) {
      _overview = _loadOverview();
    }
  }

  static bool _sameBranches(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);

  static bool _sameModules(
    List<ModuleDefinition> a,
    List<ModuleDefinition> b,
  ) =>
      a.length == b.length &&
      a.map((m) => m.key).toSet().containsAll(b.map((m) => m.key));

  @override
  void dispose() {
    _changeListener?.cancel();
    super.dispose();
  }

  void _refresh() => setState(() => _overview = _loadOverview());

  Future<_LocalOverview> _loadOverview() async {
    final scope = widget.tenantId.isEmpty ? widget.tenantName : widget.tenantId;
    final sales = <InvoiceDocument>[];
    final canSee = widget.modules.map((m) => m.key).toSet();
    final purchases = <Map<String, dynamic>>[];
    // Do not invent another branch when the authenticated session has none.
    for (final branch in widget.branchIds.toSet()) {
      if (canSee.contains('sales')) {
        sales.addAll(await InvoiceHistoryStore().read(scope, branch));
      }
      if (canSee.contains('purchases')) {
        purchases.addAll(await PurchaseInvoiceStore().read(scope, branch));
      }
    }
    final products = canSee.contains('products') || canSee.contains('inventory')
        ? await ProductCatalogStore(scope).read()
        : <CatalogProduct>[];
    final customers = canSee.contains('customers')
        ? await CustomerStore(scope).read()
        : <SavedCustomer>[];
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final start = midnight.subtract(const Duration(days: 6));
    final weeklyCounts = List<int>.filled(7, 0);
    final recent = <_RecentRow>[];
    int salesMinor = 0;
    int purchaseMinor = 0;
    int pricedSales = 0;
    int pricedPurchases = 0;

    for (final invoice in sales) {
      if (invoice.postedToServer &&
          invoice.serverTotalMinor != null &&
          invoice.currency == 'YER') {
        salesMinor += invoice.serverTotalMinor!;
        pricedSales++;
      }
      if (invoice.createdAt.isAfter(start) ||
          invoice.createdAt.isAtSameMomentAs(start)) {
        final offset = invoice.createdAt.difference(start).inDays;
        if (offset >= 0 && offset < 7 && invoice.postedToServer) {
          weeklyCounts[offset]++;
        }
      }
      recent.add(
        _RecentRow(
          title: 'فاتورة بيع ${invoice.displayNumber}',
          description: invoice.customerName.trim().isEmpty
              ? 'عميل نقدي'
              : invoice.customerName,
          timestamp: invoice.createdAt,
          icon: Icons.receipt_long_rounded,
          keyName: 'sales',
          color: const Color(0xFF0AAE90),
        ),
      );
    }
    for (final purchase in purchases) {
      final minor = (purchase['total_minor'] as num?)?.toInt();
      if (minor != null) {
        purchaseMinor += minor;
        pricedPurchases++;
      }
      final when = DateTime.tryParse(
        purchase['created_at']?.toString() ??
            purchase['issued_at']?.toString() ??
            '',
      );
      if (when != null) {
        recent.add(
          _RecentRow(
            title:
                'فاتورة شراء ${purchase['number'] ?? purchase['invoice_number'] ?? ''}',
            description: (purchase['supplier_name'] ?? 'مورد').toString(),
            timestamp: when,
            icon: Icons.shopping_cart_rounded,
            keyName: 'purchases',
            color: const Color(0xFF1279D9),
          ),
        );
      }
    }
    recent.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return _LocalOverview(
      salesMinor: pricedSales == 0 ? null : salesMinor,
      purchaseMinor: pricedPurchases == 0 ? null : purchaseMinor,
      customerCount: customers.length,
      productCount: products.length,
      lowStockCount: products
          .where(
            (product) =>
                product.stockQuantity != null && product.stockQuantity! <= 5,
          )
          .length,
      weeklyCounts: weeklyCounts,
      recent: recent.take(5).toList(growable: false),
    );
  }

  static const _moduleOrder = <String>[
    'sales',
    'purchases',
    'products',
    'customers',
    'suppliers',
    'inventory',
    'debts',
    'cashbox',
    'accounts',
    'reports',
    'wasl',
    'whatsapp',
    'users',
    'branches',
    'backup',
    'sales.returns',
    'settings',
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final narrow = width < 620;
      final modules = [...widget.modules]
        ..sort((a, b) {
          final ai = _moduleOrder.indexOf(a.key);
          final bi = _moduleOrder.indexOf(b.key);
          return (ai < 0 ? 999 : ai).compareTo(bi < 0 ? 999 : bi);
        });
      final filtered = _query.trim().isEmpty
          ? modules
          : modules
                .where(
                  (module) =>
                      module.title.contains(_query.trim()) ||
                      module.entityLabel.contains(_query.trim()),
                )
                .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('dashboard-command-search'),
            onChanged: (value) => setState(() => _query = value),
            onSubmitted: (value) {
              final search = value.trim();
              if (search.isNotEmpty && filtered.length == 1) {
                widget.onOpen(filtered.first.key);
              } else if (search.isNotEmpty) {
                widget.onSearchApps?.call(search);
              } else {
                widget.onOpenApps?.call();
              }
            },
            decoration: InputDecoration(
              hintText: 'بحث سريع عن قسم أو خدمة...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'عرض كل الأقسام',
                icon: const Icon(Icons.grid_view_rounded),
                onPressed: widget.onOpenApps,
              ),
            ),
          ),
          if (!narrow) ...[
            const SizedBox(height: 14),
            _HeaderCaption(
              text: 'لمحة عن نشاطك',
              action: IconButton(
                onPressed: _refresh,
                tooltip: 'تحديث المؤشرات من النسخة المحلية',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ],
          const SizedBox(height: 9),
          FutureBuilder<_LocalOverview>(
            future: _overview,
            builder: (context, state) {
              final overview = state.data;
              final visibleOverview =
                  overview ??
                  (state.hasError
                      ? const _LocalOverview(
                          salesMinor: null,
                          purchaseMinor: null,
                          customerCount: 0,
                          productCount: 0,
                          lowStockCount: 0,
                          weeklyCounts: [0, 0, 0, 0, 0, 0, 0],
                          recent: [],
                        )
                      : null);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.hasError) ...[
                    _OverviewUnavailable(onRefresh: _refresh),
                    const SizedBox(height: 10),
                  ],
                  GridView.count(
                    key: const Key('dashboard-overview-grid'),
                    crossAxisCount: width < 620 ? 2 : 4,
                    crossAxisSpacing: width < 600 ? 8 : 10,
                    mainAxisSpacing: width < 600 ? 8 : 10,
                    childAspectRatio: width >= 1100
                        ? 1.75
                        : width >= 780
                            ? 1.30
                            : 1.18,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _OverviewCard(
                        key: const Key('overview-sales-card'),
                        title: 'المبيعات',
                        value:
                            !widget.modules.any((m) => m.key == 'sales') ||
                                overview?.salesMinor == null
                            ? '—'
                            : _money(overview!.salesMinor!),
                        subLabel: 'ر.ي • مخزنة محلياً',
                        icon: Icons.local_atm_rounded,
                        color: const Color(0xFF1689F8),
                        onTap: () => widget.onOpen('sales'),
                      ),
                      _OverviewCard(
                        key: const Key('overview-purchases-card'),
                        title: 'المشتريات',
                        value:
                            !widget.modules.any((m) => m.key == 'purchases') ||
                                overview?.purchaseMinor == null
                            ? '—'
                            : _money(overview!.purchaseMinor!),
                        subLabel: 'ر.ي • مخزنة محلياً',
                        icon: Icons.shopping_cart_rounded,
                        color: const Color(0xFFEF4661),
                        onTap: () => widget.onOpen('purchases'),
                      ),
                      _OverviewCard(
                        key: const Key('overview-products-card'),
                        title: 'الأصناف',
                        value:
                            overview == null ||
                                !widget.modules.any(
                                  (m) =>
                                      m.key == 'products' ||
                                      m.key == 'inventory',
                                )
                            ? '—'
                            : _fmt(overview.productCount),
                        subLabel: 'صنف في الجهاز',
                        icon: Icons.inventory_2_rounded,
                        color: const Color(0xFFF07C17),
                        onTap: () => widget.onOpen('products'),
                      ),
                      _OverviewCard(
                        key: const Key('overview-customers-card'),
                        title: 'العملاء',
                        value:
                            overview == null ||
                                !widget.modules.any((m) => m.key == 'customers')
                            ? '—'
                            : _fmt(overview.customerCount),
                        subLabel: 'عميل في الجهاز',
                        icon: Icons.groups_rounded,
                        color: const Color(0xFF118FC8),
                        onTap: () => widget.onOpen('customers'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _QuickActions(modules: widget.modules, onOpen: widget.onOpen),
                  const SizedBox(height: 10),
                  _FeatureShortcuts(
                    modules: widget.modules,
                    onOpen: widget.onOpen,
                  ),
                  if (narrow) ...[
                    const SizedBox(height: 12),
                    Column(
                      key: const Key('dashboard-phone-operations'),
                      children: [
                        _RecentActivity(
                          overview: visibleOverview,
                          onOpen: widget.onOpen,
                        ),
                        const SizedBox(height: 10),
                        _AttentionPanel(
                          lowStock: overview?.lowStockCount,
                          onInventory: () => widget.onOpen('products'),
                          modules: widget.modules,
                        ),
                      ],
                    ),
                  ],
                  if (!narrow) ...[
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _RecentActivity(
                            overview: visibleOverview,
                            onOpen: widget.onOpen,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _WeeklyChart(values: overview?.weeklyCounts),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _AttentionPanel(
                      lowStock: overview?.lowStockCount,
                      onInventory: () => widget.onOpen('products'),
                      modules: widget.modules,
                    ),
                  ],
                ],
              );
            },
          ),
          if (!narrow) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text('حالة الخدمات', style: _headingStyle(context)),
                const Spacer(),
                widget.statusIndicator,
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'المؤشرات أعلاه مستمدة من السجلات المتزامنة المحفوظة على هذا الجهاز، وليست تقريراً مالياً نهائياً لكل الفروع. افتح التقارير للحصول على البيانات الرسمية.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ],
      );
    },
  );
}

// Monetary values are formatted from INTEGER minor units; no floating ledger math.
String _money(int minor) {
  final negative = minor < 0 ? '-' : '';
  final whole = minor.abs() ~/ 100;
  final cents = minor.abs() % 100;
  final amount = NumberFormat.decimalPattern('en').format(whole);
  return cents == 0
      ? '$negative$amount'
      : '$negative$amount.${cents.toString().padLeft(2, '0')}';
}

String _fmt(int value) => NumberFormat.decimalPattern('en').format(value);
TextStyle _headingStyle(BuildContext context) => TextStyle(
  fontFamily: 'GESS',
  color: Theme.of(context).colorScheme.onSurface,
  fontSize: 18,
  fontWeight: FontWeight.w700,
);

class _LocalOverview {
  const _LocalOverview({
    required this.salesMinor,
    required this.purchaseMinor,
    required this.customerCount,
    required this.productCount,
    required this.lowStockCount,
    required this.weeklyCounts,
    required this.recent,
  });
  final int? salesMinor, purchaseMinor;
  final int customerCount, productCount, lowStockCount;
  final List<int> weeklyCounts;
  final List<_RecentRow> recent;
}

class _RecentRow {
  const _RecentRow({
    required this.title,
    required this.description,
    required this.timestamp,
    required this.icon,
    required this.keyName,
    required this.color,
  });
  final String title, description, keyName;
  final DateTime timestamp;
  final IconData icon;
  final Color color;
}

// Retained for possible desktop-only reuse; excluded from the compact home.
// ignore: unused_element
class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({required this.tenantName, required this.displayName});
  final String tenantName, displayName;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 460;
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 13 : 18,
          vertical: 11,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDCE9F6)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFE7F2FF),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.waving_hand_rounded,
                color: Color(0xFF147BE0),
                size: 21,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مرحباً بك في ${tenantName.trim().isEmpty ? 'ناين سوفت' : tenantName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'GESS',
                      fontSize: compact ? 12 : 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F8FE),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_month_rounded,
                    size: 17,
                    color: Color(0xFF147BE0),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    DateFormat('yyyy/MM/dd').format(DateTime.now()),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _HeaderCaption extends StatelessWidget {
  const _HeaderCaption({required this.text, this.action});
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(text, style: _headingStyle(context))),
      ?action,
    ],
  );
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    super.key,
    required this.title,
    required this.value,
    required this.subLabel,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String title, value, subLabel;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    return Material(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(compact ? 17 : 20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: compact ? 8 : 12,
            horizontal: compact ? 4 : 11,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 17 : 20),
            border: Border.all(color: color.withValues(alpha: .14)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: compact ? 34 : 52,
                height: compact ? 34 : 49,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: .82), color],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(compact ? 11 : 16),
                ),
                child: Icon(icon, color: Colors.white, size: compact ? 20 : 29),
              ),
              SizedBox(height: compact ? 4 : 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'GESS',
                  fontSize: compact ? 10 : 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: compact ? 2 : 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: compact ? 13 : 21,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              if (!compact)
                Text(
                  subLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _hasRoot(List<ModuleDefinition> modules, String root) =>
    modules.any((module) => module.key == root);

class _QuickActionDefinition {
  const _QuickActionDefinition({
    required this.keyName,
    required this.label,
    required this.moduleKey,
    required this.requiredRoot,
    required this.icon,
    required this.colors,
  });

  final String keyName;
  final String label;
  final String moduleKey;
  final String requiredRoot;
  final IconData icon;
  final List<Color> colors;
}

const _quickActions = <_QuickActionDefinition>[
  _QuickActionDefinition(
    keyName: 'fast-invoice',
    label: 'فاتورة\nسريعة',
    moduleKey: 'sales',
    requiredRoot: 'sales',
    icon: Icons.point_of_sale_rounded,
    colors: [Color(0xFF1689F8), Color(0xFF075BC7)],
  ),
  _QuickActionDefinition(
    keyName: 'invoice',
    label: 'تحرير\nفاتورة',
    moduleKey: 'sales',
    requiredRoot: 'sales',
    icon: Icons.edit_square,
    colors: [Color(0xFF13B39E), Color(0xFF048273)],
  ),
  _QuickActionDefinition(
    keyName: 'receipt',
    label: 'سند\nقبض',
    moduleKey: 'debts.receipts',
    requiredRoot: 'debts',
    icon: Icons.move_to_inbox_rounded,
    colors: [Color(0xFF2CCB68), Color(0xFF049743)],
  ),
  _QuickActionDefinition(
    keyName: 'payment',
    label: 'سند\nصرف',
    moduleKey: 'debts.payments',
    requiredRoot: 'debts',
    icon: Icons.outbox_rounded,
    colors: [Color(0xFFF46270), Color(0xFFD72E43)],
  ),
  _QuickActionDefinition(
    keyName: 'journal',
    label: 'قيد\nسريع',
    moduleKey: 'accounts.journals',
    requiredRoot: 'accounts',
    icon: Icons.note_alt_rounded,
    colors: [Color(0xFFFFB62F), Color(0xFFF08A00)],
  ),
  _QuickActionDefinition(
    keyName: 'customer',
    label: 'إضافة\nعميل',
    moduleKey: 'customers',
    requiredRoot: 'customers',
    icon: Icons.person_add_rounded,
    colors: [Color(0xFFA65BE9), Color(0xFF7133C7)],
  ),
];

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.modules, required this.onOpen});

  final List<ModuleDefinition> modules;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final actions = _quickActions
        .where((action) => _hasRoot(modules, action.requiredRoot))
        .toList(growable: false);
    if (actions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFFFFA000)),
            const SizedBox(width: 5),
            Expanded(
              child: Text('إجراءات سريعة', style: _headingStyle(context)),
            ),
            if (MediaQuery.sizeOf(context).width >= 700)
              Text(
                'تفتح المحرر الحقيقي مباشرة',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        const SizedBox(height: 9),
        LayoutBuilder(
          builder: (context, constraints) => GridView.count(
            key: const Key('dashboard-quick-action-grid'),
            crossAxisCount: constraints.maxWidth < 620 ? 3 : 6,
            crossAxisSpacing: constraints.maxWidth < 620 ? 7 : 10,
            mainAxisSpacing: 7,
            childAspectRatio: constraints.maxWidth < 620
                ? 1.05
                : constraints.maxWidth < 820
                    ? 1.25
                    : 1.55,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final action in actions)
                _QuickActionCard(
                  key: Key('quick-action-${action.keyName}'),
                  action: action,
                  onTap: () => onOpen(action.moduleKey),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    super.key,
    required this.action,
    required this.onTap,
  });

  final _QuickActionDefinition action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: Ink(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: action.colors,
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: action.colors.last.withValues(alpha: .20),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                key: Key('quick-action-icon-${action.keyName}'),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .22),
                  ),
                ),
                child: Icon(action.icon, color: Colors.white, size: 21),
              ),
              const SizedBox(height: 5),
              Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'GESS',
                  fontSize: 10,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FeatureShortcuts extends StatelessWidget {
  const _FeatureShortcuts({required this.modules, required this.onOpen});

  final List<ModuleDefinition> modules;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (modules.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF0C6FD3).withValues(alpha: .10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                color: Color(0xFF0C6FD3),
                size: 19,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('الأقسام الرئيسية', style: _headingStyle(context)),
            ),
            Text(
              '${modules.length} قسم',
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 520
                ? 4
                : constraints.maxWidth < 820
                    ? 5
                    : constraints.maxWidth < 1180
                        ? 6
                        : 8;
            return GridView.builder(
              key: const Key('dashboard-feature-shortcut-grid'),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: constraints.maxWidth < 620 ? 7 : 11,
                mainAxisSpacing: constraints.maxWidth < 620 ? 10 : 12,
                childAspectRatio: constraints.maxWidth < 620 ? .82 : .92,
              ),
              itemCount: modules.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final module = modules[index];
                return _HomeAppIcon(
                  key: Key(
                    'feature-shortcut-${module.key.replaceAll('.', '-')}',
                  ),
                  module: module,
                  onTap: () => onOpen(module.key),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _HomeAppIcon extends StatelessWidget {
  const _HomeAppIcon({
    super.key,
    required this.module,
    required this.onTap,
  });

  final ModuleDefinition module;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 620;
    final iconSize = compact ? 56.0 : 62.0;
    return Tooltip(
      message: module.actionLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      module.color.withValues(alpha: .76),
                      module.color,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(compact ? 17 : 19),
                  boxShadow: [
                    BoxShadow(
                      color: module.color.withValues(alpha: .18),
                      blurRadius: 13,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(
                  module.icon,
                  color: Colors.white,
                  size: compact ? 27 : 30,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                module.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'GESS',
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 9.5 : 10.5,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Legacy desktop reference kept out of the compact home composition.
// ignore: unused_element
class _EntryPreviews extends StatelessWidget {
  const _EntryPreviews({required this.modules, required this.onOpen});

  final List<ModuleDefinition> modules;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      if (_hasRoot(modules, 'sales'))
        _EntryPreviewCard(
          key: const Key('dashboard-invoice-preview'),
          title: 'تحرير فاتورة',
          subtitle: 'العميل والأصناف والوحدات داخل المحرر الكامل',
          icon: Icons.receipt_long_rounded,
          color: const Color(0xFF147BE0),
          details: const [
            ('العميل', 'اختيار مسجل أو عميل نقدي'),
            ('الأصناف', 'بحث وباركود ووحدات'),
          ],
          actionLabel: 'فتح محرر الفاتورة',
          onPressed: () => onOpen('sales'),
        ),
      if (_hasRoot(modules, 'debts'))
        _VoucherPreview(
          key: const Key('dashboard-voucher-preview'),
          onReceipt: () => onOpen('debts.receipts'),
          onPayment: () => onOpen('debts.payments'),
        ),
      if (_hasRoot(modules, 'accounts'))
        _EntryPreviewCard(
          key: const Key('dashboard-journal-preview'),
          title: 'قيد محاسبي',
          subtitle: 'طرفان متساويان حتى يظل القيد متوازنًا',
          icon: Icons.menu_book_rounded,
          color: const Color(0xFF13A260),
          details: const [
            ('مدين', 'الحساب المدين — المستفيد أو المستلم'),
            ('دائن', 'الحساب الدائن — مصدر المبلغ'),
            ('التوازن', 'الفرق بين الطرفين يجب أن يكون صفرًا'),
          ],
          actionLabel: 'فتح القيد السريع',
          onPressed: () => onOpen('accounts.journals'),
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth >= 940
            ? 3
            : constraints.maxWidth >= 350
            ? 2
            : 1;
        final spacing = 10.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (count - 1))) / count;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards) SizedBox(width: itemWidth, child: card),
          ],
        );
      },
    );
  }
}

class _EntryPreviewCard extends StatelessWidget {
  const _EntryPreviewCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.details,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<(String, String)> details;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => NineSoftPanel(
    padding: const EdgeInsets.all(13),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _headingStyle(context)),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final detail in details)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .055),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: .12)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 55,
                    child: Text(
                      detail.$1,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      detail.$2,
                      style: const TextStyle(fontSize: 11, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
        FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(backgroundColor: color),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(actionLabel),
        ),
      ],
    ),
  );
}

class _VoucherPreview extends StatelessWidget {
  const _VoucherPreview({
    super.key,
    required this.onReceipt,
    required this.onPayment,
  });

  final VoidCallback onReceipt;
  final VoidCallback onPayment;

  @override
  Widget build(BuildContext context) => NineSoftPanel(
    padding: const EdgeInsets.all(13),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF147BE0).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.payments_rounded,
                color: Color(0xFF147BE0),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('سند قبض أو صرف', style: _headingStyle(context)),
                  Text(
                    'اختر الحركة ثم يكمل النظام القيد من المحرر الحقيقي',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _VoucherChoice(
          color: const Color(0xFF13A260),
          icon: Icons.south_west_rounded,
          title: 'سند قبض',
          subtitle: 'استلام مبلغ إلى الصندوق أو البنك',
          onTap: onReceipt,
        ),
        const SizedBox(height: 8),
        _VoucherChoice(
          color: const Color(0xFFE04455),
          icon: Icons.north_east_rounded,
          title: 'سند صرف',
          subtitle: 'دفع مبلغ من الصندوق أو البنك',
          onTap: onPayment,
        ),
      ],
    ),
  );
}

class _VoucherChoice extends StatelessWidget {
  const _VoucherChoice({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: .065),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_left_rounded, color: color),
          ],
        ),
      ),
    ),
  );
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.values});
  final List<int>? values;

  @override
  Widget build(BuildContext context) => NineSoftPanel(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.insert_chart_rounded, color: NizamiColors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text('نشاط فواتير البيع', style: _headingStyle(context)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'عدد الفواتير المرحّلة محلياً آخر 7 أيام',
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 135,
          width: double.infinity,
          child: values == null
              ? const Center(child: CircularProgressIndicator.adaptive())
              : CustomPaint(
                  painter: _ActivityGraphPainter(
                    values: values!,
                    line: NizamiColors.tealDark,
                    fill: NizamiColors.teal.withValues(alpha: .12),
                    grid: Theme.of(context).dividerColor,
                  ),
                ),
        ),
        const SizedBox(height: 9),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 6; i >= 0; i--)
              Text(
                '${DateTime.now().subtract(Duration(days: i)).day}',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _ActivityGraphPainter extends CustomPainter {
  _ActivityGraphPainter({
    required this.values,
    required this.line,
    required this.fill,
    required this.grid,
  });
  final List<int> values;
  final Color line, fill, grid;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    final axis = Paint()
      ..color = grid.withValues(alpha: .45)
      ..strokeWidth = 1;
    for (final tick in [0.0, .33, .66, 1.0]) {
      canvas.drawLine(
        Offset(bounds.left, bounds.top + bounds.height * tick),
        Offset(bounds.right, bounds.top + bounds.height * tick),
        axis,
      );
    }
    if (values.isEmpty) return;
    final maxValue = math.max(1, values.reduce(math.max));
    final pointStep = values.length <= 1
        ? 0.0
        : size.width / (values.length - 1);
    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          i * pointStep,
          size.height - 12 - (size.height - 24) * values[i] / maxValue,
        ),
    ];
    final stroke = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final old = points[i - 1];
      final next = points[i];
      final middle = (old.dx + next.dx) / 2;
      stroke.cubicTo(middle, old.dy, middle, next.dy, next.dx, next.dy);
    }
    final area = Path.from(stroke)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(stroke, linePaint);
    for (final point in points) {
      canvas.drawCircle(point, 4.5, Paint()..color = line);
      canvas.drawCircle(point, 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _ActivityGraphPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.line != line ||
      oldDelegate.grid != grid;
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.overview, required this.onOpen});
  final _LocalOverview? overview;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => NineSoftPanel(
    padding: const EdgeInsets.all(15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.schedule_rounded, color: NizamiColors.blue),
            const SizedBox(width: 9),
            Text('آخر العمليات', style: _headingStyle(context)),
          ],
        ),
        const SizedBox(height: 11),
        if (overview == null)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else if (overview!.recent.isEmpty)
          const Padding(
            padding: EdgeInsets.all(25),
            child: Text(
              'لا توجد مستندات محفوظة محلياً بعد.',
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final row in overview!.recent) ...[
            Material(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: .04)
                  : const Color(0xFFF9FCFF),
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: () => onOpen(row.keyName),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: row.color.withValues(alpha: .11),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(row.icon, color: row.color, size: 22),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'GESS',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              row.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('MM/dd').format(row.timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
          ],
      ],
    ),
  );
}

class _AttentionPanel extends StatelessWidget {
  const _AttentionPanel({
    required this.lowStock,
    required this.onInventory,
    required this.modules,
  });
  final int? lowStock;
  final VoidCallback onInventory;
  final List<ModuleDefinition> modules;

  bool _permitted(String key) => modules.any((m) => m.key == key);
  @override
  Widget build(BuildContext context) => NineSoftPanel(
    color: Theme.of(context).brightness == Brightness.dark
        ? null
        : const Color(0xFFFFF7F7),
    padding: const EdgeInsets.all(15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.notifications_active_outlined,
              color: Color(0xFFDA3540),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('تنبيهات العمل', style: _headingStyle(context)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (lowStock == null)
          const Text('جارٍ قراءة بيانات المخزون المحلية...')
        else if (lowStock == 0)
          const Text(
            'لا توجد أصناف برصيد 5 أو أقل في البيانات المحلية المتاحة.',
          )
        else if (_permitted('products'))
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(
                Icons.inventory_2_outlined,
                color: Color(0xFFF07819),
              ),
              title: Text('أصناف برصيد منخفض: $lowStock'),
              subtitle: const Text('معيار تنبيه العرض: كمية 5 أو أقل'),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: onInventory,
            ),
          ),
      ],
    ),
  );
}

class _OverviewUnavailable extends StatelessWidget {
  const _OverviewUnavailable({required this.onRefresh});
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) => NineSoftPanel(
    child: Row(
      children: [
        const Icon(Icons.cloud_off_outlined, color: Colors.orange),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'تعذر عرض الملخص المحلي. الأقسام المحاسبية لا تزال متاحة.',
          ),
        ),
        IconButton(
          tooltip: 'أعد المحاولة',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
  );
}
