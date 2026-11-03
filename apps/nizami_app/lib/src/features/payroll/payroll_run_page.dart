import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/nizami_theme.dart';
import '../accounting/chart_accounts_api.dart';
import '../sync/payroll_outbox.dart';
import '../sync/realtime_sync_coordinator.dart';
import 'payroll_api.dart';
import 'payroll_cache.dart';
import 'payroll_models.dart';
import 'payroll_ui_support.dart';

class PayrollRunPage extends StatefulWidget {
  const PayrollRunPage({
    super.key,
    required this.token,
    required this.tenantId,
    required this.tenantName,
    required this.branchIds,
    required this.roleCode,
    required this.permissions,
    this.initialEnvelope,
    this.outbox,
    this.api,
    this.restoreGeneration,
    this.initialPeriodMonth,
    this.syncChanges,
    this.accountOptions,
    this.previewLoader,
  });

  final String token;
  final String tenantId;
  final String tenantName;
  final List<String> branchIds;
  final String roleCode;
  final List<String> permissions;
  final PayrollEnvelope? initialEnvelope;
  final PayrollOutbox? outbox;
  final PayrollApi? api;
  final int? restoreGeneration;
  final String? initialPeriodMonth;
  final Stream<Set<String>>? syncChanges;
  final List<ChartAccount>? accountOptions;
  final Future<PayrollApprovalPreview> Function({
    required String branchId,
    required String periodMonth,
    required String selectionMode,
    required List<String> employeeIds,
    required int restoreGeneration,
  })?
  previewLoader;

  @override
  State<PayrollRunPage> createState() => _PayrollRunPageState();
}

class _PayrollRunPageState extends State<PayrollRunPage> {
  PayrollEnvelope _envelope = PayrollEnvelope.empty();
  List<PayrollOutboxEntry> _operations = const [];
  final Set<String> _selectedEmployees = {};
  final Set<String> _selectedPaymentItems = {};
  final Map<String, TextEditingController> _paymentAmounts = {};
  StreamSubscription<Set<String>>? _syncSubscription;
  late String _periodMonth;
  String _selectionMode = 'all';
  String? _selectedRunId;
  String? _paymentAccount;
  DateTime _paymentDate = DateTime.now();
  List<ChartAccount> _accountOptions = const [];
  PayrollApprovalPreview? _approvalPreview;
  int _previewEpoch = 0;
  bool _previewLoading = false;
  bool _loading = true;
  bool _approving = false;
  bool _paying = false;
  String? _error;

  String? get _branch => widget.branchIds.firstOrNull;
  PayrollCache? get _cache =>
      _branch == null ? null : PayrollCache(widget.tenantId, _branch!);
  PayrollOutbox? get _queue =>
      widget.outbox ??
      (_branch == null
          ? null
          : PayrollOutbox(widget.tenantId, _branch!, cache: _cache));
  PayrollApi get _api => widget.api ?? PayrollApi(token: widget.token);
  int get _restoreGeneration =>
      widget.restoreGeneration ??
      RealtimeSyncCoordinator.instance.restoreGeneration;
  bool get _canApprove => hasPayrollPermission(
    widget.roleCode,
    widget.permissions,
    'payroll.approve',
  );
  bool get _canPay =>
      hasPayrollPermission(widget.roleCode, widget.permissions, 'payroll.pay');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _periodMonth =
        widget.initialPeriodMonth ??
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    _envelope = widget.initialEnvelope ?? PayrollEnvelope.empty();
    _accountOptions = _usableAccounts(widget.accountOptions ?? const []);
    _paymentAccount = _accountOptions.firstOrNull?.code;
    _syncSubscription =
        (widget.syncChanges ?? RealtimeSyncCoordinator.instance.changes).listen(
          _onSyncChange,
        );
    unawaited(_load(refreshCache: widget.initialEnvelope == null));
    if (widget.accountOptions == null) unawaited(_loadAccounts());
  }

  @override
  void dispose() {
    for (final controller in _paymentAmounts.values) {
      controller.dispose();
    }
    _syncSubscription?.cancel();
    super.dispose();
  }

  List<ChartAccount> _usableAccounts(Iterable<ChartAccount> values) => values
      .where(
        (account) =>
            account.active && account.allowPosting && account.isCashEquivalent,
      )
      .toList(growable: false);

  Future<void> _loadAccounts() async {
    final branch = _branch;
    if (branch == null) return;
    try {
      final values = _usableAccounts(
        await _api.fetchPayrollSettlementAccounts(branch),
      );
      if (!mounted) return;
      setState(() {
        _accountOptions = values;
        if (!values.any((account) => account.code == _paymentAccount)) {
          _paymentAccount = values.firstOrNull?.code;
        }
      });
    } catch (_) {
      // The action stays disabled when no canonical settlement account exists.
    }
  }

  void _onSyncChange(Set<String> types) {
    if (types.intersection(const {
      'employee',
      'employee_advance',
      'payroll_run',
      'payroll_payment',
      'payroll_needs_review',
      'snapshot_restore',
    }).isNotEmpty) {
      if (types.intersection(const {
        'employee',
        'employee_advance',
        'snapshot_restore',
      }).isNotEmpty) {
        _invalidatePreview();
      }
      unawaited(_load(refreshCache: true));
      if (types.contains('snapshot_restore') && widget.accountOptions == null) {
        unawaited(_loadAccounts());
      }
    }
  }

  Future<void> _load({bool refreshCache = false}) async {
    final cache = _cache;
    final queue = _queue;
    if (cache == null || queue == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final values = await Future.wait<Object>([
        refreshCache ? cache.read() : Future.value(_envelope),
        queue.list(),
      ]);
      if (!mounted) return;
      setState(() {
        _envelope = values[0] as PayrollEnvelope;
        _operations = values[1] as List<PayrollOutboxEntry>;
        _normalizeSelectedRun();
        _error = null;
      });
      unawaited(_refreshPreview());
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر قراءة المسير المحلي: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Employee> get _activeEmployees => _envelope.employees
      .where((employee) => employee.active)
      .toList(growable: false);

  List<PayrollRun> get _periodRuns {
    final values = _envelope.payrollRuns
        .where(
          (run) =>
              run.toJson()['period_month'] == _periodMonth &&
              run.documentKind == 'payroll_run',
        )
        .toList(growable: false);
    values.sort((a, b) => _occurredAt(b).compareTo(_occurredAt(a)));
    return values;
  }

  DateTime _occurredAt(PayrollJsonModel value) =>
      DateTime.tryParse(value.toJson()['occurred_at']?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  void _normalizeSelectedRun() {
    final runs = _periodRuns;
    if (!runs.any((run) => run.id == _selectedRunId)) {
      _selectedRunId = runs.firstOrNull?.id;
      _selectedPaymentItems.clear();
    }
    if (_claimedEmployeeIds.isNotEmpty && _selectionMode == 'all') {
      _selectionMode = 'selected';
    }
  }

  PayrollRun? get _postedRun =>
      _periodRuns.where((run) => run.id == _selectedRunId).firstOrNull;

  Set<String> get _claimedEmployeeIds => _envelope.payrollPeriodClaims
      .where((claim) => claim.toJson()['period_month'] == _periodMonth)
      .map((claim) => claim.employeeId)
      .toSet();

  List<Employee> get _approvalCandidates => _activeEmployees
      .where((employee) => !_claimedEmployeeIds.contains(employee.id))
      .toList(growable: false);

  List<PayrollRunItem> get _runItems {
    final run = _postedRun;
    if (run == null) return const [];
    return _envelope.payrollRunItems
        .where((item) => item.payrollRunId == run.id)
        .toList(growable: false);
  }

  bool get _periodIsValid {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(_periodMonth)) return false;
    final parts = _periodMonth.split('-').map(int.parse).toList();
    if (parts[1] < 1 || parts[1] > 12) return false;
    final now = DateTime.now();
    return parts[0] < now.year ||
        (parts[0] == now.year && parts[1] <= now.month);
  }

  bool get _approvalLocked => _operations.any(
    (entry) =>
        entry.kind == PayrollOperationKind.payrollRunApproval &&
        entry.request['period_month'] == _periodMonth,
  );

  List<Employee> get _approvalSelection => _selectionMode == 'all'
      ? _approvalCandidates
      : _approvalCandidates
            .where((employee) => _selectedEmployees.contains(employee.id))
            .toList(growable: false);

  PayrollApprovalPreviewItem? _preview(Employee employee) => _approvalPreview
      ?.items
      .where((item) => item.employeeId == employee.id)
      .firstOrNull;

  bool get _hasCanonicalPreview {
    final preview = _approvalPreview;
    if (preview == null || _previewLoading || _approvalSelection.isEmpty) {
      return false;
    }
    final expected = _approvalSelection.map((employee) => employee.id).toSet();
    return preview.version == 1 &&
        preview.restoreGeneration == _restoreGeneration &&
        preview.branchId == _branch &&
        preview.periodMonth == _periodMonth &&
        preview.selectionMode == _selectionMode &&
        preview.items
            .map((item) => item.employeeId)
            .toSet()
            .containsAll(expected) &&
        expected.containsAll(preview.items.map((item) => item.employeeId));
  }

  void _invalidatePreview() {
    _previewEpoch++;
    if (mounted) {
      setState(() {
        _approvalPreview = null;
        _previewLoading = false;
      });
    }
  }

  Future<void> _refreshPreview() async {
    final branch = _branch;
    final selection = _approvalSelection;
    if (branch == null ||
        !_canApprove ||
        !_periodIsValid ||
        selection.isEmpty ||
        (_selectionMode == 'all' && _claimedEmployeeIds.isNotEmpty)) {
      _invalidatePreview();
      return;
    }
    final epoch = ++_previewEpoch;
    if (mounted) {
      setState(() {
        _approvalPreview = null;
        _previewLoading = true;
      });
    }
    try {
      final ids = _selectionMode == 'selected'
          ? (selection.map((employee) => employee.id).toList()..sort())
          : <String>[];
      final loader = widget.previewLoader;
      final preview = loader == null
          ? await _api.fetchPayrollPreview(
              branchId: branch,
              periodMonth: _periodMonth,
              selectionMode: _selectionMode,
              employeeIds: ids,
              restoreGeneration: _restoreGeneration,
            )
          : await loader(
              branchId: branch,
              periodMonth: _periodMonth,
              selectionMode: _selectionMode,
              employeeIds: ids,
              restoreGeneration: _restoreGeneration,
            );
      if (!mounted || epoch != _previewEpoch) return;
      setState(() {
        _approvalPreview = preview;
        _previewLoading = false;
      });
    } catch (error) {
      if (!mounted || epoch != _previewEpoch) return;
      setState(() {
        _approvalPreview = null;
        _previewLoading = false;
        _error = 'تعذر تحديث معاينة المسير: $error';
      });
    }
  }

  bool get _canSubmitApproval =>
      _canApprove &&
      !_approving &&
      !_approvalLocked &&
      _periodIsValid &&
      _approvalCandidates.isNotEmpty &&
      (_selectionMode == 'selected' || _claimedEmployeeIds.isEmpty) &&
      (_selectionMode == 'all' || _selectedEmployees.isNotEmpty) &&
      _hasCanonicalPreview;

  Future<void> _approve() async {
    if (!_canSubmitApproval || _branch == null || _queue == null) return;
    setState(() => _approving = true);
    try {
      final request = await _api.preparePayrollRun(
        branchId: _branch!,
        periodMonth: _periodMonth,
        selectionMode: _selectionMode,
        employeeIds: _selectionMode == 'selected'
            ? _selectedEmployees
            : const <String>[],
        restoreGeneration: _restoreGeneration,
        previewVersion: _approvalPreview!.version,
        previewSignature: _approvalPreview!.signature,
      );
      await _queue!.enqueue(
        kind: PayrollOperationKind.payrollRunApproval,
        aggregateId: const Uuid().v4(),
        request: request,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'تعذر حفظ طلب اعتماد المسير: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _approving = false);
      }
    }
  }

  TextEditingController _amountController(PayrollRunItem item) =>
      _paymentAmounts.putIfAbsent(item.id, () {
        final controller = TextEditingController();
        controller.addListener(() {
          if (mounted) setState(() {});
        });
        return controller;
      });

  int? _paymentAmount(PayrollRunItem item) =>
      int.tryParse(_amountController(item).text.trim());

  bool _validPaymentItem(PayrollRunItem item) {
    final amount = _paymentAmount(item);
    final remaining = item.remainingMinor ?? 0;
    return amount != null && amount > 0 && amount <= remaining;
  }

  bool get _canSubmitPayment {
    final items = _runItems
        .where((item) => _selectedPaymentItems.contains(item.id))
        .toList(growable: false);
    return _canPay &&
        !_paying &&
        _paymentAccount != null &&
        _postedRun?.status == 'approved' &&
        items.isNotEmpty &&
        items.every((item) => !_blockedPaymentItemIds.contains(item.id)) &&
        items.every(_validPaymentItem);
  }

  Set<String> get _blockedPaymentItemIds => _operations
      .where((entry) => entry.kind == PayrollOperationKind.payrollPaymentPost)
      .expand((entry) => (entry.request['items'] as List? ?? const []))
      .whereType<Map>()
      .map((item) => item['payroll_run_item_id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toSet();

  Future<void> _pay() async {
    final run = _postedRun;
    if (!_canSubmitPayment || run == null || _queue == null) return;
    setState(() => _paying = true);
    try {
      final items = _runItems
          .where((item) => _selectedPaymentItems.contains(item.id))
          .map(
            (item) => <String, Object?>{
              'payroll_run_item_id': item.id,
              'amount_minor': _paymentAmount(item)!,
            },
          );
      final request = await _api.preparePayrollPayment(
        occurredAt: _paymentDate,
        accountCode: _paymentAccount!,
        items: items,
        restoreGeneration: _restoreGeneration,
      );
      await _queue!.enqueue(
        kind: PayrollOperationKind.payrollPaymentPost,
        aggregateId: run.id,
        request: request,
      );
      _selectedPaymentItems.clear();
      for (final controller in _paymentAmounts.values) {
        controller.clear();
      }
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر حفظ طلب دفعة الراتب: $error');
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  String _dateLabel(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _pickPaymentDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (value != null && mounted) setState(() => _paymentDate = value);
  }

  @override
  Widget build(BuildContext context) {
    final posted = _postedRun;
    return PayrollPageBody(
      child: Column(
        key: const Key('payroll-run-page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NineSoftEntryHeading(
            title: 'المسير الشهري',
            subtitle:
                'اعتماد كل الموظفين النشطين أو مجموعة محددة، ثم صرف المستحق كليًا أو جزئيًا',
            icon: Icons.payments_rounded,
            status: '${widget.tenantName} • ${_branch ?? 'لا يوجد فرع'}',
            actions: [
              SizedBox(
                width: 170,
                child: TextFormField(
                  initialValue: _periodMonth,
                  enabled: !_approvalLocked,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'شهر المسير YYYY-MM',
                    filled: true,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _periodMonth = value.trim();
                      _selectedEmployees.clear();
                      _normalizeSelectedRun();
                      _approvalPreview = null;
                    });
                    unawaited(_refreshPreview());
                  },
                ),
              ),
              if (posted != null)
                PayrollStatusChip(
                  status: posted.status,
                  operationId: posted.localOperationId,
                ),
            ],
          ),
          const SizedBox(height: 16),
          for (final entry in _operations) PayrollOperationBanner(entry: entry),
          if (_error != null) ...[
            NineSoftEntryHint(
              text: _error!,
              icon: Icons.error_outline_rounded,
              accent: Colors.red,
            ),
            const SizedBox(height: 12),
          ],
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            NineSoftDocumentEditorScaffold(
              main: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSelection(posted),
                  if (_periodRuns.length > 1) ...[
                    _buildRunPicker(),
                    const SizedBox(height: 16),
                  ],
                  if (posted != null && _runItems.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildPayment(),
                  ],
                ],
              ),
              summary: _buildSummary(posted),
            ),
        ],
      ),
    );
  }

  Widget _buildRunPicker() => NineSoftEntrySection(
    title: 'مسيرات الشهر',
    subtitle: 'اختر المسير القانوني المراد فحصه أو صرف بنوده',
    icon: Icons.library_books_outlined,
    child: DropdownButtonFormField<String>(
      key: const Key('payroll-run-picker'),
      initialValue: _selectedRunId,
      decoration: const InputDecoration(labelText: 'المسير المعتمد'),
      items: [
        for (final run in _periodRuns)
          DropdownMenuItem(
            value: run.id,
            child: Text('${run.id} • ${run.status}'),
          ),
      ],
      onChanged: (value) => setState(() {
        _selectedRunId = value;
        _selectedPaymentItems.clear();
      }),
    ),
  );

  Widget _buildSelection(PayrollRun? posted) => NineSoftEntrySection(
    title: _approvalCandidates.isNotEmpty
        ? 'اختيار موظفي الاعتماد التالي'
        : 'بنود المسير المعتمد',
    subtitle: _approvalCandidates.isNotEmpty
        ? 'تظهر فقط الأسماء غير المطالب بها في هذه الفترة، والمعاينة قيم مؤكدة من الخادم'
        : 'الاسم والراتب والتخصيص لقطات تاريخية غير قابلة للتعديل',
    icon: Icons.fact_check_outlined,
    child: Column(
      key: const Key('payroll-run-selection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_approvalCandidates.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const Key('payroll-mode-all'),
                label: const Text('كل الموظفين النشطين'),
                selected: _selectionMode == 'all',
                onSelected: _claimedEmployeeIds.isEmpty
                    ? (_) {
                        setState(() => _selectionMode = 'all');
                        unawaited(_refreshPreview());
                      }
                    : null,
              ),
              ChoiceChip(
                key: const Key('payroll-mode-selected'),
                label: Text('محدد (${_selectedEmployees.length})'),
                selected: _selectionMode == 'selected',
                onSelected: (_) {
                  setState(() => _selectionMode = 'selected');
                  unawaited(_refreshPreview());
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (_approvalCandidates.isNotEmpty)
          for (final employee in _approvalCandidates)
            _PayrollCandidateCard(
              key: Key('payroll-run-item-${employee.id}'),
              employee: employee,
              selected:
                  _selectionMode == 'all' ||
                  _selectedEmployees.contains(employee.id),
              selectionEnabled: _selectionMode == 'selected',
              onSelected: (value) {
                setState(() {
                  if (value) {
                    _selectedEmployees.add(employee.id);
                  } else {
                    _selectedEmployees.remove(employee.id);
                  }
                });
                unawaited(_refreshPreview());
              },
              preview: _preview(employee),
            ),
        if (posted != null) ...[
          if (_approvalCandidates.isNotEmpty) ...[
            const Divider(height: 28),
            const Text(
              'بنود المسير المحدد',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
          ],
          for (final item in _runItems)
            _PostedRunItemCard(
              key: Key('payroll-run-item-${item.id}'),
              item: item,
            ),
        ],
      ],
    ),
  );

  Widget _buildSummary(PayrollRun? posted) {
    final json = posted?.toJson();
    final previewReady = _hasCanonicalPreview;
    final previewGross = _approvalPreview?.grossMinor ?? 0;
    final previewApplied = _approvalPreview?.appliedMinor ?? 0;
    final previewNet = _approvalPreview?.netMinor ?? 0;
    final approvalOpen = _approvalCandidates.isNotEmpty;
    final rows = <NineSoftEntrySummaryRow>[
      NineSoftEntrySummaryRow(
        id: 'period',
        label: 'الفترة',
        value: _periodMonth,
      ),
      NineSoftEntrySummaryRow(
        id: 'gross',
        label: 'إجمالي الرواتب',
        value: approvalOpen
            ? (previewReady
                  ? formatPayrollMinor(previewGross)
                  : 'المعاينة غير متاحة')
            : formatPayrollMinor(json?['total_gross_minor'] as int? ?? 0),
      ),
      NineSoftEntrySummaryRow(
        id: 'advance',
        label: 'السلف المخصصة',
        value: approvalOpen
            ? (previewReady
                  ? formatPayrollMinor(previewApplied)
                  : 'المعاينة غير متاحة')
            : formatPayrollMinor(json?['total_applied_minor'] as int? ?? 0),
      ),
      NineSoftEntrySummaryRow(
        id: 'net',
        label: 'صافي المستحق',
        value: approvalOpen
            ? (previewReady
                  ? formatPayrollMinor(previewNet)
                  : 'المعاينة غير متاحة')
            : formatPayrollMinor(json?['total_net_minor'] as int? ?? 0),
        emphasized: true,
      ),
      NineSoftEntrySummaryRow(
        id: 'count',
        label: 'عدد الموظفين',
        value: approvalOpen
            ? (_selectionMode == 'all'
                  ? '${_approvalCandidates.length}'
                  : '${_selectedEmployees.length}')
            : '${_runItems.length}',
      ),
    ];
    return NineSoftEntrySummary(
      rows: rows,
      primaryKey: const Key('payroll-approve'),
      primaryLabel: approvalOpen ? 'اعتماد المسير' : 'المسير مرحّل',
      onPrimary: approvalOpen && _canApprove && _canSubmitApproval
          ? _approve
          : null,
      busy: _approving,
      helpText: approvalOpen
          ? 'معاينة مؤكدة من الخادم ومحفوظة في اللقطة؛ يظل الإقرار القانوني النهائي هو المرجع المحاسبي.'
          : 'هذا المسير تاريخي وللقراءة فقط. التصحيح يتطلب عكسًا مدققًا مستقلًا.',
    );
  }

  Widget _buildPayment() => NineSoftEntrySection(
    title: 'صرف الرواتب',
    subtitle:
        'اختر البنود ذات الرصيد المتبقي وأدخل مبلغًا صحيحًا لا يتجاوز المتبقي',
    icon: Icons.account_balance_wallet_outlined,
    child: Column(
      key: const Key('payroll-payment-selection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in _runItems.where(
          (row) => (row.remainingMinor ?? 0) > 0,
        ))
          _PaymentItemRow(
            item: item,
            selected: _selectedPaymentItems.contains(item.id),
            canEdit: _canPay && !_blockedPaymentItemIds.contains(item.id),
            controller: _amountController(item),
            valid:
                !_selectedPaymentItems.contains(item.id) ||
                _validPaymentItem(item),
            onSelected: (value) => setState(() {
              if (value) {
                _selectedPaymentItems.add(item.id);
              } else {
                _selectedPaymentItems.remove(item.id);
              }
            }),
          ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: const Key('payroll-payment-account'),
          isExpanded: true,
          initialValue: _paymentAccount,
          decoration: const InputDecoration(labelText: 'حساب الصرف'),
          items: [
            for (final account in _accountOptions)
              DropdownMenuItem(
                value: account.code,
                child: Text(
                  '${account.nameAr} • ${account.code}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _canPay
              ? (value) => setState(() => _paymentAccount = value!)
              : null,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('payroll-payment-date'),
          onPressed: _canPay ? _pickPaymentDate : null,
          icon: const Icon(Icons.event_outlined),
          label: Text('تاريخ الصرف ${_dateLabel(_paymentDate)}'),
        ),
        if (_canPay) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('payroll-pay'),
            onPressed: _canSubmitPayment ? _pay : null,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(_paying ? 'جارٍ الحفظ…' : 'تسجيل الدفعة'),
          ),
        ],
      ],
    ),
  );
}

class _PayrollCandidateCard extends StatelessWidget {
  const _PayrollCandidateCard({
    super.key,
    required this.employee,
    required this.selected,
    required this.selectionEnabled,
    required this.onSelected,
    required this.preview,
  });
  final Employee employee;
  final bool selected;
  final bool selectionEnabled;
  final ValueChanged<bool> onSelected;
  final PayrollApprovalPreviewItem? preview;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: selected ? NizamiColors.blueSoft : null,
      border: Border.all(color: NizamiColors.border),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      children: [
        Checkbox(
          key: Key('payroll-select-${employee.id}'),
          value: selected,
          onChanged: selectionEnabled ? (value) => onSelected(value!) : null,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview?.employeeName ?? employee.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                preview == null
                    ? 'الراتب المسجل ${formatPayrollMinor(employee.baseSalaryMinor)}'
                    : 'الراتب المؤكد ${formatPayrollMinor(preview!.grossMinor)}',
              ),
              if (preview != null) ...[
                const Text('معاينة مؤكدة من الخادم'),
                Text(
                  'السلف المطبقة ${formatPayrollMinor(preview!.appliedMinor)}',
                ),
                Text('الصافي ${formatPayrollMinor(preview!.netMinor)}'),
              ] else
                const Text('المعاينة المؤكدة غير متاحة'),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PostedRunItemCard extends StatelessWidget {
  const _PostedRunItemCard({super.key, required this.item});
  final PayrollRunItem item;

  @override
  Widget build(BuildContext context) {
    final json = item.toJson();
    final name = json['employee_name_snapshot']?.toString() ?? item.employeeId;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: NizamiColors.border),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              Text(
                'الإجمالي ${formatPayrollMinor(json['gross_minor'] as int)}',
              ),
              Text(
                'السلف ${formatPayrollMinor(json['applied_advance_minor'] as int)}',
              ),
              Text('الصافي ${formatPayrollMinor(item.netMinor)}'),
              Text(
                'المتبقي ${formatPayrollMinor(item.remainingMinor ?? item.netMinor)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentItemRow extends StatelessWidget {
  const _PaymentItemRow({
    required this.item,
    required this.selected,
    required this.canEdit,
    required this.controller,
    required this.valid,
    required this.onSelected,
  });
  final PayrollRunItem item;
  final bool selected;
  final bool canEdit;
  final TextEditingController controller;
  final bool valid;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      border: Border.all(color: valid ? NizamiColors.border : Colors.red),
      borderRadius: BorderRadius.circular(12),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final identity = Row(
          children: [
            Checkbox(
              key: Key('payroll-pay-select-${item.id}'),
              value: selected,
              onChanged: canEdit ? (value) => onSelected(value!) : null,
            ),
            Expanded(
              child: Text(
                '${item.toJson()['employee_name_snapshot'] ?? item.employeeId}\n'
                'المتبقي ${formatPayrollMinor(item.remainingMinor ?? 0)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
        final amount = TextField(
          key: Key('payroll-pay-amount-${item.id}'),
          controller: controller,
          enabled: canEdit && selected,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'المبلغ الصحيح',
            errorText: selected && !valid
                ? 'أكبر من صفر ولا يتجاوز المتبقي'
                : null,
          ),
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [identity, const SizedBox(height: 8), amount],
          );
        }
        return Row(
          children: [
            Expanded(child: identity),
            const SizedBox(width: 12),
            SizedBox(width: 230, child: amount),
          ],
        );
      },
    ),
  );
}
