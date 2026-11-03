import 'package:flutter/material.dart';

import '../../theme/nizami_theme.dart';
import '../../widgets/ninesoft_brand_logo.dart';
import 'ninesoft_module_taxonomy.dart';

class NineSoftOpenTab {
  const NineSoftOpenTab({required this.id, required this.title});
  final String id;
  final String title;
}

class NineSoftDesktopNavigation extends StatelessWidget {
  const NineSoftDesktopNavigation({
    super.key,
    required this.activeSection,
    required this.onOpenSection,
    required this.onGoHome,
    required this.isSectionAllowed,
    required this.tenantName,
  });

  final String activeSection;
  final ValueChanged<String> onOpenSection;
  final VoidCallback onGoHome;
  final bool Function(String key) isSectionAllowed;
  final String tenantName;

  static const sections = <({String key, String name, IconData icon})>[
    (key: 'sales', name: 'المبيعات', icon: Icons.trending_up_rounded),
    (
      key: 'sales.returns',
      name: 'مرتجعات المبيعات',
      icon: Icons.assignment_return_rounded,
    ),
    (key: 'purchases', name: 'المشتريات', icon: Icons.shopping_basket_rounded),
    (key: 'products', name: 'الأصناف', icon: Icons.inventory_2_rounded),
    (key: 'customers', name: 'العملاء', icon: Icons.people_alt_rounded),
    (key: 'payroll', name: 'الموظفون والرواتب', icon: Icons.groups_2_rounded),
    (key: 'suppliers', name: 'الموردون', icon: Icons.local_shipping_rounded),
    (
      key: 'inventory',
      name: 'المخزون والمستودعات',
      icon: Icons.warehouse_rounded,
    ),
    (key: 'accounts', name: 'الحسابات', icon: Icons.account_balance_rounded),
    (key: 'cashbox', name: 'الصندوق', icon: Icons.point_of_sale_rounded),
    (key: 'debts', name: 'السندات', icon: Icons.receipt_long_rounded),
    (key: 'reports', name: 'التقارير', icon: Icons.bar_chart_rounded),
    (key: 'whatsapp', name: 'واتساب', icon: Icons.chat_rounded),
    (
      key: 'wasl',
      name: 'التحويلات البنكية',
      icon: Icons.account_balance_wallet_rounded,
    ),
    (key: 'backup', name: 'المزامنة والنسخ', icon: Icons.cloud_sync_rounded),
    (key: 'users', name: 'المستخدمون', icon: Icons.manage_accounts_rounded),
    (key: 'branches', name: 'نسخ العملاء', icon: Icons.copy_all_rounded),
    (key: 'settings', name: 'الإعدادات', icon: Icons.settings_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final visibleSections = NineSoftModuleTaxonomy.order(
      sections.where((item) => isSectionAllowed(item.key)),
      (item) => item.key,
    );
    return Container(
      width: 278,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [NizamiColors.navy, Color(0xFF06182E)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(18, 18, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: NineSoftBrandLogo(
                          height: 68,
                          padding: EdgeInsets.all(3),
                          borderRadius: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'NineSoft',
                          style: TextStyle(
                            color: Color(0xFF73E7D4),
                            fontFamily: 'ArialMTBlack',
                            fontSize: 9,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .055),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 19,
                          backgroundColor: const Color(0xFF273D69),
                          foregroundColor: Colors.white,
                          child: Text(
                            tenantName.trim().isEmpty
                                ? 'N'
                                : tenantName.trim().characters.first,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'مساحة العمل',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                tenantName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white60,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _NavigationGroupLabel('مساحة العمل'),
                    _NavigationItem(
                      title: 'الرئيسية',
                      icon: Icons.home_rounded,
                      selected: activeSection.isEmpty,
                      onTap: onGoHome,
                    ),
                    for (final group in NineSoftModuleGroup.values) ...[
                      const SizedBox(height: 6),
                      _NavigationGroupLabel(
                        NineSoftModuleTaxonomy.labelFor(group),
                      ),
                      for (final item in visibleSections.where(
                        (item) =>
                            NineSoftModuleTaxonomy.groupFor(item.key) == group,
                      ))
                        _NavigationItem(
                          title: item.name,
                          icon: item.icon,
                          selected: item.key == activeSection,
                          onTap: () => onOpenSection(item.key),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.store_mall_directory_rounded,
                      color: Colors.white70,
                      size: 21,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        tenantName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NineSoftDesktopTopBar extends StatelessWidget {
  const NineSoftDesktopTopBar({
    super.key,
    required this.displayName,
    required this.openTabs,
    required this.activeTabId,
    required this.onActivateTab,
    required this.onCloseTab,
    required this.onToggleTheme,
    required this.onLogout,
    required this.dark,
    required this.activeSection,
    required this.onGoHome,
    required this.onOpenApps,
    required this.onOpenReports,
    required this.onSearch,
  });

  final String displayName;
  final List<NineSoftOpenTab> openTabs;
  final String? activeTabId;
  final ValueChanged<String> onActivateTab;
  final ValueChanged<String> onCloseTab;
  final VoidCallback onToggleTheme;
  final VoidCallback onLogout;
  final bool dark;
  final String activeSection;
  final VoidCallback onGoHome;
  final VoidCallback onOpenApps;
  final VoidCallback onOpenReports;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 76,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) => Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  children: [
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: PopupMenuButton<String>(
                        tooltip: 'خيارات الحساب',
                        onSelected: (value) {
                          if (value == 'logout') onLogout();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'logout',
                            child: Text('تسجيل الخروج'),
                          ),
                        ],
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: NizamiColors.blueSoft,
                              foregroundColor: NizamiColors.blue,
                              child: Text(
                                displayName.trim().isEmpty
                                    ? 'N'
                                    : displayName.trim().characters.first,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 130),
                              child: Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: dark ? 'الوضع النهاري' : 'الوضع الليلي',
                      onPressed: onToggleTheme,
                      icon: Icon(
                        dark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                      ),
                    ),
                    IconButton(
                      tooltip: 'التنبيهات',
                      onPressed: () {},
                      icon: const Icon(Icons.notifications_none_rounded),
                    ),
                    if (constraints.maxWidth > 1450) ...[
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 360,
                        child: Directionality(
                          textDirection: TextDirection.rtl,
                          child: TextField(
                            onSubmitted: onSearch,
                            decoration: const InputDecoration(
                              hintText: 'ابحث عن قسم أو إجراء...',
                              prefixIcon: Icon(Icons.search_rounded),
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Row(
                        children: [
                          _TopRouteButton(
                            label: 'الرئيسية',
                            selected: activeSection.isEmpty,
                            onTap: onGoHome,
                          ),
                          _TopRouteButton(
                            label: 'التطبيقات',
                            selected: false,
                            onTap: onOpenApps,
                          ),
                          _TopRouteButton(
                            label: 'التقارير',
                            selected: activeSection == 'reports',
                            onTap: onOpenReports,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.arrow_back_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            openTabs.isEmpty
                                ? 'الرئيسية'
                                : openTabs
                                          .where((tab) => tab.id == activeTabId)
                                          .map((tab) => tab.title)
                                          .firstOrNull ??
                                      'الرئيسية',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (openTabs.isNotEmpty)
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: openTabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 5),
              itemBuilder: (context, index) {
                final tab = openTabs[index];
                final active = tab.id == activeTabId;
                return InputChip(
                  selected: active,
                  label: Text(tab.title),
                  onSelected: (_) => onActivateTab(tab.id),
                  onDeleted: () => onCloseTab(tab.id),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16),
                );
              },
            ),
          ),
        const Divider(),
      ],
    ),
  );
}


class NineSoftDesktopTaskbar extends StatelessWidget {
  const NineSoftDesktopTaskbar({
    super.key,
    required this.activeSection,
    required this.activeTabId,
    required this.openTabs,
    required this.onGoHome,
    required this.onOpenApps,
    required this.onOpenSection,
    required this.onActivateTab,
  });

  final String activeSection;
  final String? activeTabId;
  final List<NineSoftOpenTab> openTabs;
  final VoidCallback onGoHome;
  final VoidCallback onOpenApps;
  final ValueChanged<String> onOpenSection;
  final ValueChanged<String> onActivateTab;

  static const _pinned = <({String key, String label, IconData icon, Color color})>[
    (
      key: 'sales',
      label: 'المبيعات',
      icon: Icons.point_of_sale_rounded,
      color: Color(0xFF7C3AED),
    ),
    (
      key: 'purchases',
      label: 'المشتريات',
      icon: Icons.shopping_bag_rounded,
      color: Color(0xFF1677E8),
    ),
    (
      key: 'products',
      label: 'الأصناف',
      icon: Icons.inventory_2_rounded,
      color: Color(0xFFF08A18),
    ),
    (
      key: 'customers',
      label: 'العملاء',
      icon: Icons.groups_rounded,
      color: Color(0xFF089EAA),
    ),
    (
      key: 'reports',
      label: 'التقارير',
      icon: Icons.insights_rounded,
      color: Color(0xFF7047D7),
    ),
  ];

  @override
  Widget build(BuildContext context) => Material(
    elevation: 14,
    color: Theme.of(context).colorScheme.surface,
    surfaceTintColor: Colors.transparent,
    child: Container(
      key: const Key('ninesoft-desktop-taskbar'),
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: .55),
          ),
        ),
      ),
      child: Row(
        children: [
          _TaskbarStartButton(onTap: onOpenApps),
          const SizedBox(width: 8),
          _TaskbarIconButton(
            icon: Icons.home_rounded,
            label: 'الرئيسية',
            color: NizamiColors.blue,
            selected: activeSection.isEmpty,
            onTap: onGoHome,
          ),
          const SizedBox(width: 4),
          for (final item in _pinned) ...[
            _TaskbarIconButton(
              icon: item.icon,
              label: item.label,
              color: item.color,
              selected: activeSection == item.key,
              onTap: () => onOpenSection(item.key),
            ),
            const SizedBox(width: 4),
          ],
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 34,
            color: Theme.of(context).dividerColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: openTabs.isEmpty
                ? Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'المحررات المفتوحة ستظهر هنا',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: openTabs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 5),
                    itemBuilder: (context, index) {
                      final tab = openTabs[index];
                      final selected = tab.id == activeTabId;
                      return ActionChip(
                        key: Key('taskbar-tab-${tab.id}'),
                        avatar: Icon(
                          selected ? Icons.radio_button_checked_rounded : Icons.circle_outlined,
                          size: 15,
                        ),
                        label: Text(tab.title),
                        onPressed: () => onActivateTab(tab.id),
                        side: BorderSide(
                          color: selected
                              ? NizamiColors.blue.withValues(alpha: .45)
                              : Theme.of(context).dividerColor,
                        ),
                        backgroundColor: selected
                            ? NizamiColors.blueSoft.withValues(alpha: .45)
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                      );
                    },
                  ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'اختصارات: F2 بيع • F3 شراء • F6 قبض • F7 صرف • F8 قيد • F9 كشف حساب',
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.keyboard_rounded, size: 18),
                  SizedBox(width: 5),
                  Text('F2–F9', textDirection: TextDirection.ltr),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TaskbarStartButton extends StatelessWidget {
  const _TaskbarStartButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    key: const Key('ninesoft-start-button'),
    onPressed: onTap,
    icon: const Icon(Icons.grid_view_rounded, size: 20),
    label: const Text('ابدأ'),
    style: FilledButton.styleFrom(
      backgroundColor: NizamiColors.navy,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

class _TaskbarIconButton extends StatelessWidget {
  const _TaskbarIconButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Material(
      color: selected ? color.withValues(alpha: .12) : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: selected
                ? Border.all(color: color.withValues(alpha: .32))
                : null,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    ),
  );
}

class _NavigationGroupLabel extends StatelessWidget {
  const _NavigationGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 7),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _TopRouteButton extends StatelessWidget {
  const _TopRouteButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: selected ? NizamiColors.blue : Colors.transparent,
          width: 3,
        ),
      ),
    ),
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected
            ? NizamiColors.blue
            : Theme.of(context).colorScheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        shape: const RoundedRectangleBorder(),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    ),
  );
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Material(
      color: selected ? NizamiColors.blue : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : Colors.white70,
                size: 21,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_left_rounded,
                color: selected ? Colors.white70 : Colors.white30,
                size: 17,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
