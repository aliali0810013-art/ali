import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/ninesoft_confirm_shortcuts.dart';
import '../../theme/ninesoft_ui.dart';
import '../administration/administration_api.dart';
import '../modules/catalog_sync_api.dart';
import 'accounting_api.dart';
import 'chart_accounts_api.dart';
import 'searchable_chart_account_field.dart';

/// One-time owner-only opening. Every operation has a stable, locally preserved
/// request. A timeout is NOT proof of failure; never generate a second opening
/// operation until the first is reconciled with the server ledger.
class OpeningBalancesPage extends StatefulWidget {
  const OpeningBalancesPage({
    super.key,
    required this.token,
    required this.branchIds,
    required this.roleCode,
  });

  final String token;
  final List<String> branchIds;
  final String roleCode;

  @override
  State<OpeningBalancesPage> createState() => _OpeningBalancesPageState();
}

class _OpeningLine {
  String? code;
  String? contactId;
  final debit = TextEditingController();
  final credit = TextEditingController();
  void dispose() {
    debit.dispose();
    credit.dispose();
  }
}

class _OpeningStock {
  String? productId;
  final quantity = TextEditingController();
  final value = TextEditingController();
  void dispose() {
    quantity.dispose();
    value.dispose();
  }
}

class _OpeningBalancesPageState extends State<OpeningBalancesPage> {
  late final AccountingApi _api = AccountingApi(token: widget.token);
  late final ChartAccountsApi _chart = ChartAccountsApi(widget.token);
  late final AdministrationApi _administration = AdministrationApi(
    token: widget.token,
  );
  String? _branch;
  Map<String, String> _branchNames = const {};
  DateTime _openingDate = DateTime.now();
  List<ChartAccount> _accounts = const [];
  List<Map<String, dynamic>> _customers = const [];
  List<Map<String, dynamic>> _suppliers = const [];
  List<Map<String, dynamic>> _products = const [];
  final _lines = <_OpeningLine>[];
  final _stock = <_OpeningStock>[];
  Map<String, dynamic> _status = const {};
  Map<String, dynamic> _metadata = const {};
  Map<String, dynamic>? _pending;
  String? _error;
  bool _loading = false;
  bool _submitting = false;
  bool _stockLoaded = false;

  bool get _owner => widget.roleCode == 'owner';
  bool get _editable =>
      _owner &&
      !_loading &&
      !_submitting &&
      _pending == null &&
      _status['can_open'] == true;
  String get _date =>
      '${_openingDate.year.toString().padLeft(4, '0')}-${_openingDate.month.toString().padLeft(2, '0')}-${_openingDate.day.toString().padLeft(2, '0')}';
  String get _storageKey =>
      'ninesoft.accounting.opening.pending.${_branch ?? 'none'}';

  @override
  void initState() {
    super.initState();
    _branch = widget.branchIds.firstOrNull;
    _lines.add(_OpeningLine());
    _loadBranchNames();
    _load();
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
      // Keep internal branch identifiers hidden even if the directory is offline.
    }
  }

  @override
  void dispose() {
    for (final row in _lines) {
      row.dispose();
    }
    for (final row in _stock) {
      row.dispose();
    }
    super.dispose();
  }

  static int? _scaled(String raw, int decimals) {
    final s = raw
        .trim()
        .replaceAll('٫', '.')
        .replaceAll('٬', '')
        .replaceAllMapped(RegExp(r'[٠-٩۰-۹]'), (match) {
          const arabic = '٠١٢٣٤٥٦٧٨٩';
          const persian = '۰۱۲۳۴۵۶۷۸۹';
          final char = match.group(0)!;
          final code = arabic.contains(char)
              ? arabic.indexOf(char)
              : persian.indexOf(char);
          return code.toString();
        });
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) return null;
    final parts = s.split('.');
    if (parts.length > 1 && parts[1].length > decimals) return null;
    final whole = int.tryParse(parts[0]);
    final fractional =
        int.tryParse(
          (parts.length > 1 ? parts[1] : '').padRight(decimals, '0'),
        ) ??
        0;
    if (whole == null) return null;
    final minor = whole * _power10(decimals) + fractional;
    // Matches Laravel's per-field cap; keeps sums exact in Dart web JS ints.
    if (minor > 1000000000000) return null;
    return minor;
  }

  static int _power10(int decimals) => decimals == 3 ? 1000 : 100;
  static String _money(int value) =>
      '${value ~/ 100}.${(value.abs() % 100).toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final branch = _branch;
    if (branch == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _api.openingBalanceStatus(branch),
        _api.administrationMetadata(),
        _chart.list(branch),
      ]);
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_storageKey);
      Map<String, dynamic>? pending;
      if (saved != null) {
        final decoded = jsonDecode(saved);
        if (decoded is Map) pending = Map<String, dynamic>.from(decoded);
      }
      if (!mounted || _branch != branch) return;
      final status = results[0] as Map<String, dynamic>;
      final openings = (status['previous_openings'] as List? ?? const [])
          .whereType<Map>();
      if (pending != null &&
          openings.any(
            (entry) => entry['reference_id'] == pending!['operation_id'],
          )) {
        await prefs.remove(_storageKey);
        pending = null;
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _metadata = results[1] as Map<String, dynamic>;
        _accounts = (results[2] as List<ChartAccount>)
            .where(
              (a) => a.active && a.allowPosting && a.code != '1300-INVENTORY',
            )
            .toList();
        _pending = pending;
        _lines.first.code ??= _accounts.firstOrNull?.code;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'تعذر قراءة بيانات الافتتاح: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadParties() async {
    if (_customers.isNotEmpty || _suppliers.isNotEmpty) return;
    try {
      final api = CatalogSyncApi(token: widget.token);
      final data = await Future.wait([
        api.list('customers'),
        api.list('suppliers'),
      ]);
      if (mounted) {
        setState(() {
          _customers = data[0];
          _suppliers = data[1];
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'تعذر جلب الأطراف؛ لا يمكن افتتاح الذمم دون تحديد طرف: $error',
        );
      }
    }
  }

  Future<void> _loadProducts() async {
    if (_stockLoaded) return;
    setState(() => _loading = true);
    try {
      final items = await CatalogSyncApi(token: widget.token).list('products');
      if (mounted) {
        setState(() {
          _products = items
              .where((r) => r['kind'] == 'stock' && r['deleted_at'] == null)
              .toList();
          _stockLoaded = true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر جلب قائمة الأصناف: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<DropdownMenuItem<String>> _contactsFor(String? code) {
    final source = code == '1200-AR' ? _customers : _suppliers;
    return source
        .map(
          (r) => DropdownMenuItem<String>(
            value: r['id'].toString(),
            child: Text(
              r['name']?.toString() ?? 'بدون اسم',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();
  }

  Widget _accountRow(_OpeningLine row, int index) {
    final isParty = row.code == '1200-AR' || row.code == '2100-AP';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 300,
              child: SearchableChartAccountField(
                accounts: _accounts,
                value: _accounts.any((a) => a.code == row.code)
                    ? row.code
                    : null,
                label: 'الحساب',
                onChanged: _editable
                    ? (value) {
                        setState(() {
                          row.code = value;
                          row.contactId = null;
                        });
                        if (value == '1200-AR' || value == '2100-AP') {
                          _loadParties();
                        }
                      }
                    : null,
              ),
            ),
            if (isParty)
              SizedBox(
                width: 225,
                child: DropdownButtonFormField<String>(
                  initialValue:
                      _contactsFor(
                        row.code,
                      ).any((v) => v.value == row.contactId)
                      ? row.contactId
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: row.code == '1200-AR' ? 'العميل' : 'المورد',
                  ),
                  items: _contactsFor(row.code),
                  onChanged: _editable
                      ? (value) => setState(() => row.contactId = value)
                      : null,
                ),
              ),
            SizedBox(
              width: 155,
              child: TextField(
                controller: row.debit,
                enabled: _editable,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'مدين (ريال)'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            SizedBox(
              width: 155,
              child: TextField(
                controller: row.credit,
                enabled: _editable,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'دائن (ريال)'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            IconButton(
              onPressed: _editable && _lines.length > 1
                  ? () => setState(() {
                      _lines.removeAt(index);
                      row.dispose();
                    })
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'حذف السطر',
            ),
          ],
        ),
      ),
    );
  }

  Widget _stockRow(_OpeningStock row, int index) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              initialValue: _products.any((p) => p['id'] == row.productId)
                  ? row.productId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الصنف المخزني'),
              items: _products
                  .map(
                    (p) => DropdownMenuItem<String>(
                      value: p['id'].toString(),
                      child: Text(
                        p['name']?.toString() ?? '',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _editable
                  ? (value) => setState(() => row.productId = value)
                  : null,
            ),
          ),
          SizedBox(
            width: 155,
            child: TextField(
              controller: row.quantity,
              enabled: _editable,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'الكمية (حتى 3 كسور)',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            width: 155,
            child: TextField(
              controller: row.value,
              enabled: _editable,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'إجمالي التكلفة (ريال)',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            onPressed: _editable
                ? () => setState(() {
                    _stock.removeAt(index);
                    row.dispose();
                  })
                : null,
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'حذف الصنف',
          ),
        ],
      ),
    ),
  );

  int? _debitTotal() {
    var total = 0;
    for (final row in _lines) {
      final v = _scaled(row.debit.text.isEmpty ? '0' : row.debit.text, 2);
      if (v == null) return null;
      total += v;
    }
    for (final row in _stock) {
      final v = _scaled(row.value.text, 2);
      if (v == null) return null;
      total += v;
    }
    return total;
  }

  int? _creditTotal() {
    var total = 0;
    for (final row in _lines) {
      final v = _scaled(row.credit.text.isEmpty ? '0' : row.credit.text, 2);
      if (v == null) return null;
      total += v;
    }
    return total;
  }

  Future<void> _createOpening() async {
    if (!_editable || _branch == null) return;
    try {
      final lines = <Map<String, dynamic>>[];
      for (final row in _lines) {
        final debit = _scaled(row.debit.text.isEmpty ? '0' : row.debit.text, 2);
        final credit = _scaled(
          row.credit.text.isEmpty ? '0' : row.credit.text,
          2,
        );
        if (row.code == null ||
            debit == null ||
            credit == null ||
            (debit > 0) == (credit > 0)) {
          throw const FormatException(
            'كل سطر يحتاج حسابًا ومبلغًا مدينًا أو دائنًا فقط.',
          );
        }
        if ((row.code == '1200-AR' || row.code == '2100-AP') &&
            row.contactId == null) {
          throw const FormatException(
            'اختر العميل أو المورد المرتبط برصيد الذمم.',
          );
        }
        lines.add({
          'account_code': row.code,
          'debit_minor': debit,
          'credit_minor': credit,
          if (row.contactId != null) 'contact_id': row.contactId,
        });
      }
      final stock = <Map<String, dynamic>>[];
      for (final row in _stock) {
        final qty = _scaled(row.quantity.text, 3);
        final value = _scaled(row.value.text, 2);
        if (row.productId == null ||
            qty == null ||
            value == null ||
            qty <= 0 ||
            value <= 0) {
          throw const FormatException(
            'كل صنف يحتاج كمية موجبة وقيمة تكلفة موجبة وصنفًا صحيحًا.',
          );
        }
        stock.add({
          'product_id': row.productId,
          'quantity_milli': qty,
          'value_minor': value,
        });
      }
      final debit = _debitTotal();
      final credit = _creditTotal();
      if (debit == null || credit == null || debit == 0 || debit != credit) {
        throw const FormatException(
          'الافتتاح غير متوازن؛ يجب أن يساوي المدين (بما فيه المخزون) الدائن.',
        );
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => NineSoftEnterConfirmScope(
          onConfirm: () => Navigator.pop(context, true),
          child: AlertDialog(
            title: const Text('تأكيد ترحيل الافتتاح النهائي'),
            content: Text(
              'هذا الإجراء ينشئ قيدًا وحركات مخزون فعلية ولا يمكن تكراره على فرع به حركة.\nمدين: ${_money(debit)} — دائن: ${_money(credit)}\nهل راجعت البيانات والتاريخ؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('ترحيل بعد المراجعة'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      final request = <String, dynamic>{
        'branch_id': _branch,
        'operation_id': const Uuid().v4(),
        'opening_at': _date,
        'restore_generation': _metadata['restore_generation'],
        'operation_created_at': DateTime.now().toUtc().toIso8601String(),
        'lines': lines,
        'stock_items': stock,
      };
      final prefs = await SharedPreferences.getInstance();
      // Persist the exact body before HTTP. Never quietly regenerate after timeout.
      await prefs.setString(_storageKey, jsonEncode(request));
      if (!mounted) return;
      setState(() => _pending = request);
      await _retryPending();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _retryPending() async {
    final pending = _pending;
    if (pending == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.postOpeningBalances(pending);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      if (mounted) setState(() => _pending = null);
      await _load();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'لم يتم تأكيد الترحيل. احتفظنا بنفس الطلب لإعادة إرساله بعد مراجعة الخادم: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _discardUnconfirmed() async {
    final branch = _branch;
    if (branch == null || _pending == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // Never discard while offline: a request may have reached the server.
      final status = await _api.openingBalanceStatus(branch);
      if (status['can_open'] != true) {
        throw StateError(
          'الخادم يحتوي حركات أو افتتاحًا؛ لا يمكن حذف معرّف الطلب المعلق.',
        );
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => NineSoftEnterConfirmScope(
          onConfirm: () => Navigator.pop(dialogContext, true),
          child: AlertDialog(
            title: const Text('إلغاء الطلب المحفوظ محليًا'),
            content: const Text(
              'تحققنا من أن الفرع خالٍ من الحركات حاليًا. هل تريد إلغاء طلب الافتتاح المعلق فقط، دون تغيير أي بيانات على الخادم؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('رجوع'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('إلغاء الطلب المحلي'),
              ),
            ],
          ),
        ),
      );
      if (confirmed == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_storageKey);
        if (mounted) setState(() => _pending = null);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'تعذر التحقق من حالة الطلب قبل الإلغاء: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final debit = _debitTotal();
    final credit = _creditTotal();
    return Scaffold(
      appBar: AppBar(title: const Text('الأرصدة الافتتاحية')),
      body: SafeArea(
        child: NineSoftResponsiveBody(
          child: ListView(
            children: [
              const NineSoftEntryHeading(
                title: 'الأرصدة الافتتاحية',
                subtitle: 'افتتاح الحسابات والأطراف والمخزون بقيد واحد متوازن',
                icon: Icons.balance_outlined,
                status: 'تهيئة محاسبية',
              ),
              const SizedBox(height: 12),
              NineSoftEntrySection(
                title: 'بيانات الافتتاح',
                subtitle:
                    'اختر الفرع ثم أدخل الأرصدة وراجع التوازن قبل الترحيل',
                icon: Icons.playlist_add_check_circle_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.branchIds.isEmpty)
                      const Text('لا يوجد فرع مفعل.'),
                    if (widget.branchIds.isNotEmpty)
                      NineSoftEntryFieldGrid(
                        maxColumns: 2,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _branch,
                            decoration: const InputDecoration(
                              labelText: 'الفرع',
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
                                .toList(),
                            onChanged: _submitting || _pending != null
                                ? null
                                : (id) {
                                    setState(() {
                                      _branch = id;
                                      _status = const {};
                                      _stockLoaded = false;
                                      _products = const [];
                                    });
                                    _load();
                                  },
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    if (_loading) const LinearProgressIndicator(),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'الافتتاح مخصص للفروع الجديدة فقط. لا يستبدل أرصدة سابقة ولا يعيد ترحيل المستندات القديمة.',
                    ),
                    if (_pending != null) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'يوجد طلب افتتاح محفوظ غير مؤكد. لا تنشئ طلبًا آخر قبل تسويته؛ أعد إرسال نفس الطلب فقط.',
                      ),
                      FilledButton.icon(
                        onPressed: _submitting ? null : _retryPending,
                        icon: const Icon(Icons.sync),
                        label: const Text('التحقق بإعادة إرسال نفس العملية'),
                      ),
                      TextButton(
                        onPressed: _submitting ? null : _discardUnconfirmed,
                        child: const Text(
                          'التحقق من الخادم ثم إلغاء الطلب المحلي غير المرحل',
                        ),
                      ),
                    ],
                    if (_status.isNotEmpty && _status['can_open'] != true)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'هذا الفرع يحتوي حركات أو فترة مقفلة. الافتتاح الجديد محظور، ويجب استخدام تسوية موثقة بدلًا منه.',
                        ),
                      ),
                    if (!_owner)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'عرض الافتتاح متاح، أما الترحيل فلمالك المنشأة فقط.',
                        ),
                      ),
                    if (_status['can_open'] == true && _owner) ...[
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        onPressed: _editable
                            ? () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _openingDate,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null && mounted) {
                                  setState(() => _openingDate = picked);
                                }
                              }
                            : null,
                        icon: const Icon(Icons.event),
                        label: Text('تاريخ الافتتاح: $_date'),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'الحسابات والأطراف',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      for (var i = 0; i < _lines.length; i++)
                        _accountRow(_lines[i], i),
                      OutlinedButton.icon(
                        onPressed: _editable
                            ? () => setState(() {
                                final row = _OpeningLine()
                                  ..code = _accounts.firstOrNull?.code;
                                _lines.add(row);
                              })
                            : null,
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة سطر حساب'),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'المخزون الافتتاحي (إجمالي التكلفة وليس سعر البيع)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      for (var i = 0; i < _stock.length; i++)
                        _stockRow(_stock[i], i),
                      OutlinedButton.icon(
                        onPressed: _editable
                            ? () async {
                                await _loadProducts();
                                if (mounted && _stockLoaded) {
                                  setState(() => _stock.add(_OpeningStock()));
                                }
                              }
                            : null,
                        icon: const Icon(Icons.add_box_outlined),
                        label: const Text('إضافة صنف افتتاحي'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'إجمالي المدين مع المخزون: ${debit == null ? 'غير صالح' : _money(debit)}',
                      ),
                      Text(
                        'إجمالي الدائن: ${credit == null ? 'غير صالح' : _money(credit)}',
                      ),
                      const SizedBox(height: 12),
                      NineSoftEntryFooter(
                        label: 'مراجعة ثم ترحيل الافتتاح',
                        enabled: _editable,
                        onSave: _editable ? _createOpening : null,
                        note: 'لن يتم الترحيل إلا بعد توازن المدين والدائن',
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
