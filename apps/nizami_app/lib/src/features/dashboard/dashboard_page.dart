import '../returns/return_workspace_page.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../administration/administration_page.dart';
import '../accounting/cashbox_page.dart';
import '../backup/backup_page.dart';
import '../invoices/invoice_workspace_page.dart';
import '../payroll/employee_payroll_page.dart';
import '../modules/module_workspace_page.dart';
import '../settings/identity_settings_page.dart';
import '../wasl/wasl_page.dart';
import '../whatsapp/whatsapp_page.dart';
import '../whatsapp/whatsapp_api.dart';
import '../navigation/ninesoft_module_access_policy.dart';
import '../navigation/ninesoft_global_shortcuts.dart';
import '../navigation/ninesoft_module_taxonomy.dart';
import '../../theme/ninesoft_ui.dart';
import 'server_status_api.dart';
import 'section_hub_page.dart';
import 'ninesoft_reference_dashboard.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
    required this.displayName,
    required this.token,
    required this.tenantName,
    required this.tenantId,
    required this.roleCode,
    required this.permissions,
    required this.branchIds,
    required this.onLogout,
    this.onOpenModule,
    this.showMobileDock = true,
    this.onOpenApps,
    this.onSearchApps,
  });

  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final String displayName, token, tenantName, tenantId;
  final String roleCode;
  final List<String> permissions;
  final List<String> branchIds;
  final VoidCallback onLogout;
  final ValueChanged<ModuleDefinition>? onOpenModule;
  final bool showMobileDock;
  final VoidCallback? onOpenApps;
  final ValueChanged<String>? onSearchApps;

  bool _canSee(ModuleDefinition module) => NineSoftModuleAccessPolicy.canOpen(
    moduleKey: module.key,
    roleCode: roleCode,
    permissions: permissions,
    branchIds: branchIds,
  );

  static const modules = <ModuleDefinition>[
    ModuleDefinition(
      key: 'sales',
      title: 'المبيعات',
      entityLabel: 'فاتورة بيع',
      actionLabel: 'فاتورة بيع جديدة',
      icon: Icons.shopping_bag_rounded,
      color: Color(0xFF962DDD),
    ),
    ModuleDefinition(
      key: 'purchases',
      title: 'المشتريات',
      entityLabel: 'فاتورة شراء',
      actionLabel: 'فاتورة شراء جديدة',
      icon: Icons.shopping_cart_rounded,
      color: Color(0xFF137BE0),
    ),
    ModuleDefinition(
      key: 'sales.returns',
      title: 'مرتجعات المبيعات',
      entityLabel: 'مرتجع بيع',
      actionLabel: 'مرتجع جديد',
      icon: Icons.assignment_return_rounded,
      color: Color(0xFFFF5574),
    ),
    ModuleDefinition(
      key: 'customers',
      title: 'العملاء',
      entityLabel: 'عميل',
      actionLabel: 'إضافة عميل',
      icon: Icons.groups_rounded,
      color: Color(0xFF059AA8),
    ),
    ModuleDefinition(
      key: 'payroll',
      title: 'الموظفون والرواتب',
      entityLabel: 'موظف ومسير راتب',
      actionLabel: 'فتح قسم الرواتب',
      icon: Icons.groups_2_rounded,
      color: Color(0xFF008E81),
    ),
    ModuleDefinition(
      key: 'suppliers',
      title: 'الموردون',
      entityLabel: 'مورد',
      actionLabel: 'إضافة مورد',
      icon: Icons.local_shipping_rounded,
      color: Color(0xFF059AA8),
    ),
    ModuleDefinition(
      key: 'products',
      title: 'الأصناف',
      entityLabel: 'صنف',
      actionLabel: 'إضافة صنف',
      icon: Icons.inventory_2_rounded,
      color: Color(0xFFEF791B),
    ),
    ModuleDefinition(
      key: 'inventory',
      title: 'المخزون والمستودعات',
      entityLabel: 'حركة مخزون',
      actionLabel: 'إضافة حركة',
      icon: Icons.warehouse_rounded,
      color: Color(0xFFEF791B),
    ),
    ModuleDefinition(
      key: 'debts',
      title: 'السندات',
      entityLabel: 'سند',
      actionLabel: 'إضافة سند',
      icon: Icons.payments_rounded,
      color: Color(0xFFE9A100),
    ),
    ModuleDefinition(
      key: 'cashbox',
      title: 'الصندوق',
      entityLabel: 'حركة صندوق',
      actionLabel: 'عرض حركة الصندوق',
      icon: Icons.paid_rounded,
      color: Color(0xFFF0A400),
    ),
    ModuleDefinition(
      key: 'accounts',
      title: 'المحاسبة',
      entityLabel: 'حساب',
      actionLabel: 'إضافة حساب',
      icon: Icons.calculate_rounded,
      color: Color(0xFFE74B55),
    ),
    ModuleDefinition(
      key: 'reports',
      title: 'التقارير',
      entityLabel: 'تقرير',
      actionLabel: 'إنشاء تقرير',
      icon: Icons.pie_chart_rounded,
      color: Color(0xFF7134E3),
    ),
    ModuleDefinition(
      key: 'users',
      title: 'المستخدمون',
      entityLabel: 'مستخدم',
      actionLabel: 'إضافة مستخدم',
      icon: Icons.manage_accounts_rounded,
      color: Color(0xFF0C91C7),
    ),
    ModuleDefinition(
      key: 'branches',
      title: 'نسخ العملاء',
      entityLabel: 'نسخة عميل',
      actionLabel: 'إنشاء نسخة عميل',
      icon: Icons.copy_all_rounded,
      color: Color(0xFF0CA489),
    ),
    ModuleDefinition(
      key: 'backup',
      title: 'المزامنة والنسخ الاحتياطية',
      entityLabel: 'نسخة احتياطية',
      actionLabel: 'إنشاء نسخة',
      icon: Icons.cloud_sync_rounded,
      color: Color(0xFF1975BC),
    ),
    ModuleDefinition(
      key: 'settings',
      title: 'الإعدادات',
      entityLabel: 'إعداد',
      actionLabel: 'إضافة إعداد',
      icon: Icons.settings_rounded,
      color: Color(0xFF667486),
    ),
    ModuleDefinition(
      key: 'whatsapp',
      title: 'واتساب',
      entityLabel: 'رسالة',
      actionLabel: 'ربط واتساب',
      icon: Icons.call_rounded,
      color: Color(0xFF08B75B),
    ),
    ModuleDefinition(
      key: 'wasl',
      title: 'التحويلات البنكية',
      entityLabel: 'تحويل',
      actionLabel: 'عرض التحويلات',
      icon: Icons.account_balance_rounded,
      color: Color(0xFFD643AA),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = themeMode == ThemeMode.dark;
    final visibleModules = NineSoftModuleTaxonomy.order(
      modules.where(_canSee),
      (module) => module.key,
    );
    void openKey(String key) {
      final exactModule = visibleModules
          .where((item) => item.key == key)
          .firstOrNull;
      final rootKey = key.split('.').first;
      final rootAllowed = visibleModules.any((item) => item.key == rootKey);
      final module =
          exactModule ??
          (rootAllowed ? NineSoftGlobalShortcuts.definitionFor(key) : null);
      if (module == null) return;
      if (onOpenModule != null) {
        onOpenModule!(module);
      } else {
        _ModuleTile.openModule(
          context,
          module: module,
          branchIds: branchIds,
          tenantName: tenantName,
          tenantId: tenantId,
          roleCode: roleCode,
          permissions: permissions,
          displayName: displayName,
          token: token,
        );
      }
    }

    final compact = MediaQuery.sizeOf(context).width < 900;
    return Scaffold(
      bottomNavigationBar: compact && showMobileDock
          ? NineSoftMobileDock(
              currentIndex: 0,
              centerAction: () => openKey('sales'),
              onSelected: (index) {
                if (index == 1) openKey('products');
                if (index == 2) openKey('reports');
                if (index == 3) {
                  if (onOpenApps != null) {
                    onOpenApps!();
                  } else {
                    openKey('settings');
                  }
                }
              },
            )
          : null,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [Color(0xFF0B1320), Color(0xFF101A25)]
                : const [Color(0xFFF5FCFF), Color(0xFFEBF8FB)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1480),
              child: CustomScrollView(
                slivers: [
                  if (compact)
                    SliverToBoxAdapter(
                      child: _MobileBrandHeader(
                        displayName: displayName,
                        tenantName: tenantName,
                        dark: dark,
                        onToggleTheme: onToggleTheme,
                        onLogout: onLogout,
                        onOpenSearch: onOpenApps,
                        onOpenProfile: () => openKey('settings'),
                        onOpenNotifications: onOpenApps,
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 14 : 22,
                      compact ? 16 : 20,
                      compact ? 14 : 22,
                      24,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: NineSoftReferenceDashboard(
                        tenantName: tenantName,
                        tenantId: tenantId,
                        displayName: displayName,
                        branchIds: branchIds,
                        modules: visibleModules,
                        onOpen: openKey,
                        statusIndicator: _Hero(
                          token: token,
                          branchIds: branchIds,
                        ),
                        onOpenApps: onOpenApps,
                        onSearchApps: onSearchApps,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact blue identity bar matching the approved mobile reference.
class _MobileBrandHeader extends StatelessWidget {
  const _MobileBrandHeader({
    required this.displayName,
    required this.tenantName,
    required this.dark,
    required this.onToggleTheme,
    required this.onLogout,
    this.onOpenSearch,
    this.onOpenProfile,
    this.onOpenNotifications,
  });

  final String displayName, tenantName;
  final bool dark;
  final VoidCallback onToggleTheme, onLogout;
  final VoidCallback? onOpenSearch, onOpenProfile, onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [Color(0xFF0B356F), Color(0xFF072A59)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            key: const Key('dashboard-menu-action'),
            tooltip: 'القائمة',
            onPressed: onOpenSearch,
            icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 31),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'NineSoft',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'ArialMTBlack',
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                    letterSpacing: .2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  tenantName.trim().isEmpty ? 'نظام محاسبي متكامل' : tenantName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD7E5F8),
                    fontFamily: 'GESS',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _ReferenceHeaderAction(
            tooltip: '$displayName • الحساب',
            icon: Icons.person_outline_rounded,
            onTap: onOpenProfile,
          ),
          const SizedBox(width: 5),
          Stack(
            clipBehavior: Clip.none,
            children: [
              _ReferenceHeaderAction(
                tooltip: 'التنبيهات',
                icon: Icons.notifications_none_rounded,
                onTap: onOpenNotifications,
              ),
              const PositionedDirectional(
                end: 4,
                top: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFFF5252),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(width: 8, height: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReferenceHeaderAction extends StatelessWidget {
  const _ReferenceHeaderAction({
    required this.tooltip,
    required this.icon,
    this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .10),
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      constraints: const BoxConstraints.tightFor(width: 42, height: 42),
      padding: EdgeInsets.zero,
      icon: Icon(icon, color: Colors.white, size: 26),
    ),
  );
}

class _Hero extends StatefulWidget {
  const _Hero({required this.token, required this.branchIds});
  final String token;
  final List<String> branchIds;
  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  Timer? _statusTimer;
  WhatsappStatus? _whatsapp;
  bool? _serverHealthy;
  @override
  void initState() {
    super.initState();
    _refreshStatuses();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshStatuses(),
    );
  }

  Future<void> _refreshStatuses() async {
    await Future.wait([_refreshServer(), _refreshWhatsapp()]);
  }

  Future<void> _refreshServer() async {
    try {
      await ServerStatusApi(token: widget.token).verify();
      if (mounted) setState(() => _serverHealthy = true);
    } catch (_) {
      if (mounted) setState(() => _serverHealthy = false);
    }
  }

  Future<void> _refreshWhatsapp() async {
    if (widget.branchIds.isEmpty) return;
    try {
      final status = await WhatsappApi(
        token: widget.token,
      ).status(widget.branchIds.first);
      if (mounted) setState(() => _whatsapp = status);
    } catch (_) {
      if (mounted) {
        setState(() => _whatsapp = const WhatsappStatus(state: 'unreachable'));
      }
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _whatsapp?.connected == true;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _StatusCard(
            width: 54,
            icon: Icons.dns_rounded,
            title: 'الخادم',
            value: _serverHealthy == null
                ? 'جارٍ الفحص'
                : _serverHealthy!
                ? 'متصل'
                : 'غير متصل',
            color: const Color(0xFF7341DE),
            healthy: _serverHealthy,
          ),
          _StatusCard(
            width: 54,
            icon: Icons.call_rounded,
            title: 'واتساب',
            value: connected ? 'متصل' : 'غير متصل',
            color: connected ? const Color(0xFF08B75B) : Colors.red,
            healthy: connected,
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    this.healthy,
  });
  final double width;
  final IconData icon;
  final String title, value;
  final Color color;
  final bool? healthy;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 38,
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(19),
    ),
    child: Tooltip(
      message: '$title: $value',
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: 20, color: color),
          PositionedDirectional(
            end: 1,
            bottom: 1,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: healthy == true
                    ? Colors.green
                    : healthy == false
                    ? Colors.red
                    : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

abstract final class _ModuleTile {
  static void openModule(
    BuildContext context, {
    required ModuleDefinition module,
    required List<String> branchIds,
    required String tenantName,
    required String displayName,
    required String token,
    required String tenantId,
    required String roleCode,
    required List<String> permissions,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => switch (module.key) {
        'purchases.returns' || 'sales.returns' => ReturnWorkspacePage(
          token: token,
          tenantId: tenantId,
          branchIds: branchIds,
          roleCode: roleCode,
          permissions: permissions,
          purchase: module.key == 'purchases.returns',
        ),
        'sales' => InvoiceWorkspacePage(
          branchIds: branchIds,
          tenantName: tenantName,
          tenantId: tenantId,
          employeeName: displayName,
          token: token,
          roleCode: roleCode,
          permissions: permissions,
        ),
        'payroll' => EmployeePayrollPage(
          token: token,
          tenantId: tenantId,
          tenantName: tenantName,
          branchIds: branchIds,
          roleCode: roleCode,
          permissions: permissions,
        ),
        'cashbox' => CashboxPage(
          token: token,
          tenantName: tenantName,
          tenantId: tenantId,
          branchIds: branchIds,
          roleCode: roleCode,
          permissions: permissions,
        ),
        'settings' => IdentitySettingsPage(
          branchIds: branchIds,
          tenantName: tenantName,
          tenantId: tenantId,
          token: token,
        ),
        'backup' => BackupPage(token: token),
        'whatsapp' => WhatsappPage(branchIds: branchIds, token: token),
        'wasl' => WaslPage(
          token: token,
          tenantName: tenantName,
          branchIds: branchIds,
        ),
        'users' => AdministrationPage(
          token: token,
          tenantName: tenantName,
          showUsers: true,
          roleCode: roleCode,
        ),
        'branches' => AdministrationPage(
          token: token,
          tenantName: tenantName,
          showUsers: false,
          roleCode: roleCode,
        ),
        'accounts' ||
        'debts' ||
        'inventory' ||
        'purchases' ||
        'reports' => SectionHubPage(
          module: module,
          tenantName: tenantName,
          tenantId: tenantId,
          token: token,
          branchIds: branchIds,
          roleCode: roleCode,
          permissions: permissions,
        ),
        _ => ModuleWorkspacePage(
          module: module,
          tenantName: tenantName,
          tenantId: tenantId,
          token: token,
          branchIds: branchIds,
          roleCode: roleCode,
          permissions: permissions,
        ),
      },
    ),
  );
}
