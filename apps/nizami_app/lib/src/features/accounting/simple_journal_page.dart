import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../core/formatters/latin_digit_formatter.dart';

import 'accounting_api.dart';
import 'chart_accounts_api.dart';
import '../modules/catalog_sync_api.dart';
import '../../theme/ninesoft_ui.dart';
import '../../theme/ninesoft_confirm_shortcuts.dart';
import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/nizami_theme.dart';

class SimpleJournalPage extends StatefulWidget {
  const SimpleJournalPage({
    super.key,
    required this.token,
    required this.branchIds,
    required this.roleCode,
    required this.permissions,
  });

  final String token;
  final List<String> branchIds;
  final String roleCode;
  final List<String> permissions;

  @override
  State<SimpleJournalPage> createState() => _SimpleJournalPageState();
}

class _SimpleJournalPageState extends State<SimpleJournalPage> {
  late final AccountingApi _accounting = AccountingApi(token: widget.token);
  late final ChartAccountsApi _chart = ChartAccountsApi(widget.token);
  String? _branchId;
  List<ChartAccount> _accounts = const [];
  List<Map<String, dynamic>> _entries = const [];
  List<Map<String, dynamic>> _customers = const [];
  List<Map<String, dynamic>> _suppliers = const [];
  bool _loading = true;
  String? _pendingJournalFingerprint;
  String? _pendingJournalOperationId;
  Completer<_JournalDraft?>? _journalEditorResult;
  final _searchController = TextEditingController();
  String _query = '';

  bool get _canCreate =>
      widget.roleCode == 'owner' ||
      widget.permissions.contains('invoices.create');

  bool get _canReverse =>
      widget.roleCode == 'owner' ||
      widget.permissions.contains('invoices.delete');

  @override
  void initState() {
    super.initState();
    _branchId = widget.branchIds.isEmpty ? null : widget.branchIds.first;
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _visibleEntries {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _entries;
    return _entries
        .where((entry) {
          final lines = (entry['lines'] as List? ?? const []).whereType<Map>();
          final searchable = [
            entry['description'],
            entry['reference_type'],
            entry['id'],
            for (final line in lines) line['account_code'],
            for (final line in lines) line['contact_name'],
          ].whereType<Object>().join(' ').toLowerCase();
          return searchable.contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _load() async {
    final branchId = _branchId;
    if (branchId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await Future.wait<Object>([
        _chart.list(branchId),
        _accounting.listJournals(branchId: branchId),
        CatalogSyncApi(token: widget.token).list('customers'),
        CatalogSyncApi(token: widget.token).list('suppliers'),
      ]);
      if (!mounted) return;
      setState(() {
        _accounts = (results[0] as List<ChartAccount>)
            .where(
              (account) =>
                  account.active &&
                  account.allowPosting &&
                  account.code != '1300-INVENTORY',
            )
            .toList(growable: false);
        _entries = results[1] as List<Map<String, dynamic>>;
        _customers = results[2] as List<Map<String, dynamic>>;
        _suppliers = results[3] as List<Map<String, dynamic>>;
      });
    } catch (error) {
      _message(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(Object value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _create() async {
    final draft = await _openJournalEditor();
    if (draft == null || !mounted) return;
    if (_accounts.length < 2 || _branchId == null) {
      _message('يجب توفر حسابين قابلين للترحيل في شجرة الحسابات.');
      return;
    }
    final value = double.tryParse(draft.amount.trim());
    if (draft.description.trim().length < 3 || value == null || value <= 0) {
      _message('أدخل بيانًا واضحًا ومبلغًا صحيحًا.');
      return;
    }
    final fingerprint = <Object?>[
      _branchId,
      draft.description.trim(),
      draft.debitAccountCode,
      draft.creditAccountCode,
      value,
      draft.debitContactId,
      draft.creditContactId,
    ].join('\u001f');
    final localOperationId =
        _pendingJournalFingerprint == fingerprint &&
            _pendingJournalOperationId != null
        ? _pendingJournalOperationId!
        : const Uuid().v4();
    _pendingJournalFingerprint = fingerprint;
    _pendingJournalOperationId = localOperationId;
    try {
      await _accounting.postSimpleJournal(
        branchId: _branchId!,
        localOperationId: localOperationId,
        description: draft.description,
        debitAccountCode: draft.debitAccountCode,
        creditAccountCode: draft.creditAccountCode,
        amount: value,
        debitContactId: draft.debitContactId,
        creditContactId: draft.creditContactId,
      );
      _pendingJournalFingerprint = null;
      _pendingJournalOperationId = null;
      _message('تم حفظ القيد وترحيله بنجاح.');
      await _load();
    } catch (error) {
      _message(error);
    }
  }

  Future<_JournalDraft?> _openJournalEditor() {
    final active = _journalEditorResult;
    if (active != null) return active.future;
    final result = Completer<_JournalDraft?>();
    setState(() => _journalEditorResult = result);
    return result.future;
  }

  void _closeJournalEditor([_JournalDraft? draft]) {
    final result = _journalEditorResult;
    if (result == null || result.isCompleted) return;
    setState(() => _journalEditorResult = null);
    result.complete(draft);
  }

  List<DropdownMenuItem<String>> _accountItems() => _accounts
      .map(
        (account) => DropdownMenuItem(
          value: account.code,
          child: Text('${account.code} • ${account.nameAr}'),
        ),
      )
      .toList(growable: false);

  String? _partyType(String accountCode) => switch (accountCode) {
    '1200-AR' => 'customer',
    '2100-AP' => 'supplier',
    _ => null,
  };

  Widget _partyPicker({
    required String accountCode,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final customer = _partyType(accountCode) == 'customer';
    final source = customer ? _customers : _suppliers;
    String label(Map<String, dynamic> item) => [
      item['name']?.toString() ?? '',
      item['account_number']?.toString() ?? '',
      item['phone']?.toString() ?? '',
    ].where((part) => part.isNotEmpty).join(' • ');
    final selected = source.where((item) => item['id']?.toString() == value);
    return Autocomplete<Map<String, dynamic>>(
      initialValue: TextEditingValue(
        text: selected.isEmpty ? '' : label(selected.first),
      ),
      displayStringForOption: label,
      optionsBuilder: (editing) {
        final query = editing.text.trim().toLowerCase();
        if (query.isEmpty) return source;
        return source.where(
          (item) => label(item).toLowerCase().contains(query),
        );
      },
      onSelected: (item) => onChanged(item['id']?.toString()),
      fieldViewBuilder: (_, controller, focusNode, submit) => TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: (_) => onChanged(null),
        onSubmitted: (_) => submit(),
        decoration: InputDecoration(
          labelText: customer ? 'ابحث واختر العميل' : 'ابحث واختر المورد',
          prefixIcon: Icon(
            customer ? Icons.person_outline : Icons.local_shipping_outlined,
          ),
        ),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> entry) async {
    final id = entry['id']?.toString();
    if (id == null || id.isEmpty) return;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => NineSoftEnterConfirmScope(
        onConfirm: () => Navigator.pop(dialogContext, true),
        child: AlertDialog(
          title: const Text('حذف القيد البسيط نهائيا'),
          content: TextField(
            controller: reason,
            autofocus: true,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'سبب الحذف',
              helperText:
                  'سيحذف القيد وكل أثره المحاسبي، مع بقاء سجل التدقيق فقط.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف نهائي'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    if (reason.text.trim().length < 3) {
      _message('اكتب سببًا واضحًا لحذف القيد.');
      return;
    }
    try {
      await _accounting.voidSimpleJournal(id, reason: reason.text);
      _message('تم حذف القيد وأثره المحاسبي.');
      await _load();
    } catch (error) {
      _message(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_journalEditorResult != null) {
      return _JournalDraftEditor(
        key: const ValueKey('journal-document-editor'),
        accounts: _accounts,
        customers: _customers,
        suppliers: _suppliers,
        onCancel: _closeJournalEditor,
        onSave: _closeJournalEditor,
      );
    }
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    final visibleEntries = _visibleEntries;
    final totalMinor = _entries.fold<int>(0, (sum, entry) {
      final lines = (entry['lines'] as List? ?? const []).whereType<Map>();
      return sum +
          lines.fold<int>(
            0,
            (lineSum, line) =>
                lineSum + ((line['debit_minor'] as num?)?.toInt() ?? 0),
          );
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('القيود اليومية'),
        toolbarHeight: desktop ? 0 : null,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: !desktop && _canCreate && _branchId != null
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('قيد بسيط'),
            )
          : null,
      body: SafeArea(
        child: NineSoftResponsiveBody(
          child: Column(
            children: [
              NineSoftPageHeader(
                title: 'القيود اليومية',
                subtitle: 'تسجيل ومراجعة القيود المحاسبية المتوازنة',
                icon: Icons.menu_book_rounded,
                color: NizamiColors.blue,
                actions: [
                  OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('تحديث'),
                  ),
                  if (_canCreate && _branchId != null)
                    FilledButton.icon(
                      onPressed: _create,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('قيد جديد'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
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
                          (id) => DropdownMenuItem(value: id, child: Text(id)),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      _branchId = value;
                      _load();
                    },
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: NineSoftMetricCard(
                      label: 'عدد القيود',
                      value: '${_entries.length}',
                      caption: 'قيد مرحّل',
                      icon: Icons.receipt_long_rounded,
                      color: NizamiColors.blue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NineSoftMetricCard(
                      label: 'إجمالي المدين',
                      value: (totalMinor / 100).toStringAsFixed(2),
                      caption: 'YER',
                      icon: Icons.south_west_rounded,
                      color: NizamiColors.green,
                    ),
                  ),
                  if (desktop) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: NineSoftMetricCard(
                        label: 'إجمالي الدائن',
                        value: (totalMinor / 100).toStringAsFixed(2),
                        caption: 'القيد متوازن',
                        icon: Icons.north_east_rounded,
                        color: NizamiColors.red,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              NineSoftSearchField(
                controller: _searchController,
                hintText: 'ابحث في القيود أو اكتب بيان القيد ...',
                onChanged: (value) => setState(() => _query = value),
                onClear: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : visibleEntries.isEmpty
                    ? NineSoftEmptyState(
                        icon: Icons.menu_book_outlined,
                        title: _query.isEmpty
                            ? 'لا توجد قيود مرحّلة حتى الآن'
                            : 'لا توجد نتائج مطابقة',
                        message: _query.isEmpty
                            ? 'أنشئ أول قيد عند الحاجة، ولن تُعرض أي بيانات تجريبية.'
                            : 'جرّب البحث برقم حساب أو بيان آخر.',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
                          itemCount: visibleEntries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, index) =>
                              _entryCard(visibleEntries[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entryCard(Map<String, dynamic> entry) {
    final lines = (entry['lines'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final debit = lines.fold<int>(
      0,
      (sum, line) => sum + ((line['debit_minor'] as num?)?.toInt() ?? 0),
    );
    final accounts = lines
        .map((line) {
          final code = line['account_code']?.toString() ?? '';
          final party = line['contact_name']?.toString() ?? '';
          return party.isEmpty ? code : '$code • $party';
        })
        .where((code) => code.isNotEmpty)
        .join(' ↔ ');
    final manual = entry['reference_type'] == 'manual_journal';
    final reversal = entry['reference_type'] == 'manual_journal_void';
    final reversed = entry['is_reversed'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              child: Icon(
                manual ? Icons.edit_note_rounded : Icons.menu_book_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry['description']?.toString().trim().isNotEmpty == true
                        ? entry['description'].toString()
                        : manual
                        ? 'قيد يومية بسيط'
                        : 'قيد محاسبي آلي',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(accounts, textDirection: TextDirection.ltr),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${(debit / 100).toStringAsFixed(2)} YER',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontFamily: 'ArialMTBlack',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (reversed || reversal)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(reversal ? 'قيد عكسي' : 'تم عكسه'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (manual && !reversed && _canReverse)
              IconButton(
                tooltip: 'حذف القيد نهائيا',
                onPressed: () => _delete(entry),
                icon: const Icon(Icons.undo_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _JournalDraft {
  const _JournalDraft({
    required this.description,
    required this.amount,
    required this.debitAccountCode,
    required this.creditAccountCode,
    this.debitContactId,
    this.creditContactId,
  });

  final String description;
  final String amount;
  final String debitAccountCode;
  final String creditAccountCode;
  final String? debitContactId;
  final String? creditContactId;
}

class _JournalDraftEditor extends StatefulWidget {
  const _JournalDraftEditor({
    required this.accounts,
    required this.customers,
    required this.suppliers,
    required this.onCancel,
    required this.onSave,
    super.key,
  });

  final List<ChartAccount> accounts;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> suppliers;
  final VoidCallback onCancel;
  final ValueChanged<_JournalDraft> onSave;

  @override
  State<_JournalDraftEditor> createState() => _JournalDraftEditorState();
}

class _JournalDraftEditorState extends State<_JournalDraftEditor> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  late String _debit = widget.accounts.firstOrNull?.code ?? '';
  late String _credit = widget.accounts.length > 1
      ? widget.accounts[1].code
      : '';
  String? _debitContactId;
  String? _creditContactId;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  String? _partyType(String accountCode) => switch (accountCode) {
    '1200-AR' => 'customer',
    '2100-AP' => 'supplier',
    _ => null,
  };

  List<DropdownMenuItem<String>> _accountItems() => widget.accounts
      .map(
        (account) => DropdownMenuItem(
          value: account.code,
          child: Text('${account.code} • ${account.nameAr}'),
        ),
      )
      .toList(growable: false);

  Widget _partyPicker({
    required String accountCode,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final customer = _partyType(accountCode) == 'customer';
    final source = customer ? widget.customers : widget.suppliers;
    String label(Map<String, dynamic> item) => [
      item['name']?.toString() ?? '',
      item['account_number']?.toString() ?? '',
      item['phone']?.toString() ?? '',
    ].where((part) => part.isNotEmpty).join(' • ');
    final selected = source.where((item) => item['id']?.toString() == value);
    return Autocomplete<Map<String, dynamic>>(
      initialValue: TextEditingValue(
        text: selected.isEmpty ? '' : label(selected.first),
      ),
      displayStringForOption: label,
      optionsBuilder: (input) {
        final query = input.text.trim().toLowerCase();
        if (query.isEmpty) return source;
        return source.where(
          (item) => label(item).toLowerCase().contains(query),
        );
      },
      onSelected: (item) => onChanged(item['id']?.toString()),
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              labelText: customer ? 'العميل' : 'المورد',
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
    );
  }

  void _submit() {
    if (widget.accounts.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب توفر حسابين قابلين للترحيل قبل حفظ القيد.'),
        ),
      );
      return;
    }
    widget.onSave(
      _JournalDraft(
        description: _description.text,
        amount: _amount.text,
        debitAccountCode: _debit,
        creditAccountCode: _credit,
        debitContactId: _debitContactId,
        creditContactId: _creditContactId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('قيد يومية جديد'),
      leading: IconButton(
        onPressed: widget.onCancel,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      actions: [
        TextButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save_outlined),
          label: const Text('حفظ وترحيل'),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NineSoftDocumentCommandBar(
            title: 'إجراءات القيد',
            actions: [
              NineSoftDocumentCommandAction(
                key: const ValueKey('journal-command-save'),
                label: 'حفظ وترحيل',
                shortcut: 'Ctrl+Enter',
                icon: Icons.cloud_done_rounded,
                color: NizamiColors.blue,
                onPressed: _submit,
              ),
              NineSoftDocumentCommandAction(
                key: const ValueKey('journal-command-cancel'),
                label: 'إلغاء',
                shortcut: 'Esc',
                icon: Icons.close_rounded,
                color: NizamiColors.red,
                onPressed: widget.onCancel,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.accounts.length < 2) ...[
            const NineSoftEntryHint(
              text:
                  'لا توجد حسابات كافية قابلة للترحيل. حدّث شجرة الحسابات ثم أعد المحاولة.',
              icon: Icons.info_outline_rounded,
            ),
            const SizedBox(height: 10),
          ],
          NineSoftEntrySection(
            title: 'بيان القيد',
            icon: Icons.edit_note_outlined,
            step: '01',
            accent: NizamiColors.blue,
            child: TextField(
              key: const ValueKey('journal-description'),
              controller: _description,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'البيان / الوصف المحاسبي',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
          ),
          const SizedBox(height: 10),
          NineSoftEntryFieldGrid(
            minFieldWidth: 270,
            maxColumns: 2,
            children: [
              NineSoftEntrySection(
                title: 'الطرف المدين',
                icon: Icons.south_west_rounded,
                step: '02',
                accent: NizamiColors.blue,
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      key: const ValueKey('journal-debit-account'),
                      initialValue: _debit.isEmpty ? null : _debit,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'الحساب المدين',
                      ),
                      items: _accountItems(),
                      onChanged: (value) => setState(() {
                        _debit = value ?? '';
                        _debitContactId = null;
                      }),
                    ),
                    if (_partyType(_debit) != null) ...[
                      const SizedBox(height: 8),
                      _partyPicker(
                        accountCode: _debit,
                        value: _debitContactId,
                        onChanged: (value) =>
                            setState(() => _debitContactId = value),
                      ),
                    ],
                  ],
                ),
              ),
              NineSoftEntrySection(
                title: 'الطرف الدائن',
                icon: Icons.north_east_rounded,
                step: '03',
                accent: NizamiColors.purple,
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      key: const ValueKey('journal-credit-account'),
                      initialValue: _credit.isEmpty ? null : _credit,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'الحساب الدائن',
                      ),
                      items: _accountItems(),
                      onChanged: (value) => setState(() {
                        _credit = value ?? '';
                        _creditContactId = null;
                      }),
                    ),
                    if (_partyType(_credit) != null) ...[
                      const SizedBox(height: 8),
                      _partyPicker(
                        accountCode: _credit,
                        value: _creditContactId,
                        onChanged: (value) =>
                            setState(() => _creditContactId = value),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          NineSoftEntrySection(
            title: 'المبلغ والتوازن',
            icon: Icons.balance_rounded,
            step: '04',
            accent: NizamiColors.green,
            child: TextField(
              key: const ValueKey('journal-amount'),
              controller: _amount,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                latinDigitFormatter,
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                labelText: 'مبلغ القيد',
                suffixText: 'YER',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
          ),
          const SizedBox(height: 10),
          NineSoftEntryFooter(
            onSave: _submit,
            label: 'حفظ وترحيل القيد',
            icon: Icons.save_outlined,
            note: 'يجب أن يتساوى الطرف المدين والدائن قبل الترحيل.',
          ),
        ],
      ),
    ),
  );
}
