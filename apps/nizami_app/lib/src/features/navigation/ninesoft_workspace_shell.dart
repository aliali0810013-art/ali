import '../returns/return_workspace_page.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../accounting/chart_accounts_page.dart';
import '../accounting/cashbox_page.dart';
import '../accounting/simple_journal_page.dart';
import '../accounting/opening_balances_page.dart';
import '../accounting/accounting_periods_page.dart';
import '../accounting/account_statement_page.dart';
import '../accounting/account_transfer_page.dart';
import '../accounting/financial_reports_page.dart';
import '../accounting/product_inquiry_page.dart';
import '../administration/administration_page.dart';
import '../backup/backup_page.dart';
import '../dashboard/dashboard_page.dart';
import '../dashboard/section_hub_page.dart';
import '../invoices/invoice_workspace_page.dart';
import '../modules/module_workspace_page.dart';
import '../payroll/employee_payroll_page.dart';
import '../payroll/payroll_api.dart';
import '../purchases/purchase_workspace_page.dart';
import '../inventory/stock_operations_page.dart';
import '../settings/identity_settings_page.dart';
import '../wasl/wasl_page.dart';
import '../whatsapp/whatsapp_page.dart';
import 'ninesoft_desktop_navigation.dart';
import 'ninesoft_global_shortcuts.dart';
import '../../theme/ninesoft_ui.dart';
import 'ninesoft_app_launcher.dart';
import 'ninesoft_module_access_policy.dart';
import 'ninesoft_module_taxonomy.dart';

class NineSoftWorkspaceShell extends StatefulWidget {
  const NineSoftWorkspaceShell({
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
    this.payrollApi,
    this.payrollSyncChanges,
  });

  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final String displayName;
  final String token;
  final String tenantName;
  final String tenantId;
  final String roleCode;
  final List<String> permissions;
  final List<String> branchIds;
  final VoidCallback onLogout;
  final PayrollApi? payrollApi;
  final Stream<Set<String>>? payrollSyncChanges;

  @override
  State<NineSoftWorkspaceShell> createState() => _NineSoftWorkspaceShellState();
}

class _WorkspaceTab {
  _WorkspaceTab({required this.module, required this.child});

  final ModuleDefinition module;
  final Widget child;
  final navigatorKey = GlobalKey<NavigatorState>();

  Widget buildNavigator() => Navigator(
    key: navigatorKey,
    onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => child),
  );
}

class _NineSoftWorkspaceShellState extends State<NineSoftWorkspaceShell> {
  static const _desktopBreakpoint = 900.0;

  final List<_WorkspaceTab> _tabs = [];
  String? _activeModuleKey;

  bool _isAllowed(String key) => NineSoftModuleAccessPolicy.canOpen(
    moduleKey: key,
    roleCode: widget.roleCode,
    permissions: widget.permissions,
    branchIds: widget.branchIds,
  );

  ModuleDefinition? _module(String key) {
    for (final module in DashboardPage.modules) {
      if (module.key == key) return module;
    }
    return NineSoftGlobalShortcuts.definitionFor(key);
  }

  Map<ShortcutActivator, VoidCallback> get _shortcutBindings => {
    for (final entry in NineSoftGlobalShortcuts.entries)
      SingleActivator(entry.key): () => _openByKey(entry.value),
  };

  void _openByKey(String key) {
    final existing = _tabs.where((tab) => tab.module.key == key).firstOrNull;
    if (existing != null) {
      setState(() => _activeModuleKey = key);
      return;
    }
    final module = _module(key);
    if (module != null) _openModule(module);
  }

  AtlasAppGroup _appGroup(String key) => NineSoftModuleTaxonomy.groupFor(key);

  List<AtlasAppDefinition> get _launcherApps =>
      NineSoftModuleTaxonomy.order(
            DashboardPage.modules.where((module) => _isAllowed(module.key)),
            (module) => module.key,
          )
          .map(
            (module) => AtlasAppDefinition(
              key: module.key,
              title: module.title,
              subtitle: module.entityLabel,
              icon: module.icon,
              color: module.color,
              group: _appGroup(module.key),
            ),
          )
          .toList(growable: false);

  void _showAppLauncher({String initialQuery = ''}) {
    unawaited(
      NineSoftAppLauncher.show(
        context,
        apps: _launcherApps,
        initialQuery: initialQuery,
        onOpen: _openByKey,
      ),
    );
  }

  void _openModule(ModuleDefinition module) {
    if (!_isAllowed(module.key)) return;
    final existing = _tabs.indexWhere((tab) => tab.module.key == module.key);
    if (existing < 0) {
      _tabs.add(_WorkspaceTab(module: module, child: _pageFor(module)));
    }
    setState(() => _activeModuleKey = module.key);
  }

  Widget _pageFor(ModuleDefinition module) => KeyedSubtree(
    key: PageStorageKey<String>('ninesoft-workspace-${module.key}'),
    child: switch (module.key) {
      'sales' => InvoiceWorkspacePage(
        branchIds: widget.branchIds,
        tenantName: widget.tenantName,
        tenantId: widget.tenantId,
        employeeName: widget.displayName,
        token: widget.token,
        roleCode: widget.roleCode,
        permissions: widget.permissions,
      ),
      'cashbox' => CashboxPage(
        token: widget.token,
        tenantName: widget.tenantName,
        tenantId: widget.tenantId,
        branchIds: widget.branchIds,
        roleCode: widget.roleCode,
        permissions: widget.permissions,
      ),
      'payroll' => EmployeePayrollPage(
        token: widget.token,
        tenantId: widget.tenantId,
        tenantName: widget.tenantName,
        branchIds: widget.branchIds,
        roleCode: widget.roleCode,
        permissions: widget.permissions,
        api: widget.payrollApi,
        syncChanges: widget.payrollSyncChanges,
      ),
      'accounts.accounts' => ChartAccountsPage(
        token: widget.token,
        branchIds: widget.branchIds,
        roleCode: widget.roleCode,
      ),
      'accounts.journals' => SimpleJournalPage(
        token: widget.token,
        branchIds: widget.branchIds,
        roleCode: widget.roleCode,
        permissions: widget.permissions,
      ),
      'accounts.statements' || 'reports.customers' => AccountStatementPage(
        token: widget.token,
        branchIds: widget.branchIds,
      ),
      'accounts.transfers' => AccountTransferPage(
        token: widget.token,
        branchIds: widget.branchIds,
      ),
      'accounts.financial' ||
      'reports.financial' ||
      'reports.trial' ||
      'reports.profit-loss' ||
      'reports.balance-sheet' ||
      'reports.cash-flow' => FinancialReportsPage(
        token: widget.token,
        branchIds: widget.branchIds,
        initialReport: module.key.split('.').last,
      ),
      'inventory.inquiry' => ProductInquiryPage(
        token: widget.token,
        branchIds: widget.branchIds,
      ),
      'purchases.returns' || 'sales.returns' => ReturnWorkspacePage(
        token: widget.token,
        tenantId: widget.tenantId,
        branchIds: widget.branchIds,
        roleCode: widget.roleCode,
        permissions: widget.permissions,
        purchase: module.key == 'purchases.returns',
      ),
      'purchases.invoices' || 'purchases.receiving' => PurchaseWorkspacePage(
        token: widget.token,
        branchIds: widget.branchIds,
        tenantName: widget.tenantName,
        tenantId: widget.tenantId,
        roleCode: widget.roleCode,
        permissions: widget.permissions,
      ),
      'inventory.counts' || 'inventory.transfers' => StockOperationsPage(
        token: widget.token,
        tenantId: widget.tenantId,
        branchIds: widget.branchIds,
        isTransfer: module.key == 'inventory.transfers',
        canWrite:
            widget.roleCode == 'owner' ||
            widget.permissions.contains('catalog.write'),
      ),
      'accounts.opening' => OpeningBalancesPage(
        token: widget.token,
        branchIds: widget.branchIds,
        roleCode: widget.roleCode,
      ),
      'accounts.years' => AccountingPeriodsPage(
        token: widget.token,
        branchIds: widget.branchIds,
        roleCode: widget.roleCode,
      ),
      'settings' => IdentitySettingsPage(
        branchIds: widget.branchIds,
        tenantName: widget.tenantName,
        tenantId: widget.tenantId,
        token: widget.token,
      ),
      'backup' => BackupPage(token: widget.token),
      'whatsapp' => WhatsappPage(
        branchIds: widget.branchIds,
        token: widget.token,
      ),
      'wasl' => WaslPage(
        token: widget.token,
        tenantName: widget.tenantName,
        branchIds: widget.branchIds,
      ),
      'users' => AdministrationPage(
        token: widget.token,
        tenantName: widget.tenantName,
        showUsers: true,
        roleCode: widget.roleCode,
      ),
      'branches' => AdministrationPage(
        token: widget.token,
        tenantName: widget.tenantName,
        showUsers: false,
        roleCode: widget.roleCode,
      ),
      'accounts' ||
      'debts' ||
      'inventory' ||
      'purchases' ||
      'reports' => SectionHubPage(
        module: module,
        tenantName: widget.tenantName,
        tenantId: widget.tenantId,
        token: widget.token,
        branchIds: widget.branchIds,
        roleCode: widget.roleCode,
        permissions: widget.permissions,
        onOpenChildModule: _openModule,
      ),
      _ => ModuleWorkspacePage(
        module: module,
        tenantName: widget.tenantName,
        tenantId: widget.tenantId,
        token: widget.token,
        branchIds: widget.branchIds,
        roleCode: widget.roleCode,
        permissions: widget.permissions,
      ),
    },
  );

  Future<void> _closeTab(String key) async {
    final tab = _tabs.where((item) => item.module.key == key).firstOrNull;
    if (tab == null) return;
    final close = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إغلاق التبويب؟'),
        content: Text(
          'قد تفقد التعديلات غير المحفوظة في ${tab.module.title}. '
          'احفظ عملك قبل الإغلاق.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
    if (close != true || !mounted) return;
    setState(() {
      _tabs.removeWhere((item) => item.module.key == key);
      if (_activeModuleKey == key) _activeModuleKey = null;
    });
  }

  DashboardPage _dashboard({
    ValueChanged<ModuleDefinition>? onOpenModule,
    bool showMobileDock = true,
  }) => DashboardPage(
    themeMode: widget.themeMode,
    onToggleTheme: widget.onToggleTheme,
    displayName: widget.displayName,
    tenantName: widget.tenantName,
    tenantId: widget.tenantId,
    roleCode: widget.roleCode,
    permissions: widget.permissions,
    branchIds: widget.branchIds,
    token: widget.token,
    onLogout: widget.onLogout,
    onOpenModule: onOpenModule,
    showMobileDock: showMobileDock,
    onOpenApps: _showAppLauncher,
    onSearchApps: (query) => _showAppLauncher(initialQuery: query),
  );

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: _shortcutBindings,
    child: Focus(
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final activeIndex = _activeModuleKey == null
              ? 0
              : _tabs.indexWhere((tab) => tab.module.key == _activeModuleKey) +
                    1;
          final activeRootSection = _activeModuleKey == null
              ? ''
              : _activeModuleKey!.split('.').first;
          if (constraints.maxWidth < _desktopBreakpoint) {
            const settingsModules = {
              'settings',
              'users',
              'branches',
              'backup',
            };
            final mobileIndex = activeRootSection.isEmpty
                ? 0
                : activeRootSection == 'reports'
                ? 2
                : settingsModules.contains(activeRootSection)
                ? 3
                : 1;
            final activeModule = _activeModuleKey == null
                ? null
                : _module(_activeModuleKey!);
            return Scaffold(
              body: Column(
                children: [
                  if (_activeModuleKey != null)
                    NineSoftReferenceMobileHeader(
                      title: activeModule?.title ?? 'NineSoft',
                      onMenu: _showAppLauncher,
                      onProfile: () => _openByKey('settings'),
                    ),
                  Expanded(
                    child: IndexedStack(
                      index: activeIndex < 0 ? 0 : activeIndex,
                      children: [
                        _dashboard(
                          onOpenModule: _openModule,
                          showMobileDock: false,
                        ),
                        for (final tab in _tabs) tab.buildNavigator(),
                      ],
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: NineSoftMobileDock(
                currentIndex: mobileIndex,
                contextLabel: mobileIndex == 1
                    ? (activeModule?.title ?? 'العمليات')
                    : 'العمليات',
                contextIcon: mobileIndex == 1
                    ? (activeModule?.icon ?? Icons.layers_outlined)
                    : Icons.layers_outlined,
                centerAction: () => _openByKey('sales'),
                onSelected: (index) {
                  if (index == 0) setState(() => _activeModuleKey = null);
                  if (index == 1) {
                    if (mobileIndex != 1) _showAppLauncher();
                  }
                  if (index == 2) _openByKey('reports');
                  if (index == 3) _openByKey('settings');
                },
              ),
            );
          }

          final openTabs = [
            for (final tab in _tabs)
              NineSoftOpenTab(id: tab.module.key, title: tab.module.title),
          ];
          return Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                children: [
                  NineSoftDesktopTopBar(
                    displayName: widget.displayName,
                    openTabs: openTabs,
                    activeTabId: _activeModuleKey,
                    onActivateTab: (key) =>
                        setState(() => _activeModuleKey = key),
                    onCloseTab: (key) => unawaited(_closeTab(key)),
                    onToggleTheme: widget.onToggleTheme,
                    onLogout: widget.onLogout,
                    dark: widget.themeMode == ThemeMode.dark,
                    activeSection: activeRootSection,
                    onGoHome: () => setState(() => _activeModuleKey = null),
                    onOpenApps: _showAppLauncher,
                    onOpenReports: () => _openByKey('reports'),
                    onSearch: (query) =>
                        _showAppLauncher(initialQuery: query),
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: activeIndex < 0 ? 0 : activeIndex,
                      children: [
                        _dashboard(onOpenModule: _openModule),
                        for (final tab in _tabs) tab.buildNavigator(),
                      ],
                    ),
                  ),
                  NineSoftDesktopTaskbar(
                    activeSection: activeRootSection,
                    activeTabId: _activeModuleKey,
                    openTabs: openTabs,
                    onGoHome: () => setState(() => _activeModuleKey = null),
                    onOpenApps: _showAppLauncher,
                    onOpenSection: _openByKey,
                    onActivateTab: (key) =>
                        setState(() => _activeModuleKey = key),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}


class NineSoftReferenceMobileHeader extends StatelessWidget {
  const NineSoftReferenceMobileHeader({
    super.key,
    required this.title,
    required this.onMenu,
    required this.onProfile,
  });

  final String title;
  final VoidCallback onMenu;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: EdgeInsetsDirectional.fromSTEB(14, topPadding + 8, 14, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [Color(0xFF0B356F), Color(0xFF082B5D)],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'القائمة',
            onPressed: onMenu,
            icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 31),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'NineSoft',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'ArialMTBlack',
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                    height: 1.05,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'نظام محاسبي متكامل',
                  maxLines: 1,
                  style: TextStyle(
                    color: Color(0xFFD7E5F8),
                    fontFamily: 'GESS',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'التنبيهات',
                onPressed: onMenu,
                icon: const Icon(
                  Icons.notifications_none_rounded,
                  color: Colors.white,
                  size: 29,
                ),
              ),
              const PositionedDirectional(
                top: 6,
                end: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFFF4C55),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(width: 8, height: 8),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'الحساب',
            onPressed: onProfile,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF214B82),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.person_outline_rounded, size: 27),
          ),
        ],
      ),
    );
  }
}
