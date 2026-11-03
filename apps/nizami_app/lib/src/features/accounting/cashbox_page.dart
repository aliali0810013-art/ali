import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/ninesoft_financial_ui.dart';
import '../../theme/ninesoft_ui.dart';
import '../../theme/nizami_theme.dart';
import '../administration/administration_api.dart';
import '../modules/module_workspace_page.dart';
import '../sync/realtime_sync_coordinator.dart';
import 'accounting_api.dart';
import 'cashbox_summary.dart';
import 'chart_accounts_api.dart';
import 'account_transfer_page.dart';
import 'searchable_chart_account_field.dart';

class CashboxPage extends StatefulWidget {
  const CashboxPage({
    super.key,
    required this.token,
    required this.tenantName,
    required this.tenantId,
    required this.branchIds,
    required this.roleCode,
    required this.permissions,
    this.accountingApi,
    this.chartApi,
  });

  final String token;
  final String tenantName;
  final String tenantId;
  final List<String> branchIds;
  final String roleCode;
  final List<String> permissions;
  final AccountingApi? accountingApi;
  final ChartAccountsApi? chartApi;

  @override
  State<CashboxPage> createState() => _CashboxPageState();
}

class _CashboxPageState extends State<CashboxPage> {
  late final AccountingApi _api =
      widget.accountingApi ?? AccountingApi(token: widget.token);
  late final ChartAccountsApi _chart =
      widget.chartApi ?? ChartAccountsApi(widget.token);
  late final AdministrationApi _administration = AdministrationApi(
    token: widget.token,
  );
  StreamSubscription<Set<String>>? _syncSubscription;
  Timer? _reloadDebounce;
  String? _branchId;
  CashboxPeriod _period = CashboxPeriod.all;
  CashboxSummary _summary = const CashboxSummary(
    currentBalanceMinor: 0,
    openingBalanceMinor: 0,
    inflowMinor: 0,
    outflowMinor: 0,
    movements: [],
  );
  List<Map<String, dynamic>> _journals = const [];
  List<ChartAccount> _cashAccounts = const [];
  Map<String, String> _branchNames = const {};
  String _accountCode = '1100-CASH';
  bool _loading = true;
  final CashboxReloadQueue _reloadQueue = CashboxReloadQueue();
  String? _error;

  bool get _refreshing => _reloadQueue.isActive;

  bool get _owner => widget.roleCode == 'owner';
  bool get _canCreateReceipt =>
      _owner || widget.permissions.contains('receipts.create');
  bool get _canCreatePayment =>
      _owner || widget.permissions.contains('payments.create');

  @override
  void initState() {
    super.initState();
    _branchId = widget.branchIds.firstOrNull;
    _syncSubscription = RealtimeSyncCoordinator.instance.changes.listen((
      types,
    ) {
      if (types.intersection(const {
        'invoice',
        'journal_entry',
        'receipt',
        'supplier_payment',
        'debts.receipts',
        'debts.payments',
      }).isNotEmpty) {
        _reloadDebounce?.cancel();
        _reloadDebounce = Timer(
          const Duration(milliseconds: 350),
          () => unawaited(_load(silent: true)),
        );
      }
    });
    unawaited(_loadBranchNames());
    unawaited(_load());
  }

  Future<void> _loadBranchNames() async {
    try {
      final branches = await _administration.branches();
      if (!mounted) return;
      setState(() {
        _branchNames = {
          for (final branch in branches)
            if ((branch['id']?.toString() ?? '').isNotEmpty)
              branch['id'].toString():
                  branch['name']?.toString().trim().isNotEmpty == true
                  ? branch['name'].toString().trim()
                  : 'الفرع الرئيسي',
        };
      });
    } catch (_) {
      // A readable fallback is better than exposing a UUID to the user.
    }
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final branchId = _branchId;
    if (branchId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!_reloadQueue.start(silent: silent)) {
      return;
    }
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final values = await Future.wait([
        _api.listJournals(branchId: branchId),
        _chart.list(branchId),
      ]);
      final journals = values[0] as List<Map<String, dynamic>>;
      final cashAccounts = (values[1] as List<ChartAccount>)
          .where(
            (item) => item.active && item.allowPosting && item.isCashEquivalent,
          )
          .toList(growable: false);
      if (!mounted || branchId != _branchId) return;
      setState(() {
        _journals = journals;
        _cashAccounts = cashAccounts;
        if (!cashAccounts.any((item) => item.code == _accountCode)) {
          _accountCode = cashAccounts.firstOrNull?.code ?? '1100-CASH';
        }
        _summary = summarizeCashbox(
          journals,
          period: _period,
          accountCode: _accountCode,
        );
        _error = null;
      });
    } catch (error) {
      if (mounted && !silent && branchId == _branchId) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      final queued = _reloadQueue.complete();
      if (mounted) setState(() => _loading = false);
      if (mounted && queued != null) {
        unawaited(_load(silent: queued.silent));
      }
    }
  }

  void _changePeriod(CashboxPeriod value) {
    setState(() {
      _period = value;
      _summary = summarizeCashbox(
        _journals,
        period: value,
        accountCode: _accountCode,
      );
    });
  }

  void _openDocumentModule({required bool receipt}) {
    final module = ModuleDefinition(
      key: receipt ? 'debts.receipts' : 'debts.payments',
      title: receipt ? 'سندات القبض' : 'سندات الصرف',
      entityLabel: receipt ? 'سند قبض' : 'سند صرف',
      actionLabel: receipt ? 'سند قبض جديد' : 'سند صرف جديد',
      icon: receipt ? Icons.south_west_rounded : Icons.north_east_rounded,
      color: receipt ? NizamiColors.green : NizamiColors.red,
    );
    final branchIds = prioritizeCashboxBranch(widget.branchIds, _branchId);
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ModuleWorkspacePage(
            module: module,
            tenantName: widget.tenantName,
            tenantId: widget.tenantId,
            token: widget.token,
            branchIds: branchIds,
            roleCode: widget.roleCode,
            permissions: widget.permissions,
          ),
        ),
      ),
    );
  }

  String _money(int minor) => '${(minor / 100).toStringAsFixed(2)} YER';

  String _periodLabel(CashboxPeriod value) => switch (value) {
    CashboxPeriod.all => 'جميع الفترات',
    CashboxPeriod.today => 'اليوم',
    CashboxPeriod.thisMonth => 'هذا الشهر',
  };

  String _referenceLabel(String value) => switch (value) {
    'sale_invoice' => 'فاتورة بيع',
    'purchase_invoice' => 'فاتورة شراء',
    'receipt' => 'سند قبض',
    'supplier_payment' => 'سند صرف',
    'sale_return' || 'sale_return_direct' => 'مرتجع بيع',
    'purchase_return' || 'purchase_return_direct' => 'مرتجع شراء',
    'manual_journal' => 'قيد يدوي',
    'manual_journal_void' => 'قيد عكسي',
    _ => value.isEmpty ? 'حركة محاسبية' : value,
  };

  String _dateLabel(DateTime? value) {
    if (value == null) return 'دون تاريخ';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الصندوق'),
        toolbarHeight: desktop ? 0 : null,
        actions: [
          IconButton(
            tooltip: 'تحديث حركة الصندوق',
            onPressed: _refreshing ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: NineSoftResponsiveBody(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              children: [
                NineSoftEntryHeading(
                  title: 'الصندوق',
                  subtitle:
                      'الرصيد النقدي وحركات القبض والصرف من القيود المرحلة',
                  icon: Icons.point_of_sale_rounded,
                  accent: NizamiColors.green,
                  actions: [
                    OutlinedButton.icon(
                      key: const Key('cashbox-refresh-action'),
                      onPressed: _refreshing ? null : _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('تحديث'),
                    ),
                    if (_canCreateReceipt)
                      FilledButton.icon(
                        onPressed: () => _openDocumentModule(receipt: true),
                        icon: const Icon(Icons.south_west_rounded),
                        label: const Text('سند قبض'),
                      ),
                    if (_canCreatePayment)
                      FilledButton.tonalIcon(
                        onPressed: () => _openDocumentModule(receipt: false),
                        icon: const Icon(Icons.north_east_rounded),
                        label: const Text('سند صرف'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AccountTransferPage(
                            token: widget.token,
                            branchIds: prioritizeCashboxBranch(
                              widget.branchIds,
                              _branchId,
                            ),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.swap_horiz_rounded),
                      label: const Text('تحويل'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                NineSoftEntrySection(
                  title: 'نطاق الصندوق',
                  subtitle: 'حدد الفرع والفترة والحساب النقدي',
                  icon: Icons.tune_rounded,
                  child: NineSoftEntryFieldGrid(
                    maxColumns: 3,
                    children: [
                      if (widget.branchIds.length > 1)
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _branchId,
                          decoration: const InputDecoration(
                            labelText: 'الفرع',
                            prefixIcon: Icon(Icons.store_rounded),
                          ),
                          items: widget.branchIds
                              .map(
                                (id) => DropdownMenuItem(
                                  value: id,
                                  child: Text(
                                    _branchNames[id] ?? 'الفرع الرئيسي',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            setState(() => _branchId = value);
                            unawaited(_load());
                          },
                        ),
                      DropdownButtonFormField<CashboxPeriod>(
                        isExpanded: true,
                        initialValue: _period,
                        decoration: const InputDecoration(
                          labelText: 'الفترة',
                          prefixIcon: Icon(Icons.calendar_month_rounded),
                        ),
                        items: CashboxPeriod.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(
                                  _periodLabel(value),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) _changePeriod(value);
                        },
                      ),
                      SearchableChartAccountField(
                        accounts: _cashAccounts,
                        value:
                            _cashAccounts.any(
                              (item) => item.code == _accountCode,
                            )
                            ? _accountCode
                            : null,
                        label: 'الصندوق / البنك / المحفظة',
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _accountCode = value;
                            _summary = summarizeCashbox(
                              _journals,
                              period: _period,
                              accountCode: _accountCode,
                            );
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1050
                        ? 4
                        : constraints.maxWidth >= 580
                        ? 2
                        : 1;
                    final width =
                        (constraints.maxWidth - ((columns - 1) * 10)) / columns;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: width,
                          child: NineSoftMetricCard(
                            label: 'الرصيد الحالي',
                            value: _money(_summary.currentBalanceMinor),
                            caption: 'حسب جميع القيود المرحلة',
                            icon: Icons.account_balance_wallet_rounded,
                            color: NizamiColors.blue,
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: NineSoftMetricCard(
                            label: 'المقبوض خلال الفترة',
                            value: _money(_summary.inflowMinor),
                            caption: _periodLabel(_period),
                            icon: Icons.south_west_rounded,
                            color: NizamiColors.green,
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: NineSoftMetricCard(
                            label: 'المصروف خلال الفترة',
                            value: _money(_summary.outflowMinor),
                            caption: _periodLabel(_period),
                            icon: Icons.north_east_rounded,
                            color: NizamiColors.red,
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: NineSoftMetricCard(
                            label: 'صافي الحركة',
                            value: _money(_summary.periodNetMinor),
                            caption: _period == CashboxPeriod.all
                                ? 'من بداية السجل'
                                : 'افتتاحي ${_money(_summary.openingBalanceMinor)}',
                            icon: Icons.swap_vert_rounded,
                            color: NizamiColors.purple,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                NineSoftEntrySection(
                  key: const Key('cashbox-movements-section'),
                  title: 'حركة الصندوق',
                  subtitle: 'القبض والصرف كما رُحّلا في القيود المحاسبية',
                  icon: Icons.receipt_long_outlined,
                  padding: const EdgeInsets.all(12),
                  child: _body(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return NineSoftEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'تعذر جلب حركة الصندوق',
        message: _error!,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('إعادة المحاولة'),
        ),
      );
    }
    if (_summary.movements.isEmpty) {
      return const NineSoftEmptyState(
        icon: Icons.point_of_sale_outlined,
        title: 'لا توجد حركة صندوق في هذه الفترة',
        message:
            'تظهر هنا المبيعات النقدية وسندات القبض والمشتريات النقدية وسندات الصرف بعد ترحيلها.',
      );
    }
    if (MediaQuery.sizeOf(context).width >= 900) {
      return NineSoftResponsiveFinancialTable(
        key: const Key('cashbox-movements-table'),
        columns: const [
          NineSoftFinancialColumn(label: 'التاريخ', flex: 2),
          NineSoftFinancialColumn(label: 'المرجع', flex: 2),
          NineSoftFinancialColumn(label: 'البيان', flex: 3),
          NineSoftFinancialColumn(label: 'وارد', flex: 2),
          NineSoftFinancialColumn(label: 'صادر', flex: 2),
          NineSoftFinancialColumn(label: 'الرصيد', flex: 2),
        ],
        rows: [
          for (final movement in _summary.movements)
            NineSoftFinancialRow(
              key: Key('cashbox-movement-row-${movement.entryId}'),
              cells: [
                Text(_dateLabel(movement.postedAt)),
                Text(_referenceLabel(movement.referenceType)),
                Text(
                  movement.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  movement.debitMinor == 0 ? '—' : _money(movement.debitMinor),
                  textDirection: TextDirection.ltr,
                ),
                Text(
                  movement.creditMinor == 0
                      ? '—'
                      : _money(movement.creditMinor),
                  textDirection: TextDirection.ltr,
                ),
                Text(
                  _money(movement.balanceMinor),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
        ],
      );
    }
    return Column(
      children: [
        for (var index = 0; index < _summary.movements.length; index++) ...[
          _movementCard(_summary.movements[index]),
          if (index < _summary.movements.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _movementCard(CashboxMovement movement) {
    final incoming = movement.netMinor >= 0;
    final color = incoming ? NizamiColors.green : NizamiColors.red;
    return KeyedSubtree(
      key: ValueKey('cashbox-movement-card-${movement.entryId}'),
      child: NineSoftPanel(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: .12),
              foregroundColor: color,
              child: Icon(
                incoming ? Icons.south_west_rounded : Icons.north_east_rounded,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movement.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_referenceLabel(movement.referenceType)} • ${_dateLabel(movement.postedAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${incoming ? '+' : '-'}${_money(movement.netMinor.abs())}',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: color,
                    fontFamily: 'ArialMTBlack',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'الرصيد ${_money(movement.balanceMinor)}',
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
