import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/ninesoft_confirm_shortcuts.dart';
import '../../theme/nizami_theme.dart';
import '../accounting/chart_accounts_api.dart';
import '../sync/payroll_outbox.dart';
import '../sync/realtime_sync_coordinator.dart';
import 'employee_ledger_page.dart';
import 'payroll_api.dart';
import 'payroll_cache.dart';
import 'payroll_models.dart';
import 'payroll_run_page.dart';
import 'payroll_ui_support.dart';

class EmployeePayrollPage extends StatefulWidget {
  const EmployeePayrollPage({
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
    this.syncChanges,
    this.accountOptions,
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
  final Stream<Set<String>>? syncChanges;
  final List<ChartAccount>? accountOptions;

  @override
  State<EmployeePayrollPage> createState() => _EmployeePayrollPageState();
}

class _EmployeePayrollPageState extends State<EmployeePayrollPage> {
  final _search = TextEditingController();
  PayrollEnvelope _envelope = PayrollEnvelope.empty();
  List<PayrollOutboxEntry> _operations = const [];
  StreamSubscription<Set<String>>? _syncSubscription;
  List<ChartAccount> _accountOptions = const [];
  String _filter = 'all';
  bool _loading = true;
  bool _mutating = false;
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

  bool get _canManage => hasPayrollPermission(
    widget.roleCode,
    widget.permissions,
    'payroll.manage',
  );
  bool get _canAdvance => hasPayrollPermission(
    widget.roleCode,
    widget.permissions,
    'payroll.advance',
  );

  @override
  void initState() {
    super.initState();
    _envelope = widget.initialEnvelope ?? PayrollEnvelope.empty();
    _accountOptions = _usableAccounts(widget.accountOptions ?? const []);
    _search.addListener(_refreshSearch);
    _syncSubscription =
        (widget.syncChanges ?? RealtimeSyncCoordinator.instance.changes).listen(
          _onSyncChange,
        );
    unawaited(_load(refreshCache: widget.initialEnvelope == null));
    if (widget.accountOptions == null) unawaited(_loadAccounts());
  }

  @override
  void dispose() {
    _search
      ..removeListener(_refreshSearch)
      ..dispose();
    _syncSubscription?.cancel();
    super.dispose();
  }

  void _refreshSearch() => setState(() {});

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
      if (mounted) setState(() => _accountOptions = values);
    } catch (_) {
      // Financial actions remain disabled without canonical account options.
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
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'تعذر قراءة بيانات الرواتب المحلية: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Employee> get _employees {
    final query = _search.text.trim().toLowerCase();
    return _envelope.employees
        .where((employee) {
          if (_filter == 'active' && !employee.active) return false;
          if (_filter == 'inactive' && employee.active) return false;
          if (query.isEmpty) return true;
          return employee.name.toLowerCase().contains(query) ||
              (employee.phone ?? '').toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _openLedger(Employee employee) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            EmployeeLedgerPage(employee: employee, envelope: _envelope),
      ),
    );
  }

  Future<void> _openAdvance(Employee employee) async {
    if (!_canAdvance || _mutating || _branch == null || _queue == null) return;
    final intent = await _readAdvanceIntent(employee);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _AdvanceSheet(
        employee: employee,
        accounts: _accountOptions,
        intent: intent,
        onNewIntent: () => _clearAdvanceIntent(employee),
        onRetry: intent == null
            ? null
            : () async {
                await _queue!.enqueue(
                  kind: PayrollOperationKind.advancePost,
                  aggregateId: intent.operationId,
                  request: intent.request,
                );
                await _load();
              },
        onSubmit: (amount, category, note, account, occurredAt) async {
          if (_mutating) return;
          setState(() => _mutating = true);
          try {
            final request = await _api.prepareAdvance(
              employeeId: employee.id,
              branchId: _branch!,
              amountMinor: amount,
              category: category,
              note: note,
              accountCode: account,
              occurredAt: occurredAt,
              restoreGeneration: _restoreGeneration,
            );
            await _writeAdvanceIntent(employee, request);
            await _queue!.enqueue(
              kind: PayrollOperationKind.advancePost,
              aggregateId: request['local_operation_id'] as String,
              request: request,
            );
            if (context.mounted) Navigator.pop(context);
            await _load();
          } finally {
            if (mounted) setState(() => _mutating = false);
          }
        },
      ),
    );
  }

  String _advanceIntentKey(Employee employee) =>
      'ninesoft.payroll.advance-intent.v1.${widget.tenantId}.${_branch!}.${employee.id}';

  Future<void> _writeAdvanceIntent(
    Employee employee,
    Map<String, dynamic> request,
  ) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      _advanceIntentKey(employee),
      jsonEncode(request),
    );
    if (!saved) throw StateError('Unable to persist advance intent');
  }

  Future<void> _clearAdvanceIntent(Employee employee) async {
    await (await SharedPreferences.getInstance()).remove(
      _advanceIntentKey(employee),
    );
  }

  Future<_AdvanceIntent?> _readAdvanceIntent(Employee employee) async {
    Map<String, dynamic>? request;
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_advanceIntentKey(employee));
    if (raw != null) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) request = Map<String, dynamic>.from(decoded);
    }
    PayrollOutboxEntry? queued;
    final matching =
        _operations
            .where(
              (entry) =>
                  entry.kind == PayrollOperationKind.advancePost &&
                  entry.request['employee_id'] == employee.id,
            )
            .toList(growable: false)
          ..sort(
            (a, b) => b.operationCreatedAt.compareTo(a.operationCreatedAt),
          );
    if (request == null && matching.isNotEmpty) {
      queued = matching.first;
      request = queued.request;
    }
    final posted =
        _envelope.employeeAdvances
            .where(
              (advance) =>
                  advance.employeeId == employee.id &&
                  advance.documentKind == 'employee_advance',
            )
            .toList(growable: false)
          ..sort((a, b) {
            final left =
                DateTime.tryParse(
                  a.toJson()['operation_created_at']?.toString() ?? '',
                ) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final right =
                DateTime.tryParse(
                  b.toJson()['operation_created_at']?.toString() ?? '',
                ) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return right.compareTo(left);
          });
    if (request == null && posted.isNotEmpty) request = posted.first.toJson();
    if (request == null ||
        request['employee_id'] != employee.id ||
        request['local_operation_id'] is! String) {
      return null;
    }
    final operationId = request['local_operation_id'] as String;
    queued = _operations
        .where((entry) => entry.operationId == operationId)
        .firstOrNull;
    final canonical = posted
        .where((advance) => advance.localOperationId == operationId)
        .firstOrNull;
    final state = queued != null
        ? (queued.state == PayrollOutboxState.needsReview
              ? 'needs_review: ${queued.rejectionMessage ?? ''}'
              : 'queued')
        : canonical != null
        ? canonical.status
        : 'prepared';
    if (raw == null) await _writeAdvanceIntent(employee, request);
    return _AdvanceIntent(request: request, state: state);
  }

  Future<void> _addEmployee() async {
    if (!_canManage || _mutating || _branch == null || _queue == null) return;
    final value = await showModalBottomSheet<_NewEmployeeValue>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _EmployeeCreateSheet(),
    );
    if (value == null || _mutating) return;
    setState(() => _mutating = true);
    try {
      final employeeId = const Uuid().v4();
      final request = await _api.prepareEmployeeCreate(
        id: employeeId,
        branchId: _branch!,
        name: value.name,
        phone: value.phone,
        baseSalaryMinor: value.salaryMinor,
        startDate: value.startDate,
        notes: value.notes,
        restoreGeneration: _restoreGeneration,
      );
      await _queue!.enqueue(
        kind: PayrollOperationKind.employeeCreate,
        aggregateId: employeeId,
        request: request,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _editEmployee(Employee employee) async {
    if (!_canManage || _mutating || _branch == null || _queue == null) return;
    final value = await showModalBottomSheet<_NewEmployeeValue>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EmployeeCreateSheet(initial: employee),
    );
    if (value == null || _mutating) return;
    setState(() => _mutating = true);
    try {
      final request = await _api.prepareEmployeeUpdate(
        id: employee.id,
        branchId: _branch!,
        name: value.name,
        phone: value.phone,
        baseSalaryMinor: value.salaryMinor,
        startDate: value.startDate,
        notes: value.notes,
        expectedVersion: employee.version,
        restoreGeneration: _restoreGeneration,
      );
      await _queue!.enqueue(
        kind: PayrollOperationKind.employeeUpdate,
        aggregateId: employee.id,
        request: request,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _deactivateEmployee(Employee employee) async {
    if (!_canManage || _mutating || !employee.active || _queue == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => NineSoftEnterConfirmScope(
        onConfirm: () => Navigator.pop(context, true),
        child: AlertDialog(
          title: const Text('تعطيل الموظف؟'),
          content: Text(
            'سيبقى كشف ${employee.name} ومستحقاته التاريخية مقروءة، ولن يدخل في مسير «الكل» الجديد.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: const Key('payroll-deactivate-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ طلب التعطيل'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || _mutating) return;
    setState(() => _mutating = true);
    try {
      final request = await _api.prepareEmployeeDeactivate(
        id: employee.id,
        branchId: employee.branchId,
        expectedVersion: employee.version,
        restoreGeneration: _restoreGeneration,
      );
      await _queue!.enqueue(
        kind: PayrollOperationKind.employeeDeactivate,
        aggregateId: employee.id,
        request: request,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width > 700;
    final branch = _branch ?? 'لا يوجد فرع متاح';
    return PayrollPageBody(
      child: Column(
        key: const Key('payroll-module'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NineSoftEntryHeading(
            title: 'الموظفون والرواتب',
            subtitle: 'ملفات الموظفين، كشوف الذمم، السلف، والمسير الشهري',
            icon: Icons.groups_rounded,
            status: '${widget.tenantName} • الفرع $branch',
            actions: [
              FilledButton.icon(
                key: const Key('payroll-open-run'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => PayrollRunPage(
                      token: widget.token,
                      tenantId: widget.tenantId,
                      tenantName: widget.tenantName,
                      branchIds: widget.branchIds,
                      roleCode: widget.roleCode,
                      permissions: widget.permissions,
                      initialEnvelope: _envelope,
                      outbox: widget.outbox,
                      api: widget.api,
                      restoreGeneration: widget.restoreGeneration,
                      syncChanges: widget.syncChanges,
                      accountOptions: widget.accountOptions == null
                          ? null
                          : _accountOptions,
                    ),
                  ),
                ),
                icon: const Icon(Icons.calendar_month_rounded),
                label: const Text('المسير الشهري'),
              ),
              if (_canManage)
                OutlinedButton.icon(
                  key: const Key('payroll-add-employee'),
                  onPressed: _mutating ? null : _addEmployee,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('إضافة موظف'),
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
          NineSoftEntrySection(
            title: 'دليل الموظفين',
            subtitle: 'السجل التاريخي يبقى مقروءًا حتى بعد تعطيل الموظف',
            icon: Icons.badge_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: desktop ? 380 : double.infinity,
                      child: TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded),
                          labelText: 'بحث بالاسم أو الهاتف',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: desktop ? 190 : double.infinity,
                      child: DropdownButtonFormField<String>(
                        initialValue: _filter,
                        decoration: const InputDecoration(labelText: 'الحالة'),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('الكل')),
                          DropdownMenuItem(value: 'active', child: Text('نشط')),
                          DropdownMenuItem(
                            value: 'inactive',
                            child: Text('غير نشط'),
                          ),
                        ],
                        onChanged: (value) => setState(() => _filter = value!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_employees.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text('لا توجد سجلات مطابقة')),
                  )
                else if (desktop)
                  _EmployeeTable(
                    employees: _employees,
                    canAdvance: _canAdvance,
                    canManage: _canManage,
                    onLedger: _openLedger,
                    onAdvance: _openAdvance,
                    onEdit: _editEmployee,
                    onDeactivate: _deactivateEmployee,
                  )
                else
                  Column(
                    children: [
                      for (final employee in _employees)
                        _EmployeeCard(
                          employee: employee,
                          canAdvance: _canAdvance,
                          canManage: _canManage,
                          onLedger: _openLedger,
                          onAdvance: _openAdvance,
                          onEdit: _editEmployee,
                          onDeactivate: _deactivateEmployee,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeTable extends StatelessWidget {
  const _EmployeeTable({
    required this.employees,
    required this.canAdvance,
    required this.canManage,
    required this.onLedger,
    required this.onAdvance,
    required this.onEdit,
    required this.onDeactivate,
  });

  final List<Employee> employees;
  final bool canAdvance;
  final bool canManage;
  final ValueChanged<Employee> onLedger;
  final ValueChanged<Employee> onAdvance;
  final ValueChanged<Employee> onEdit;
  final ValueChanged<Employee> onDeactivate;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('payroll-employee-table'),
    decoration: BoxDecoration(
      border: Border.all(color: NizamiColors.border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        const _EmployeeTableLine(header: true),
        for (final employee in employees)
          _EmployeeTableLine(
            employee: employee,
            canAdvance: canAdvance,
            canManage: canManage,
            onLedger: onLedger,
            onAdvance: onAdvance,
            onEdit: onEdit,
            onDeactivate: onDeactivate,
          ),
      ],
    ),
  );
}

class _EmployeeTableLine extends StatelessWidget {
  const _EmployeeTableLine({
    this.employee,
    this.header = false,
    this.canAdvance = false,
    this.canManage = false,
    this.onLedger,
    this.onAdvance,
    this.onEdit,
    this.onDeactivate,
  });

  final Employee? employee;
  final bool header;
  final bool canAdvance;
  final bool canManage;
  final ValueChanged<Employee>? onLedger;
  final ValueChanged<Employee>? onAdvance;
  final ValueChanged<Employee>? onEdit;
  final ValueChanged<Employee>? onDeactivate;

  @override
  Widget build(BuildContext context) {
    final json = employee?.toJson();
    Text cell(String value, {FontWeight? weight}) => Text(
      value,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontWeight: weight),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: NizamiColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: header
                ? cell('الموظف', weight: FontWeight.w800)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      cell(employee!.name, weight: FontWeight.w700),
                      cell(employee!.phone ?? 'لا يوجد هاتف'),
                    ],
                  ),
          ),
          Expanded(
            child: header
                ? cell('الحالة', weight: FontWeight.w800)
                : cell(employee!.active ? 'نشط' : 'غير نشط'),
          ),
          Expanded(
            flex: 2,
            child: header
                ? cell('الراتب الشهري', weight: FontWeight.w800)
                : cell(formatPayrollMinor(employee!.baseSalaryMinor)),
          ),
          Expanded(
            flex: 2,
            child: header
                ? cell('السلف', weight: FontWeight.w800)
                : cell(
                    formatPayrollMinor(
                      _readMinor(json, 'advance_balance_minor'),
                    ),
                  ),
          ),
          Expanded(
            flex: 2,
            child: header
                ? cell('المستحق', weight: FontWeight.w800)
                : cell(
                    formatPayrollMinor(
                      _readMinor(json, 'payable_balance_minor'),
                    ),
                  ),
          ),
          Expanded(
            flex: 3,
            child: header
                ? cell('الإجراءات', weight: FontWeight.w800)
                : Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      TextButton(
                        key: Key('payroll-statement-${employee!.id}'),
                        onPressed: () => onLedger!(employee!),
                        child: const Text('كشف الموظف'),
                      ),
                      if (canAdvance)
                        TextButton(
                          key: Key('payroll-advance-${employee!.id}'),
                          onPressed: () => onAdvance!(employee!),
                          child: const Text('سلفة/سحب'),
                        ),
                      if (canManage)
                        IconButton(
                          key: Key('payroll-edit-${employee!.id}'),
                          tooltip: 'تعديل الموظف',
                          onPressed: () => onEdit!(employee!),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      if (canManage && employee!.active)
                        IconButton(
                          key: Key('payroll-deactivate-${employee!.id}'),
                          tooltip: 'تعطيل الموظف',
                          onPressed: () => onDeactivate!(employee!),
                          icon: const Icon(Icons.person_off_outlined),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    required this.canAdvance,
    required this.canManage,
    required this.onLedger,
    required this.onAdvance,
    required this.onEdit,
    required this.onDeactivate,
  });

  final Employee employee;
  final bool canAdvance;
  final bool canManage;
  final ValueChanged<Employee> onLedger;
  final ValueChanged<Employee> onAdvance;
  final ValueChanged<Employee> onEdit;
  final ValueChanged<Employee> onDeactivate;

  @override
  Widget build(BuildContext context) {
    final json = employee.toJson();
    return Container(
      key: Key('payroll-employee-card-${employee.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: NizamiColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(employee.phone ?? 'لا يوجد هاتف'),
                  ],
                ),
              ),
              Chip(label: Text(employee.active ? 'نشط' : 'غير نشط')),
            ],
          ),
          const SizedBox(height: 10),
          _CardAmount(label: 'الراتب', value: employee.baseSalaryMinor),
          _CardAmount(
            label: 'رصيد السلف',
            value: _readMinor(json, 'advance_balance_minor'),
          ),
          _CardAmount(
            label: 'المستحق',
            value: _readMinor(json, 'payable_balance_minor'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: Key('payroll-statement-${employee.id}'),
                onPressed: () => onLedger(employee),
                child: const Text('كشف الموظف'),
              ),
              if (canAdvance)
                FilledButton.tonal(
                  key: Key('payroll-advance-${employee.id}'),
                  onPressed: () => onAdvance(employee),
                  child: const Text('سلفة/سحب'),
                ),
              if (canManage)
                IconButton(
                  key: Key('payroll-edit-${employee.id}'),
                  tooltip: 'تعديل الموظف',
                  onPressed: () => onEdit(employee),
                  icon: const Icon(Icons.edit_outlined),
                ),
              if (canManage && employee.active)
                IconButton(
                  key: Key('payroll-deactivate-${employee.id}'),
                  tooltip: 'تعطيل الموظف',
                  onPressed: () => onDeactivate(employee),
                  icon: const Icon(Icons.person_off_outlined),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardAmount extends StatelessWidget {
  const _CardAmount({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Flexible(
          flex: 2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              formatPayrollMinor(value),
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    ),
  );
}

int _readMinor(Map<String, dynamic>? json, String field) =>
    json?[field] is int ? json![field] as int : 0;

class _AdvanceSheet extends StatefulWidget {
  const _AdvanceSheet({
    required this.employee,
    required this.accounts,
    required this.intent,
    required this.onNewIntent,
    required this.onRetry,
    required this.onSubmit,
  });
  final Employee employee;
  final List<ChartAccount> accounts;
  final _AdvanceIntent? intent;
  final Future<void> Function() onNewIntent;
  final Future<void> Function()? onRetry;
  final Future<void> Function(
    int amount,
    String category,
    String note,
    String account,
    DateTime occurredAt,
  )
  onSubmit;

  @override
  State<_AdvanceSheet> createState() => _AdvanceSheetState();
}

class _AdvanceSheetState extends State<_AdvanceSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _category = 'advance';
  String? _account;
  DateTime _occurredAt = DateTime.now();
  bool _saving = false;
  String? _error;
  late bool _locked;

  @override
  void initState() {
    super.initState();
    _locked = widget.intent != null;
    _account = widget.accounts.firstOrNull?.code;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final amount = int.tryParse(_amount.text.trim());
    if (amount == null ||
        amount <= 0 ||
        _note.text.trim().isEmpty ||
        _account == null) {
      setState(() => _error = 'أدخل مبلغًا صحيحًا بوحدات صحيحة وملاحظة واضحة');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        amount,
        _category,
        _note.text.trim(),
        _account!,
        _occurredAt,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('payroll-advance-form'),
    padding: EdgeInsets.fromLTRB(
      18,
      18,
      18,
      MediaQuery.viewInsetsOf(context).bottom + 18,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'سلفة/سحب — ${widget.employee.name}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          if (_locked) ...[
            Container(
              key: Key('payroll-advance-intent-${widget.intent!.operationId}'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: NizamiColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('operation ${widget.intent!.operationId}'),
                  Text('state ${widget.intent!.state}'),
                  Text(
                    'amount ${widget.intent!.request['amount_minor']} • '
                    '${widget.intent!.request['account_code']}',
                  ),
                  Text(widget.intent!.request['note']?.toString() ?? ''),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (widget.intent!.state == 'prepared' && widget.onRetry != null)
              FilledButton.icon(
                key: const Key('payroll-advance-retry-intent'),
                onPressed: _saving
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        try {
                          await widget.onRetry!();
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry the same saved intent'),
              ),
            OutlinedButton.icon(
              key: const Key('payroll-advance-new-intent'),
              onPressed: _saving
                  ? null
                  : () async {
                      await widget.onNewIntent();
                      if (mounted) setState(() => _locked = false);
                    },
              icon: const Icon(Icons.add),
              label: const Text('Start an explicit new advance'),
            ),
          ] else ...[
            NineSoftEntryFieldGrid(
              maxColumns: 2,
              children: [
                TextField(
                  key: const Key('payroll-advance-amount'),
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'المبلغ بوحدات نقدية صحيحة',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'التصنيف'),
                  items: const [
                    DropdownMenuItem(value: 'advance', child: Text('سلفة')),
                    DropdownMenuItem(value: 'withdrawal', child: Text('سحبية')),
                    DropdownMenuItem(value: 'debt', child: Text('دين')),
                    DropdownMenuItem(value: 'other', child: Text('أخرى')),
                  ],
                  onChanged: (value) => setState(() => _category = value!),
                ),
                DropdownButtonFormField<String>(
                  key: const Key('payroll-advance-account'),
                  isExpanded: true,
                  initialValue: _account,
                  decoration: const InputDecoration(labelText: 'حساب الصرف'),
                  items: [
                    for (final account in widget.accounts)
                      DropdownMenuItem(
                        value: account.code,
                        child: Text(
                          '${account.nameAr} • ${account.code}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _account = value!),
                ),
                OutlinedButton.icon(
                  key: const Key('payroll-advance-date'),
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text('تاريخ السند ${_dateLabel(_occurredAt)}'),
                ),
                TextField(
                  key: const Key('payroll-advance-note'),
                  controller: _note,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'الملاحظة'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('payroll-advance-submit'),
              onPressed: _saving ? null : _submit,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ في قائمة الإرسال'),
            ),
            const SizedBox(height: 8),
            const Text(
              'الحفظ لا يعني الترحيل؛ تظهر النتيجة النهائية فقط بعد وصول الإقرار القانوني.',
            ),
          ],
        ],
      ),
    ),
  );

  String _dateLabel(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (value != null && mounted) setState(() => _occurredAt = value);
  }
}

class _AdvanceIntent {
  const _AdvanceIntent({required this.request, required this.state});

  final Map<String, dynamic> request;
  final String state;
  String get operationId => request['local_operation_id'] as String;
}

class _NewEmployeeValue {
  const _NewEmployeeValue({
    required this.name,
    required this.phone,
    required this.salaryMinor,
    required this.startDate,
    required this.notes,
  });
  final String name;
  final String? phone;
  final int salaryMinor;
  final String startDate;
  final String? notes;
}

class _EmployeeCreateSheet extends StatefulWidget {
  const _EmployeeCreateSheet({this.initial});

  final Employee? initial;

  @override
  State<_EmployeeCreateSheet> createState() => _EmployeeCreateSheetState();
}

class _EmployeeCreateSheetState extends State<_EmployeeCreateSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _salary = TextEditingController();
  final _notes = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    final json = initial.toJson();
    _name.text = initial.name;
    _phone.text = initial.phone ?? '';
    _salary.text = initial.baseSalaryMinor.toString();
    _notes.text = json['notes']?.toString() ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _salary.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final salary = int.tryParse(_salary.text.trim());
    if (_name.text.trim().isEmpty || salary == null || salary < 0) {
      setState(() => _error = 'الاسم والراتب الصحيح مطلوبان');
      return;
    }
    final today = DateTime.now();
    final existingStart = widget.initial?.toJson()['start_date']?.toString();
    Navigator.pop(
      context,
      _NewEmployeeValue(
        name: _name.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        salaryMinor: salary,
        startDate:
            existingStart ??
            '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      18,
      18,
      18,
      MediaQuery.viewInsetsOf(context).bottom + 18,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.initial == null ? 'إضافة موظف' : 'تعديل الموظف',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          NineSoftEntryFieldGrid(
            maxColumns: 2,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'الاسم'),
              ),
              TextField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'الهاتف'),
              ),
              TextField(
                controller: _salary,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'الراتب بوحدات صحيحة',
                ),
              ),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'ملاحظات'),
              ),
            ],
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _submit,
            child: const Text('حفظ في قائمة الإرسال'),
          ),
        ],
      ),
    ),
  );
}
