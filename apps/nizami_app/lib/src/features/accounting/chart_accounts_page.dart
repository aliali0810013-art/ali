import 'dart:async';

import 'package:flutter/material.dart';

import '../sync/realtime_sync_coordinator.dart';
import '../../theme/ninesoft_ui.dart';
import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/nizami_theme.dart';

import 'chart_accounts_api.dart';
import 'chart_accounts_view_model.dart';

class ChartAccountsPage extends StatefulWidget {
  const ChartAccountsPage({
    super.key,
    required this.token,
    required this.branchIds,
    required this.roleCode,
    this.chartAccountsApi,
  });
  final String token;
  final List<String> branchIds;
  final String roleCode;
  final ChartAccountsApi? chartAccountsApi;
  @override
  State<ChartAccountsPage> createState() => _ChartAccountsPageState();
}

class _ChartAccountsPageState extends State<ChartAccountsPage> {
  late final ChartAccountsApi _api =
      widget.chartAccountsApi ?? ChartAccountsApi(widget.token);
  List<ChartAccount> _items = [];
  String? _branchId;
  bool _loading = true;
  final _searchController = TextEditingController();
  String _query = '';
  String _typeFilter = '';
  bool _showTotals = false;
  final Set<String> _expandedIds = <String>{};
  String? _selectedAccountId;
  StreamSubscription<Set<String>>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _branchId = widget.branchIds.isEmpty ? null : widget.branchIds.first;
    _syncSubscription = RealtimeSyncCoordinator.instance.changes.listen((
      types,
    ) {
      if (types.contains('chart_account') ||
          types.contains('journal_entry') ||
          types.contains('invoice')) {
        if (mounted && !_loading) unawaited(_load());
      }
    });
    _load();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<ChartAccount> get _visibleItems {
    return visibleChartAccounts(
      accounts: _items,
      expandedIds: _expandedIds,
      query: _query,
      type: _typeFilter,
    );
  }

  Future<void> _load() async {
    if (_branchId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await _api.list(_branchId!);
      if (mounted) {
        setState(() {
          _items = rows;
          _selectedAccountId ??= rows.isEmpty ? null : rows.first.id;
          if (_expandedIds.isEmpty) {
            _expandedIds.addAll(
              rows
                  .where((item) => item.parentId == null)
                  .map((item) => item.id),
            );
          }
        });
      }
    } catch (error) {
      _message(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  String _type(String value) =>
      const {
        'asset': 'أصول',
        'liability': 'التزامات',
        'equity': 'حقوق ملكية',
        'revenue': 'إيرادات',
        'expense': 'مصروفات',
      }[value] ??
      value;

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    final visibleItems = _visibleItems;
    final totals = chartRootTotals(_items);
    return Scaffold(
      appBar: AppBar(
        title: const Text('شجرة الحسابات'),
        toolbarHeight: 0,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton:
          !desktop && widget.roleCode == 'owner' && _branchId != null
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('حساب جديد'),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: NineSoftResponsiveBody(
            child: SingleChildScrollView(
              key: const Key('chart-accounts-page-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NineSoftPageHeader(
                    title: 'شجرة الحسابات',
                    subtitle: 'كل حسابات المنشأة مرتبة من الرئيسي إلى الفرعي',
                    icon: Icons.account_tree_rounded,
                    color: NizamiColors.blue,
                    actions: [
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('تحديث'),
                      ),
                      if (widget.roleCode == 'owner' && _branchId != null)
                        FilledButton.icon(
                          key: const Key('chart-account-add-action'),
                          onPressed: () => _edit(),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('إضافة حساب'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _quickGuide(),
                  const SizedBox(height: 12),
                  if (widget.branchIds.length > 1)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: DropdownButtonFormField<String>(
                        initialValue: _branchId,
                        decoration: const InputDecoration(
                          labelText: 'الفرع',
                          prefixIcon: Icon(Icons.store_rounded),
                        ),
                        items: widget.branchIds
                            .map(
                              (id) =>
                                  DropdownMenuItem(value: id, child: Text(id)),
                            )
                            .toList(),
                        onChanged: (value) {
                          _branchId = value;
                          _load();
                        },
                      ),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _showTotals = !_showTotals),
                      icon: Icon(
                        _showTotals
                            ? Icons.expand_less_rounded
                            : Icons.analytics_outlined,
                      ),
                      label: Text(
                        _showTotals ? 'إخفاء الإجماليات' : 'عرض الإجماليات',
                      ),
                    ),
                  ),
                  if (_showTotals)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _accountMetric(
                          'الأصول',
                          totals['asset'] ?? 0,
                          NizamiColors.green,
                          Icons.account_balance_wallet_rounded,
                        ),
                        _accountMetric(
                          'الالتزامات',
                          totals['liability'] ?? 0,
                          NizamiColors.red,
                          Icons.credit_card_rounded,
                        ),
                        _accountMetric(
                          'حقوق الملكية',
                          totals['equity'] ?? 0,
                          NizamiColors.purple,
                          Icons.pie_chart_rounded,
                        ),
                        _accountMetric(
                          'الإيرادات',
                          totals['revenue'] ?? 0,
                          NizamiColors.amber,
                          Icons.trending_up_rounded,
                        ),
                        _accountMetric(
                          'المصروفات',
                          totals['expense'] ?? 0,
                          NizamiColors.blue,
                          Icons.receipt_long_rounded,
                        ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  NineSoftPanel(
                    child: Column(
                      children: [
                        NineSoftSearchField(
                          controller: _searchController,
                          hintText: 'ابحث باسم الحساب أو رمزه ...',
                          onChanged: (value) => setState(() => _query = value),
                          onClear: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            _typeChip('', 'الكل'),
                            _typeChip('asset', 'الأصول'),
                            _typeChip('liability', 'الالتزامات'),
                            _typeChip('equity', 'حقوق الملكية'),
                            _typeChip('revenue', 'الإيرادات'),
                            _typeChip('expense', 'المصروفات'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 80),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (desktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _accountList(visibleItems)),
                        const SizedBox(width: 12),
                        SizedBox(width: 310, child: _accountDetails()),
                      ],
                    )
                  else
                    _accountList(visibleItems),
                  const SizedBox(height: 96),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickGuide() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: NizamiColors.blue.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: NizamiColors.blue.withValues(alpha: .16)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.touch_app_rounded, color: NizamiColors.blue),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'ابدأ من نوع الحساب، ثم افتح السهم لرؤية الحسابات الفرعية. '
            'الحساب التجميعي ينظم الشجرة، أما الحساب التفصيلي فهو الذي يقبل الترحيل.',
            style: TextStyle(height: 1.55, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _accountMetric(
    String label,
    int amountMinor,
    Color color,
    IconData icon,
  ) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 6),
    child: Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 1, style: const TextStyle(fontSize: 11)),
                Text(
                  '${(amountMinor / 100).toStringAsFixed(2)} YER',
                  maxLines: 1,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: 'ArialMTBlack',
                    fontSize: 11,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _typeChip(String value, String label) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 7),
    child: ChoiceChip(
      label: Text(label),
      selected: _typeFilter == value,
      onSelected: (_) => setState(() => _typeFilter = value),
    ),
  );

  Widget _accountList(List<ChartAccount> visibleItems) => visibleItems.isEmpty
      ? Container(
          constraints: const BoxConstraints(minHeight: 180),
          alignment: Alignment.center,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_tree_outlined, size: 42),
              SizedBox(height: 10),
              Text('لا توجد حسابات مطابقة للبحث والتصفية.'),
            ],
          ),
        )
      : Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
          child: Column(
            children: [
              for (final account in visibleItems) _accountTile(account),
            ],
          ),
        );

  Color _typeColor(String type) => switch (type) {
    'asset' => const Color(0xFF11A879),
    'liability' => const Color(0xFFEC5265),
    'equity' => const Color(0xFF7657D8),
    'revenue' => const Color(0xFFFF8A1D),
    'expense' => const Color(0xFF2B7EEA),
    _ => NizamiColors.blue,
  };

  IconData _typeIcon(String type) => switch (type) {
    'asset' => Icons.account_balance_wallet_rounded,
    'liability' => Icons.credit_card_rounded,
    'equity' => Icons.pie_chart_rounded,
    'revenue' => Icons.trending_up_rounded,
    'expense' => Icons.receipt_long_rounded,
    _ => Icons.account_balance_rounded,
  };

  Widget _accountDetails() {
    ChartAccount? selected;
    for (final account in _items) {
      if (account.id == _selectedAccountId) {
        selected = account;
        break;
      }
    }
    if (selected == null) {
      return const NineSoftPanel(
        child: Center(child: Text('اختر حسابًا لعرض تفاصيله.')),
      );
    }
    final account = selected;
    final color = _typeColor(account.type);
    final children = _items.where((item) => item.parentId == account.id).length;
    return NineSoftPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [color, color.withValues(alpha: .72)],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_typeIcon(account.type), color: Colors.white, size: 34),
                const SizedBox(height: 14),
                Text(
                  account.nameAr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (account.nameEn.isNotEmpty)
                  Text(
                    account.nameEn,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: Colors.white70),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _detailRow('رمز الحساب', account.code),
                _detailRow('نوع الحساب', _type(account.type)),
                _detailRow(
                  'التصنيف المالي',
                  _classificationLabel(account.classification),
                ),
                _detailRow(
                  'الحساب الختامي',
                  account.closingStatement == 'profit_loss'
                      ? 'الأرباح والخسائر'
                      : 'المركز المالي',
                ),
                if (account.isCashEquivalent)
                  _detailRow('حساب نقدي', 'صندوق / بنك / محفظة'),
                _detailRow(
                  'طبيعة الحساب',
                  account.allowPosting ? 'تفصيلي — يسمح بالترحيل' : 'تجميعي',
                ),
                _detailRow('الحسابات الفرعية', '$children'),
                _detailRow(
                  'الرصيد الحالي',
                  '${(account.balanceMinor / 100).toStringAsFixed(2)} YER',
                  ltr: true,
                ),
                const SizedBox(height: 12),
                if (widget.roleCode == 'owner') ...[
                  FilledButton.icon(
                    onPressed: () => _edit(account: account),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل الحساب'),
                  ),
                  if (!account.allowPosting && account.active) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _edit(parent: account),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('إضافة حساب فرعي'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool ltr = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textDirection: ltr ? TextDirection.ltr : null,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontFamily: ltr ? 'ArialMTBlack' : null,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _accountTile(ChartAccount account) {
    final balance = '${(account.balanceMinor / 100).toStringAsFixed(2)} YER';
    final depth = _accountDepth(account);
    final hasChildren = _items.any((item) => item.parentId == account.id);
    final expanded = _expandedIds.contains(account.id);
    final color = _typeColor(account.type);
    final selected = _selectedAccountId == account.id;
    return Card(
      color: selected ? color.withValues(alpha: .085) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(
          color: selected
              ? color.withValues(alpha: .55)
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      margin: EdgeInsetsDirectional.only(start: depth * 18, top: 3, bottom: 3),
      child: ListTile(
        dense: true,
        minVerticalPadding: 3,
        visualDensity: const VisualDensity(vertical: -2),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: account.parentId == null ? 42 : 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            const SizedBox(width: 5),
            if (hasChildren)
              IconButton(
                tooltip: expanded
                    ? 'طي الحسابات الفرعية'
                    : 'عرض الحسابات الفرعية',
                onPressed: () => setState(() {
                  if (expanded) {
                    _expandedIds.remove(account.id);
                  } else {
                    _expandedIds.add(account.id);
                  }
                }),
                icon: AnimatedRotation(
                  turns: expanded ? .25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.chevron_right_rounded, color: color),
                ),
              )
            else
              CircleAvatar(
                radius: 17,
                backgroundColor: color.withValues(alpha: .1),
                child: Icon(
                  account.allowPosting
                      ? Icons.account_balance_wallet_outlined
                      : Icons.folder_outlined,
                  color: color,
                  size: 19,
                ),
              ),
          ],
        ),
        title: Text(
          account.nameAr,
          style: TextStyle(
            fontWeight: account.parentId == null
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              account.nameEn.isEmpty
                  ? _type(account.type)
                  : '${_type(account.type)} • ${account.nameEn}',
            ),
            Text(
              account.code,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontFamily: 'ArialMTBlack'),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              balance,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: 'ArialMTBlack',
              ),
            ),
            if (widget.roleCode == 'owner' &&
                !account.allowPosting &&
                account.active)
              IconButton(
                tooltip: 'إضافة حساب فرعي',
                onPressed: () => _edit(parent: account),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            if (widget.roleCode == 'owner')
              IconButton(
                tooltip: 'تعديل الحساب',
                onPressed: () => _edit(account: account),
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        onTap: () => setState(() => _selectedAccountId = account.id),
      ),
    );
  }

  double _accountDepth(ChartAccount account) {
    var depth = 0;
    var parentId = account.parentId;
    final visited = <String>{account.id};
    while (parentId != null && depth < 50 && visited.add(parentId)) {
      depth++;
      ChartAccount? parent;
      for (final candidate in _items) {
        if (candidate.id == parentId) {
          parent = candidate;
          break;
        }
      }
      parentId = parent?.parentId;
    }
    return depth.clamp(0, 8).toDouble();
  }

  Future<void> _edit({ChartAccount? account, ChartAccount? parent}) async {
    final code = TextEditingController(text: account?.code);
    final ar = TextEditingController(text: account?.nameAr);
    final en = TextEditingController(text: account?.nameEn);
    final sortCtrl = TextEditingController(text: '${account?.sortOrder ?? 0}');
    var type = account?.type ?? parent?.type ?? 'asset';
    var classification = account?.classification.isNotEmpty == true
        ? account!.classification
        : _defaultClassification(type);
    var isCashEquivalent = account?.isCashEquivalent ?? false;
    String? parentId = account?.parentId ?? parent?.id;
    var posting = account?.allowPosting ?? true;
    var active = account?.active ?? true;
    final save = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (pageContext, localSet) => Scaffold(
            key: const ValueKey('chart-account-inline-editor'),
            appBar: AppBar(toolbarHeight: 0),
            body: SafeArea(
              child: NineSoftResponsiveBody(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: [
NineSoftEntryHeading(
                    title: account == null
                        ? 'إضافة حساب محاسبي'
                        : 'تحرير حساب محاسبي',
                    subtitle:
                        'الترقيم والتصنيف ثم خصائص الحساب وصلاحية الترحيل',
                    icon: Icons.account_tree_rounded,
                    status: 'شجرة الحسابات',
                    accent: NizamiColors.blue,
                  ),
                  const SizedBox(height: 12),
                  NineSoftEntrySection(
                    title: 'بيانات الحساب الأساسية',
                    subtitle: 'رمز الحساب وأسماؤه باللغة العربية والإنجليزية',
                    icon: Icons.badge_outlined,
                    step: '01',
                    accent: NizamiColors.blue,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: code,
                          enabled: account == null,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                            labelText:
                                'رمز الحساب (اتركه فارغًا للترقيم التلقائي)',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: ar,
                          decoration: const InputDecoration(
                            labelText: 'اسم الحساب بالعربي',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: en,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                            labelText: 'اسم الحساب بالإنجليزي',
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  NineSoftEntrySection(
                    title: 'التصنيف والصلاحيات',
                    subtitle:
                        'تحديد نوع الحساب والأب وخيارات الترحيل والاستخدام',
                    icon: Icons.account_balance_outlined,
                    step: '02',
                    accent: NizamiColors.green,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: type,
                          decoration: const InputDecoration(
                            labelText: 'نوع الحساب',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'asset',
                              child: Text('أصول'),
                            ),
                            DropdownMenuItem(
                              value: 'liability',
                              child: Text('التزامات'),
                            ),
                            DropdownMenuItem(
                              value: 'equity',
                              child: Text('حقوق ملكية'),
                            ),
                            DropdownMenuItem(
                              value: 'revenue',
                              child: Text('إيرادات'),
                            ),
                            DropdownMenuItem(
                              value: 'expense',
                              child: Text('مصروفات'),
                            ),
                          ],
                          onChanged: account == null
                              ? (value) => localSet(() {
                                  type = value!;
                                  classification = _defaultClassification(type);
                                  isCashEquivalent = false;
                                  parentId = null;
                                })
                              : null,
                        ),
                        ...[
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String?>(
                            initialValue: parentId,
                            decoration: const InputDecoration(
                              labelText: 'الحساب الأب (اختياري)',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('حساب رئيسي'),
                              ),
                              ..._items
                                  .where(
                                    (item) =>
                                        item.id != account?.id &&
                                        item.type == type &&
                                        item.active &&
                                        !item.allowPosting,
                                  )
                                  .map(
                                    (item) => DropdownMenuItem<String?>(
                                      value: item.id,
                                      child: Text(
                                        '${item.code} — ${item.nameAr}',
                                      ),
                                    ),
                                  ),
                            ],
                            onChanged: (value) =>
                                localSet(() => parentId = value),
                          ),
                        ],
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: classification,
                          decoration: const InputDecoration(
                            labelText: 'التصنيف المالي الفرعي',
                          ),
                          items: _classificationOptions(type)
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_classificationLabel(value)),
                                ),
                              )
                              .toList(),
                          onChanged: account?.isSystem == true
                              ? null
                              : (value) => localSet(() {
                                  classification = value!;
                                  if (classification != 'current_asset') {
                                    isCashEquivalent = false;
                                  }
                                }),
                        ),
                        if (classification == 'current_asset')
                          SwitchListTile(
                            value: isCashEquivalent,
                            onChanged: account?.isSystem == true
                                ? null
                                : (value) =>
                                      localSet(() => isCashEquivalent = value),
                            title: const Text('صندوق / بنك / محفظة نقدية'),
                            subtitle: const Text(
                              'يظهر ضمن حسابات الدفع والتحصيل والتحويلات',
                            ),
                          ),
                        if (account != null) ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: sortCtrl,
                            keyboardType: TextInputType.number,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'ترتيب العرض (Sort Order)',
                            ),
                          ),
                        ],
                        SwitchListTile(
                          value: posting,
                          onChanged: account?.isSystem == true
                              ? null
                              : (v) => localSet(() => posting = v),
                          title: const Text('يسمح بالترحيل إليه'),
                        ),
                        if (account != null)
                          SwitchListTile(
                            value: active,
                            onChanged: account.isSystem
                                ? null
                                : (v) => localSet(() => active = v),
                            title: const Text('الحساب فعال'),
                          ),
                      ],
                    ),
                  ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        if (account != null && !account.isSystem) ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                Navigator.pop(pageContext, false);
                                await _remove(account);
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('حذف'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: NizamiColors.red,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(pageContext, false),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('إلغاء'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(pageContext, true),
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('حفظ الحساب'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (save != true || _branchId == null) return;
    try {
      if (account == null) {
        await _api.create(_branchId!, {
          'code': code.text.trim(),
          'name_ar': ar.text.trim(),
          'name_en': en.text.trim(),
          'type': type,
          'normal_balance': type == 'asset' || type == 'expense'
              ? 'debit'
              : 'credit',
          'classification': classification,
          'closing_statement': type == 'revenue' || type == 'expense'
              ? 'profit_loss'
              : 'balance_sheet',
          'is_cash_equivalent': isCashEquivalent,
          'parent_id': parentId,
          'allow_posting': posting,
        });
      } else {
        await _api.update(_branchId!, account.id, {
          'name_ar': ar.text.trim(),
          'name_en': en.text.trim(),
          'allow_posting': posting,
          'active': active,
          'parent_id': parentId,
          'sort_order': int.tryParse(sortCtrl.text.trim()) ?? account.sortOrder,
          if (!account.isSystem) 'classification': classification,
          if (!account.isSystem) 'is_cash_equivalent': isCashEquivalent,
          'expected_version': account.version,
        });
      }
      await _load();
    } catch (error) {
      _message(error);
    }
  }

  String _defaultClassification(String type) => switch (type) {
    'asset' => 'current_asset',
    'liability' => 'current_liability',
    'equity' => 'equity',
    'revenue' => 'revenue',
    _ => 'operating_expense',
  };

  List<String> _classificationOptions(String type) => switch (type) {
    'asset' => const ['current_asset', 'non_current_asset'],
    'liability' => const ['current_liability', 'non_current_liability'],
    'equity' => const ['equity'],
    'revenue' => const ['revenue'],
    _ => const ['cost_of_sales', 'operating_expense'],
  };

  String _classificationLabel(String value) =>
      const {
        'current_asset': 'أصل متداول',
        'non_current_asset': 'أصل غير متداول',
        'current_liability': 'التزام متداول',
        'non_current_liability': 'التزام غير متداول',
        'equity': 'حقوق ملكية',
        'revenue': 'إيراد',
        'cost_of_sales': 'تكلفة مبيعات',
        'operating_expense': 'مصروف تشغيلي',
      }[value] ??
      value;

  Future<void> _remove(ChartAccount account) async {
    try {
      await _api.delete(_branchId!, account.id);
      await _load();
    } catch (error) {
      _message(error);
    }
  }
}
