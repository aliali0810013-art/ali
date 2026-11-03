import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/nizami_theme.dart';
import 'ninesoft_module_taxonomy.dart';

typedef AtlasAppGroup = NineSoftModuleGroup;

class AtlasAppDefinition {
  const AtlasAppDefinition({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.group,
  });

  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final AtlasAppGroup group;
}

IconData _modernModuleIcon(AtlasAppDefinition app) => switch (app.key) {
  'sales' => Icons.point_of_sale_rounded,
  'sales.returns' => Icons.assignment_return_rounded,
  'purchases' || 'purchases.invoices' => Icons.shopping_bag_rounded,
  'purchases.returns' => Icons.assignment_return_outlined,
  'products' || 'inventory.inquiry' => Icons.category_rounded,
  'inventory' || 'inventory.counts' || 'inventory.transfers' =>
    Icons.warehouse_rounded,
  'customers' => Icons.group_rounded,
  'suppliers' => Icons.local_shipping_rounded,
  'cashbox' => Icons.savings_rounded,
  'debts' || 'debts.receipts' || 'debts.payments' =>
    Icons.account_balance_wallet_rounded,
  'accounts' || 'accounts.accounts' => Icons.account_balance_rounded,
  'accounts.journals' => Icons.note_alt_rounded,
  'accounts.statements' => Icons.receipt_long_rounded,
  'accounts.transfers' => Icons.swap_horiz_rounded,
  'accounts.opening' => Icons.playlist_add_check_circle_rounded,
  'reports' ||
  'accounts.financial' ||
  'reports.financial' ||
  'reports.trial' ||
  'reports.profit-loss' ||
  'reports.balance-sheet' ||
  'reports.cash-flow' => Icons.insights_rounded,
  'payroll' => Icons.badge_rounded,
  'users' => Icons.admin_panel_settings_rounded,
  'branches' => Icons.business_rounded,
  'backup' => Icons.cloud_sync_rounded,
  'whatsapp' => Icons.chat_bubble_rounded,
  'wasl' => Icons.account_balance_rounded,
  'settings' => Icons.tune_rounded,
  _ => app.icon,
};

Color _modernModuleColor(AtlasAppDefinition app) => switch (app.key) {
  'sales' => const Color(0xFF7C3AED),
  'sales.returns' => const Color(0xFFEC4870),
  'purchases' || 'purchases.invoices' => const Color(0xFF1677E8),
  'purchases.returns' => const Color(0xFFE85D3F),
  'products' || 'inventory.inquiry' => const Color(0xFFF08A18),
  'inventory' || 'inventory.counts' || 'inventory.transfers' =>
    const Color(0xFFF07816),
  'customers' => const Color(0xFF089EAA),
  'suppliers' => const Color(0xFF0B9CAD),
  'cashbox' => const Color(0xFFEAAA00),
  'debts' || 'debts.receipts' || 'debts.payments' => const Color(0xFF10A36D),
  'accounts' || 'accounts.accounts' || 'accounts.journals' =>
    const Color(0xFFE04455),
  'reports' ||
  'accounts.financial' ||
  'reports.financial' ||
  'reports.trial' ||
  'reports.profit-loss' ||
  'reports.balance-sheet' ||
  'reports.cash-flow' => const Color(0xFF7047D7),
  'payroll' => const Color(0xFF008F8C),
  'users' => const Color(0xFF1386C9),
  'branches' => const Color(0xFF0CA88E),
  'backup' => const Color(0xFF1680D0),
  'whatsapp' => const Color(0xFF06A96D),
  'wasl' => const Color(0xFF0F958E),
  'settings' => const Color(0xFF64748B),
  _ => app.color,
};

class _QuickLauncherAction {
  const _QuickLauncherAction({
    required this.key,
    required this.root,
    required this.label,
    required this.shortcut,
    required this.icon,
    required this.color,
  });

  final String key;
  final String root;
  final String label;
  final String shortcut;
  final IconData icon;
  final Color color;
}

const _quickLauncherActions = <_QuickLauncherAction>[
  _QuickLauncherAction(
    key: 'sales',
    root: 'sales',
    label: 'فاتورة بيع',
    shortcut: 'F2',
    icon: Icons.point_of_sale_rounded,
    color: Color(0xFF7C3AED),
  ),
  _QuickLauncherAction(
    key: 'purchases.invoices',
    root: 'purchases',
    label: 'فاتورة شراء',
    shortcut: 'F3',
    icon: Icons.shopping_cart_checkout_rounded,
    color: Color(0xFF1677E8),
  ),
  _QuickLauncherAction(
    key: 'debts.receipts',
    root: 'debts',
    label: 'سند قبض',
    shortcut: 'F6',
    icon: Icons.south_west_rounded,
    color: Color(0xFF10A36D),
  ),
  _QuickLauncherAction(
    key: 'debts.payments',
    root: 'debts',
    label: 'سند صرف',
    shortcut: 'F7',
    icon: Icons.north_east_rounded,
    color: Color(0xFFE65353),
  ),
  _QuickLauncherAction(
    key: 'accounts.journals',
    root: 'accounts',
    label: 'قيد يومي',
    shortcut: 'F8',
    icon: Icons.note_alt_rounded,
    color: Color(0xFFE04455),
  ),
  _QuickLauncherAction(
    key: 'accounts.statements',
    root: 'accounts',
    label: 'كشف حساب',
    shortcut: 'F9',
    icon: Icons.receipt_long_rounded,
    color: Color(0xFF7047D7),
  ),
];

class NineSoftAppLauncher extends StatefulWidget {
  const NineSoftAppLauncher({
    super.key,
    required this.apps,
    required this.onOpen,
    this.initialQuery = '',
  });

  static const _favoritesKey = 'ninesoft.atlas.favorites';

  final List<AtlasAppDefinition> apps;
  final ValueChanged<String> onOpen;
  final String initialQuery;

  static Future<void> show(
    BuildContext context, {
    required List<AtlasAppDefinition> apps,
    required ValueChanged<String> onOpen,
    String initialQuery = '',
  }) => showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'إغلاق قائمة التطبيقات',
    barrierColor: Colors.black.withValues(alpha: .40),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => SafeArea(
      child: NineSoftAppLauncher(
        apps: apps,
        onOpen: onOpen,
        initialQuery: initialQuery,
      ),
    ),
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(.04, .08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );

  @override
  State<NineSoftAppLauncher> createState() => _NineSoftAppLauncherState();
}

class _NineSoftAppLauncherState extends State<NineSoftAppLauncher> {
  late final TextEditingController _search = TextEditingController(
    text: widget.initialQuery,
  );
  final Set<String> _favorites = <String>{};
  AtlasAppGroup? _group;
  bool _favoritesOnly = false;
  bool _loadingFavorites = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _favorites.addAll(
        prefs.getStringList(NineSoftAppLauncher._favoritesKey) ?? const [],
      );
      _loadingFavorites = false;
    });
  }

  Future<void> _toggleFavorite(String key) async {
    setState(() {
      if (!_favorites.add(key)) _favorites.remove(key);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      NineSoftAppLauncher._favoritesKey,
      _favorites.toList()..sort(),
    );
  }

  List<AtlasAppDefinition> get _visibleApps {
    final query = _search.text.trim().toLowerCase();
    return widget.apps.where((app) {
      if (_favoritesOnly && !_favorites.contains(app.key)) return false;
      if (_group != null && app.group != _group) return false;
      if (query.isEmpty) return true;
      return app.title.toLowerCase().contains(query) ||
          app.subtitle.toLowerCase().contains(query) ||
          app.key.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  bool _hasRoot(String root) => widget.apps.any((app) => app.key == root);

  void _open(String key) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onOpen(key));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final phone = size.width < 620;
    final panelWidth = phone ? size.width - 16 : 680.0;
    final panelHeight = phone
        ? size.height - 20
        : (size.height * .82).clamp(620.0, 760.0).toDouble();
    final apps = _visibleApps;
    final quick = _quickLauncherActions
        .where((action) => _hasRoot(action.root))
        .toList(growable: false);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Align(
        key: const Key('ninesoft-left-app-drawer'),
        alignment: phone ? Alignment.bottomCenter : Alignment.bottomRight,
        child: Padding(
          padding: EdgeInsets.all(phone ? 8 : 14),
          child: SizedBox(
            width: panelWidth,
            height: panelHeight,
            child: Material(
              elevation: 24,
              color: Theme.of(context).colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              borderRadius: BorderRadius.circular(phone ? 28 : 30),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LauncherHeader(
                    onClose: () => Navigator.of(context).pop(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TextField(
                      controller: _search,
                      autofocus: widget.initialQuery.isNotEmpty,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'ابحث عن قسم أو إجراء أو مستند...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'مسح البحث',
                                onPressed: () {
                                  _search.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                  ),
                  if (quick.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(Icons.bolt_rounded, color: Color(0xFFFFA000), size: 19),
                          const SizedBox(width: 6),
                          Text(
                            'تحرير سريع',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'اختصارات الكاشير',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 78,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: quick.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, index) => _QuickLauncherTile(
                          action: quick[index],
                          onTap: () => _open(quick[index].key),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    height: 42,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      children: [
                        _filterChip(
                          'الكل',
                          selected: _group == null && !_favoritesOnly,
                          onTap: () {
                            setState(() {
                              _group = null;
                              _favoritesOnly = false;
                            });
                          },
                        ),
                        for (final group in NineSoftModuleGroup.values)
                          _filterChip(
                            NineSoftModuleTaxonomy.labelFor(group),
                            selected: _group == group,
                            onTap: () {
                              setState(() {
                                _group = group;
                                _favoritesOnly = false;
                              });
                            },
                          ),
                        _filterChip(
                          'المفضلة',
                          selected: _favoritesOnly,
                          icon: Icons.star_rounded,
                          onTap: () {
                            setState(() {
                              _group = null;
                              _favoritesOnly = true;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: _loadingFavorites
                        ? const Center(child: CircularProgressIndicator())
                        : apps.isEmpty
                            ? const _LauncherEmptyState()
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final columns = constraints.maxWidth < 420
                                      ? 4
                                      : constraints.maxWidth < 580
                                          ? 5
                                          : 6;
                                  return GridView.builder(
                                    key: const Key('mobile-app-library-grid'),
                                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 10,
                                      childAspectRatio: .79,
                                    ),
                                    itemCount: apps.length,
                                    itemBuilder: (_, index) {
                                      final app = apps[index];
                                      return _LauncherAppIcon(
                                        key: Key('launcher-app-${app.key}'),
                                        app: app,
                                        favorite: _favorites.contains(app.key),
                                        onOpen: () => _open(app.key),
                                        onFavorite: () => _toggleFavorite(app.key),
                                      );
                                    },
                                  );
                                },
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

  Widget _filterChip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 7),
    child: FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: icon == null ? null : Icon(icon, size: 17),
      label: Text(label),
    ),
  );
}

class _LauncherHeader extends StatelessWidget {
  const _LauncherHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [
          NizamiColors.navy,
          NizamiColors.navy.withValues(alpha: .92),
          const Color(0xFF0A5670),
        ],
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withValues(alpha: .14)),
          ),
          child: const Icon(Icons.grid_view_rounded, color: Colors.white),
        ),
        const SizedBox(width: 11),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'قائمة NineSoft',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'الأقسام والمحررات والاختصارات في مكان واحد',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'إغلاق',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
      ],
    ),
  );
}

class _QuickLauncherTile extends StatelessWidget {
  const _QuickLauncherTile({required this.action, required this.onTap});

  final _QuickLauncherAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 104,
    child: Material(
      color: action.color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: action.color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(action.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10),
                    ),
                    Text(
                      action.shortcut,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: action.color,
                        fontWeight: FontWeight.w900,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LauncherAppIcon extends StatelessWidget {
  const _LauncherAppIcon({
    super.key,
    required this.app,
    required this.favorite,
    required this.onOpen,
    required this.onFavorite,
  });

  final AtlasAppDefinition app;
  final bool favorite;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final color = _modernModuleColor(app);
    final icon = _modernModuleIcon(app);
    return Tooltip(
      message: app.subtitle,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        onLongPress: onFavorite,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [color.withValues(alpha: .78), color],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: .22),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 29),
                  ),
                  if (favorite)
                    PositionedDirectional(
                      end: -4,
                      top: -4,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          shape: BoxShape.circle,
                          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black12)],
                        ),
                        child: const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFB000),
                          size: 15,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                app.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
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

class _LauncherEmptyState extends StatelessWidget {
  const _LauncherEmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.apps_outage_rounded,
          size: 52,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 10),
        const Text(
          'لا توجد تطبيقات مطابقة',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const Text('غيّر البحث أو التصفية لعرض بقية الأقسام.'),
      ],
    ),
  );
}
