import '../returns/return_workspace_page.dart';
import 'package:flutter/material.dart';
import '../modules/module_workspace_page.dart';
import '../accounting/chart_accounts_page.dart';
import '../accounting/simple_journal_page.dart';
import '../accounting/opening_balances_page.dart';
import '../accounting/accounting_periods_page.dart';
import '../accounting/account_statement_page.dart';
import '../accounting/account_transfer_page.dart';
import '../accounting/financial_reports_page.dart';
import '../accounting/product_inquiry_page.dart';
import '../purchases/purchase_workspace_page.dart';
import '../inventory/stock_operations_page.dart';
import '../../theme/ninesoft_ui.dart';
import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/nizami_theme.dart';
import '../navigation/ninesoft_module_access_policy.dart';

/// Section-specific navigation. Basic registers stay usable and synchronized,
/// but are clearly distinguished from workflows that post accounting entries.
class SectionHubPage extends StatelessWidget {
  const SectionHubPage({
    super.key,
    required this.module,
    required this.tenantName,
    this.tenantId,
    required this.token,
    required this.branchIds,
    required this.roleCode,
    required this.permissions,
    this.onOpenChildModule,
  });
  final ModuleDefinition module;
  final String tenantName;
  final String? tenantId;
  final String token;
  final List<String> branchIds;
  final String roleCode;
  final List<String> permissions;
  final ValueChanged<ModuleDefinition>? onOpenChildModule;

  void _openHubEntry(BuildContext context, _HubItem item, Color itemColor) {
    final childDefinition = ModuleDefinition(
      key: '${module.key}.${item.key}',
      title: item.title,
      entityLabel: item.entityLabel,
      actionLabel: 'إضافة ${item.entityLabel}',
      icon: item.icon,
      color: itemColor,
    );
    if (onOpenChildModule != null) {
      onOpenChildModule!(childDefinition);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _buildEntryPage(item, childDefinition),
      ),
    );
  }

  Widget _buildEntryPage(_HubItem item, ModuleDefinition childDefinition) {
    if (module.key == 'accounts' && item.key == 'accounts') {
      return ChartAccountsPage(
        token: token,
        branchIds: branchIds,
        roleCode: roleCode,
      );
    }
    if (module.key == 'accounts' && item.key == 'journals') {
      return SimpleJournalPage(
        token: token,
        branchIds: branchIds,
        roleCode: roleCode,
        permissions: permissions,
      );
    }
    if (module.key == 'accounts' && item.key == 'statements' ||
        module.key == 'reports' && item.key == 'customers') {
      return AccountStatementPage(token: token, branchIds: branchIds);
    }
    if (module.key == 'accounts' && item.key == 'transfers') {
      return AccountTransferPage(token: token, branchIds: branchIds);
    }
    if (module.key == 'accounts' && item.key == 'financial') {
      return FinancialReportsPage(token: token, branchIds: branchIds);
    }
    if (module.key == 'inventory' && item.key == 'inquiry') {
      return ProductInquiryPage(token: token, branchIds: branchIds);
    }
    if (module.key == 'reports' &&
        const {
          'financial',
          'trial',
          'profit-loss',
          'balance-sheet',
          'cash-flow',
        }.contains(item.key)) {
      return FinancialReportsPage(
        token: token,
        branchIds: branchIds,
        initialReport: item.key,
      );
    }
    if (module.key == 'purchases' && item.key == 'returns') {
      return ReturnWorkspacePage(
        token: token,
        tenantId: tenantId ?? tenantName,
        branchIds: branchIds,
        roleCode: roleCode,
        permissions: permissions,
      );
    }
    if (module.key == 'purchases' &&
        (item.key == 'invoices' || item.key == 'receiving')) {
      return PurchaseWorkspacePage(
        token: token,
        branchIds: branchIds,
        tenantName: tenantName,
        tenantId: tenantId,
        roleCode: roleCode,
        permissions: permissions,
      );
    }
    if (module.key == 'inventory' &&
        (item.key == 'counts' || item.key == 'transfers')) {
      return StockOperationsPage(
        token: token,
        tenantId: tenantId ?? tenantName,
        branchIds: branchIds,
        isTransfer: item.key == 'transfers',
        canWrite: roleCode == 'owner' || permissions.contains('catalog.write'),
      );
    }
    if (module.key == 'accounts' && item.key == 'opening') {
      return OpeningBalancesPage(
        token: token,
        branchIds: branchIds,
        roleCode: roleCode,
      );
    }
    if (module.key == 'accounts' && item.key == 'years') {
      return AccountingPeriodsPage(
        token: token,
        branchIds: branchIds,
        roleCode: roleCode,
      );
    }
    return ModuleWorkspacePage(
      module: childDefinition,
      tenantName: tenantName,
      tenantId: tenantId,
      token: token,
      branchIds: branchIds,
      roleCode: roleCode,
      permissions: permissions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _entries(module.key)
        .where(
          (item) => NineSoftModuleAccessPolicy.canOpen(
            moduleKey: '${module.key}.${item.key}',
            roleCode: roleCode,
            permissions: permissions,
            branchIds: branchIds,
          ),
        )
        .toList(growable: false);
    const palette = <Color>[
      Color(0xFF1684CE),
      Color(0xFF089D91),
      Color(0xFF8A3BDE),
      Color(0xFFF07819),
      Color(0xFF0BA1AD),
      Color(0xFFDB5263),
    ];
    final date = DateTime.now();
    final dateLabel =
        '${date.year.toString().padLeft(4, '0')}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: Text(module.title)),
      body: SafeArea(
        child: NineSoftResponsiveBody(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop =
                  constraints.maxWidth >= NineSoftBreakpoints.desktop;
              return ListView(
                children: [
                  NineSoftEntryHeading(
                    title: module.title,
                    subtitle:
                        'كل أدوات ${module.title} في مكان واحد وبخطوات واضحة',
                    icon: module.icon,
                    accent: module.color,
                    status: tenantName,
                    actions: desktop
                        ? [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: NizamiColors.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.calendar_month_rounded,
                                    size: 19,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    dateLabel,
                                    textDirection: TextDirection.ltr,
                                    style: const TextStyle(
                                      fontFamily: 'ArialMTBlack',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ]
                        : const [],
                  ),
                  const SizedBox(height: 18),
                  NineSoftEntrySection(
                    title: 'أقسام ${module.title}',
                    subtitle: '${items.length} قسم متاح حسب صلاحيات الحساب',
                    icon: Icons.grid_view_rounded,
                    child: Column(
                      children: [
                        GridView.builder(
                          key: const Key('section-hub-grid'),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: items.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: desktop
                                    ? 3
                                    : constraints.maxWidth > 560
                                    ? 2
                                    : 1,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: desktop ? 2.25 : 2.7,
                              ),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final color = palette[index % palette.length];
                            return NineSoftPanel(
                              padding: EdgeInsets.zero,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: item.implemented
                                    ? () => _openHubEntry(context, item, color)
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: .12),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Icon(item.icon, color: color),
                                      ),
                                      const SizedBox(width: 13),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontFamily: 'GESS',
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              item.integrated
                                                  ? 'عرض وإدارة ${item.entityLabel}'
                                                  : 'سجل محفوظ دون ترحيل محاسبي',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_left_rounded,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: NizamiColors.blueSoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: NizamiColors.blue,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'تُعرض بيانات النظام الحقيقية فقط. عند عدم وجود سجلات ستظهر حالة فارغة واضحة.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<_HubItem> _entries(String key) => switch (key) {
    'accounts' => const [
      _HubItem('accounts', 'شجرة الحسابات', 'حساب', Icons.account_tree_rounded),
      _HubItem(
        'journals',
        'القيود اليومية',
        'قيد يومي',
        Icons.menu_book_rounded,
      ),
      _HubItem(
        'opening',
        'الأرصدة الافتتاحية',
        'قيد افتتاحي',
        Icons.flag_rounded,
      ),
      _HubItem(
        'statements',
        'كشف الحساب الموحد',
        'كشف حساب',
        Icons.manage_search_rounded,
      ),
      _HubItem(
        'financial',
        'القوائم المالية',
        'قائمة مالية',
        Icons.bar_chart_rounded,
      ),
      _HubItem(
        'transfers',
        'تحويلات الخزائن والبنوك',
        'تحويل نقدي',
        Icons.swap_horiz_rounded,
      ),
      _HubItem(
        'years',
        'السنوات المالية',
        'سنة مالية',
        Icons.calendar_month_rounded,
      ),
    ],
    'debts' => const [
      _HubItem(
        'dues',
        'سجل الاستحقاقات',
        'استحقاق',
        Icons.account_balance_wallet_rounded,
      ),
      _HubItem('receipts', 'سندات القبض', 'سند قبض', Icons.south_west_rounded),
      _HubItem('payments', 'سندات الصرف', 'سند صرف', Icons.north_east_rounded),
      _HubItem(
        'exchange',
        'أسعار العملات',
        'سعر عملة',
        Icons.currency_exchange_rounded,
        integrated: false,
      ),
    ],
    'inventory' => const [
      _HubItem(
        'inquiry',
        'استعلام الصنف',
        'استعلام مخزون',
        Icons.manage_search_rounded,
      ),
      _HubItem(
        'movements',
        'حركات المخزون',
        'حركة مخزون',
        Icons.inventory_2_rounded,
      ),
      _HubItem(
        'warehouses',
        'المستودعات',
        'مستودع',
        Icons.warehouse_rounded,
        integrated: false,
      ),
      _HubItem(
        'transfers',
        'تحويلات الفروع',
        'تحويل مخزون',
        Icons.swap_horiz_rounded,
      ),
      _HubItem(
        'counts',
        'الجرد والتسويات',
        'تسوية جرد',
        Icons.fact_check_rounded,
      ),
      _HubItem(
        'valuation',
        'تقييم المخزون',
        'تقييم مخزون',
        Icons.price_check_rounded,
      ),
      _HubItem('reports', 'التقارير', 'تقرير مخزون', Icons.bar_chart_rounded),
    ],
    'purchases' => const [
      _HubItem(
        'invoices',
        'سجل المشتريات',
        'فاتورة شراء',
        Icons.receipt_long_rounded,
      ),
      _HubItem(
        'orders',
        'أوامر الشراء',
        'أمر شراء',
        Icons.assignment_rounded,
        integrated: false,
      ),
      _HubItem(
        'receiving',
        'استلام الأصناف',
        'استلام أصناف',
        Icons.local_shipping_rounded,
      ),
      _HubItem(
        'returns',
        'مرتجعات المشتريات',
        'مرتجع مشتريات',
        Icons.keyboard_return_rounded,
      ),
    ],
    'reports' => const [
      _HubItem(
        'financial',
        'القوائم المالية',
        'قائمة مالية',
        Icons.account_balance_rounded,
      ),
      _HubItem(
        'trial',
        'ميزان المراجعة',
        'ميزان مراجعة',
        Icons.balance_rounded,
      ),
      _HubItem(
        'profit-loss',
        'الأرباح والخسائر',
        'قائمة دخل',
        Icons.trending_up_rounded,
      ),
      _HubItem(
        'balance-sheet',
        'المركز المالي',
        'ميزانية عمومية',
        Icons.account_balance_rounded,
      ),
      _HubItem(
        'cash-flow',
        'التدفقات النقدية',
        'تدفقات نقدية',
        Icons.waterfall_chart_rounded,
      ),
      _HubItem(
        'daily',
        'التقرير اليومي الشامل',
        'تقرير يومي',
        Icons.summarize_rounded,
      ),
      _HubItem(
        'sales',
        'تقرير المبيعات',
        'تقرير مبيعات',
        Icons.trending_up_rounded,
      ),
      _HubItem(
        'purchases',
        'تقرير المشتريات',
        'تقرير مشتريات',
        Icons.shopping_bag_outlined,
      ),
      _HubItem(
        'debts',
        'تقرير الديون والاستحقاقات',
        'تقرير ديون',
        Icons.notification_important_outlined,
      ),
      _HubItem(
        'cash',
        'تقرير القبض والصرف',
        'تقرير مالي',
        Icons.account_balance_wallet_outlined,
      ),
      _HubItem(
        'inventory',
        'تقرير المخزون',
        'تقرير مخزون',
        Icons.inventory_2_outlined,
      ),
      _HubItem(
        'customers',
        'كشف حساب عميل',
        'كشف حساب',
        Icons.person_search_outlined,
      ),
    ],
    _ => const [
      _HubItem('records', 'سجل القسم', 'سجل', Icons.grid_view_rounded),
    ],
  };
}

class _HubItem {
  const _HubItem(
    this.key,
    this.title,
    this.entityLabel,
    this.icon, {
    this.integrated = true,
  });
  final String key;
  final String title;
  final String entityLabel;
  final IconData icon;
  final bool integrated;
  bool get implemented => true;
}
