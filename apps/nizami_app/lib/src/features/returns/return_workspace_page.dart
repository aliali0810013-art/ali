import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/formatters/latin_digit_formatter.dart';
import '../../theme/ninesoft_ui.dart';
import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/ninesoft_financial_ui.dart';
import '../../theme/nizami_theme.dart';
import '../sync/realtime_sync_coordinator.dart';
import '../modules/catalog_sync_api.dart';
import 'return_quantity.dart';
import 'returns_api.dart';

class ReturnWorkspacePage extends StatefulWidget {
  const ReturnWorkspacePage({
    super.key,
    required this.token,
    required this.tenantId,
    required this.branchIds,
    required this.roleCode,
    required this.permissions,
    this.purchase = true,
  });
  final String token, tenantId, roleCode;
  final List<String> branchIds, permissions;
  final bool purchase;
  @override
  State<ReturnWorkspacePage> createState() => _ReturnWorkspacePageState();
}

class _ReturnWorkspacePageState extends State<ReturnWorkspacePage> {
  late final ReturnsApi _api = ReturnsApi(token: widget.token);
  final _search = TextEditingController();
  final _reason = TextEditingController();
  final _quantities = <String, TextEditingController>{};
  late final CatalogSyncApi _catalogApi = CatalogSyncApi(token: widget.token);
  StreamSubscription<Set<String>>? _subscription;
  Timer? _debounce;
  String? _branch;
  String _channel = 'cash';
  String _settlement = 'cash';
  String? _directContactId;
  bool _direct = true;
  String? _message;
  bool _loading = false,
      _posting = false,
      _preparing = false,
      _initializing = true,
      _reloadRequested = false;
  int _selectionGeneration = 0;
  int? _selectionRestoreGeneration;
  int _originalPage = 1, _originalLast = 1, _returnPage = 1, _returnLast = 1;
  List<Map<String, dynamic>> _originals = [], _returns = [], _items = [];
  List<Map<String, dynamic>> _products = [], _contacts = [];
  final List<Map<String, Object?>> _directRows = [];
  Map<String, dynamic>? _selected, _pending;
  String get _type => widget.purchase ? 'purchase' : 'sale';
  String get _draftKey => 'ninesoft.linked_return.v1.${widget.tenantId}.$_type';
  bool get _canPost =>
      widget.roleCode == 'owner' ||
      (widget.permissions.contains('invoices.create') &&
          widget.permissions.contains('invoices.read'));

  void _addDirectRow([Map<String, dynamic>? product]) {
    final selected = product ?? (_products.isEmpty ? null : _products.first);
    _directRows.add({
      'product_id': selected?['id']?.toString(),
      'quantity': TextEditingController(text: '1'),
      'price': TextEditingController(
        text:
            (((selected?[widget.purchase
                                    ? 'purchase_price_minor'
                                    : 'sale_price_minor']
                                as num?)
                            ?.toInt() ??
                        0) /
                    100)
                .toStringAsFixed(2),
      ),
    });
  }

  void _disposeDirectRows() {
    for (final row in _directRows) {
      (row['quantity'] as TextEditingController).dispose();
      (row['price'] as TextEditingController).dispose();
    }
    _directRows.clear();
  }

  Future<void> _loadDirectCatalog() async {
    if (_products.isNotEmpty) return;
    try {
      final values = await Future.wait([
        _catalogApi.list('products'),
        _catalogApi.list(widget.purchase ? 'suppliers' : 'customers'),
      ]);
      if (!mounted) return;
      setState(() {
        _products = values[0];
        _contacts = values[1];
        if (_directRows.isEmpty && _products.isNotEmpty) _addDirectRow();
      });
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'تعذر تحميل الأصناف والأطراف: $error');
      }
    }
  }

  String _amount(Object? raw) {
    final value = (raw as num?)?.toInt() ?? 0;
    return '${value ~/ 100}.${(value.abs() % 100).toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> _rows(Object? raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
      : [];

  @override
  void initState() {
    super.initState();
    _branch = widget.branchIds.firstOrNull;
    _subscription = RealtimeSyncCoordinator.instance.changes.listen((types) {
      if (types.intersection({
        'invoice',
        'return_invoice',
        'snapshot_restore',
      }).isEmpty) {
        return;
      }
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 120),
        () => unawaited(_load()),
      );
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_draftKey);
      if (!mounted) return;
      if (raw != null) {
        final pending = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        setState(() => _pending = pending);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message =
              'تعذر قراءة الطلب المحفوظ؛ لا تنشئ طلبًا بديلًا قبل المراجعة: $error',
        );
      }
      return; // Fail closed: corrupt pending data must not create a duplicate return.
    }
    if (!mounted) return;
    setState(() => _initializing = false);
    await _loadDirectCatalog();
    await _load();
  }

  Future<void> _load() async {
    if (_branch == null || !mounted) return;
    if (_loading) {
      _reloadRequested = true;
      return;
    }
    final branch = _branch!;
    setState(() => _loading = true);
    try {
      final originals = await _api.originals(
        branch,
        _type,
        _search.text.trim(),
        page: _originalPage,
      );
      final returns = await _api.list(branch, _type, page: _returnPage);
      if (!mounted || branch != _branch) return;
      setState(() {
        _originals = _rows(originals['data']);
        _returns = _rows(returns['data']);
        _originalLast = (originals['last_page'] as num?)?.toInt() ?? 1;
        _returnLast = (returns['last_page'] as num?)?.toInt() ?? 1;
      });
    } on ReturnsApiError catch (error) {
      if (mounted) {
        setState(
          () => _message = error.statusCode == 401
              ? 'انتهت جلسة الدخول. سجّل الدخول مجددًا لحماية بياناتك.'
              : 'تعذر تحديث الفواتير الآن. تحقق من الاتصال ثم اضغط «تحديث».',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'تعذر تحديث الفواتير الآن. تحقق من الاتصال ثم اضغط «تحديث».',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_reloadRequested) {
          _reloadRequested = false;
          unawaited(_load());
        }
      }
    }
  }

  Future<void> _choose(Map<String, dynamic> invoice) async {
    if (_posting || _preparing || _pending != null || _initializing) return;
    final selectionGeneration = ++_selectionGeneration;
    final selectedBranch = _branch;
    try {
      final result = await _api.returnable(invoice['id'].toString());
      if (!mounted ||
          selectionGeneration != _selectionGeneration ||
          selectedBranch != _branch ||
          _preparing ||
          _posting ||
          _pending != null) {
        return;
      }
      for (final controller in _quantities.values) {
        controller.dispose();
      }
      _quantities.clear();
      final items = _rows(result['items']);
      for (final item in items) {
        _quantities[item['id'].toString()] = TextEditingController(text: '0');
      }
      setState(() {
        _selected = Map<String, dynamic>.from(result['invoice'] as Map);
        _selectionRestoreGeneration = (result['restore_generation'] as num?)
            ?.toInt();
        _items = items;
        _message = null;
      });
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _submit() async {
    if (_preparing || _posting || _initializing || !_canPost) return;
    setState(() => _preparing = true);
    try {
      await _prepareAndSubmit();
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر تجهيز الطلب: $error');
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _submitDirect() async {
    if (_preparing ||
        _posting ||
        _initializing ||
        !_canPost ||
        _branch == null) {
      return;
    }
    setState(() => _preparing = true);
    try {
      if (_pending != null) {
        await _sendPending();
        return;
      }
      final items = <Map<String, dynamic>>[];
      for (final row in _directRows) {
        final productId = row['product_id']?.toString() ?? '';
        final quantity = ReturnQuantity.milli(
          (row['quantity'] as TextEditingController).text,
        );
        final price = double.tryParse(
          (row['price'] as TextEditingController).text.trim(),
        );
        if (productId.isEmpty ||
            quantity == null ||
            quantity < 1 ||
            price == null ||
            price < 0) {
          setState(
            () => _message = 'أكمل الصنف والكمية والسعر في جميع سطور المرتجع.',
          );
          return;
        }
        items.add({
          'product_id': productId,
          'quantity_milli': quantity,
          'unit_price_minor': (price * 100).round(),
        });
      }
      if (items.isEmpty || _reason.text.trim().length < 3) {
        setState(
          () => _message =
              'أضف صنفًا واحدًا على الأقل واكتب سببًا واضحًا للمرتجع.',
        );
        return;
      }
      if (_settlement == 'credit' && _directContactId == null) {
        setState(
          () => _message = widget.purchase
              ? 'اختر المورد للمرتجع الآجل.'
              : 'اختر العميل للمرتجع الآجل.',
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            widget.purchase
                ? 'اعتماد مرتجع المشتريات'
                : 'اعتماد مرتجع المبيعات',
          ),
          content: Text(
            _settlement == 'cash'
                ? (widget.purchase
                      ? 'سيُنقص المخزون ويُسجل المبلغ واردًا إلى الصندوق.'
                      : 'سيزيد المخزون ويُسجل المبلغ مصروفًا من الصندوق.')
                : (widget.purchase
                      ? 'سيُنقص المخزون ويخفض مستحقات المورد.'
                      : 'سيزيد المخزون ويخفض رصيد العميل.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ترحيل المرتجع'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final prefs = await SharedPreferences.getInstance();
      var device = prefs.getString('ninesoft.accounting.device_uuid.v1');
      if (device == null || device.isEmpty) {
        device = const Uuid().v4();
        if (!await prefs.setString(
          'ninesoft.accounting.device_uuid.v1',
          device,
        )) {
          if (mounted) {
            setState(
              () => _message = 'تعذر حفظ هوية الجهاز؛ لم يُرسل المرتجع.',
            );
          }
          return;
        }
      }
      final pending = <String, dynamic>{
        'direct': true,
        'branch_id': _branch,
        'body': {
          'branch_id': _branch,
          'type': '${_type}_return',
          'contact_id': _directContactId,
          'device_id': device,
          'local_operation_id': const Uuid().v4(),
          'restore_generation':
              RealtimeSyncCoordinator.instance.restoreGeneration,
          'operation_created_at': DateTime.now().toUtc().toIso8601String(),
          'reason': _reason.text.trim(),
          'settlement_mode': _settlement,
          'refund_channel': _channel,
          'items': items,
        },
      };
      final prefsSaved = await prefs.setString(_draftKey, jsonEncode(pending));
      if (!prefsSaved) {
        if (mounted) {
          setState(
            () => _message = 'تعذر حفظ الطلب محليًا؛ لم يُرسل أي مرتجع.',
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() => _pending = pending);
      await _sendPending();
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _prepareAndSubmit() async {
    if (_pending != null) {
      await _sendPending();
      return;
    }
    if (_selected == null) return;
    final items = <Map<String, dynamic>>[];
    for (final item in _items) {
      final quantity = ReturnQuantity.milli(
        _quantities[item['id'].toString()]!.text,
      );
      final available = (item['returnable_quantity_milli'] as num).toInt();
      if (quantity == null || quantity > available) {
        setState(
          () => _message =
              'كمية غير صحيحة أو تتجاوز المتبقي للصنف ${item['product_name_snapshot']}.',
        );
        return;
      }
      if (quantity > 0) {
        items.add({'original_item_id': item['id'], 'quantity_milli': quantity});
      }
    }
    if (items.isEmpty || _reason.text.trim().length < 3) {
      setState(
        () =>
            _message = 'اختر كمية واحدة على الأقل واكتب سببًا واضحًا للمرتجع.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد ترحيل المرتجع'),
        content: const Text(
          'سيحسب الخادم الخصم والضريبة من الفاتورة الأصلية، ويخفض المديونية أولًا، ثم يسجل رد المال المتبقي عبر القناة المختارة. يؤثر الترحيل في المخزون والقيود ولا يمكن حذفه من هذه الشاشة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('اعتماد المرتجع'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    var device = prefs.getString('ninesoft.accounting.device_uuid.v1');
    if (device == null || device.isEmpty) {
      device = const Uuid().v4();
      if (!await prefs.setString(
        'ninesoft.accounting.device_uuid.v1',
        device,
      )) {
        setState(() => _message = 'تعذر حفظ هوية الجهاز؛ لم يُرسل المرتجع.');
        return;
      }
    }
    if (!mounted) return;
    final pending = <String, dynamic>{
      'invoice_id': _selected!['id'],
      'branch_id': _branch,
      'body': {
        'device_id': device,
        'local_operation_id': const Uuid().v4(),
        'restore_generation':
            _selectionRestoreGeneration ??
            RealtimeSyncCoordinator.instance.restoreGeneration,
        'operation_created_at': DateTime.now().toUtc().toIso8601String(),
        'reason': _reason.text.trim(),
        'refund_channel': _channel,
        'items': items,
      },
    };
    if (!await prefs.setString(_draftKey, jsonEncode(pending))) {
      if (mounted) {
        setState(() => _message = 'تعذر حفظ الطلب محليًا؛ لم يُرسل أي مرتجع.');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _pending = pending);
    await _sendPending();
  }

  Future<void> _sendPending() async {
    if (_pending == null || _posting || !_canPost || _initializing) return;
    final pending = Map<String, dynamic>.from(_pending!);
    setState(() {
      _posting = true;
      _message = null;
    });
    try {
      final body = Map<String, dynamic>.from(pending['body'] as Map);
      final result = pending['direct'] == true
          ? await _api.postDirect(body)
          : await _api.post(pending['invoice_id'].toString(), body);
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.remove(_draftKey)) {
        throw StateError(
          'تعذر تثبيت تأكيد الترحيل محليًا؛ إعادة المحاولة آمنة.',
        );
      }
      if (!mounted) return;
      final invoice = result['invoice'] as Map;
      setState(() {
        _pending = null;
        _selected = null;
        _items = [];
        if (pending['direct'] == true) {
          _disposeDirectRows();
          if (_products.isNotEmpty) _addDirectRow();
        }
        _reason.clear();
        _message =
            'تم الترحيل: ${compactDocumentNumber(invoice['number']?.toString() ?? '')} • الإجمالي ${_amount(invoice['total_minor'])} • رد المال ${_amount(invoice['paid_minor'])} • خفض الدين ${_amount(invoice['due_minor'])}';
      });
      unawaited(RealtimeSyncCoordinator.instance.synchronizeNow());
      await _load();
    } catch (error) {
      // Only explicit rejection responses may unlock a different request. Never replace a timed-out operation ID.
      if (error is ReturnsApiError && error.definitelyRejected) {
        final removed = await (await SharedPreferences.getInstance()).remove(
          _draftKey,
        );
        if (removed && mounted) setState(() => _pending = null);
      }
      if (mounted) setState(() => _message = 'لم يُؤكد الترحيل: $error');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _debounce?.cancel();
    _search.dispose();
    _reason.dispose();
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    _disposeDirectRows();
    super.dispose();
  }

  Widget _sourceInvoicesPanel({required bool desktop}) => NineSoftPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.receipt_long_outlined, color: NizamiColors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'اختر الفاتورة الأصلية',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: 'رقم الفاتورة أو اسم العميل / المورد',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: 'بحث',
              onPressed: () {
                _originalPage = 1;
                unawaited(_load());
              },
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          onSubmitted: (_) {
            _originalPage = 1;
            unawaited(_load());
          },
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: desktop ? 390 : 250,
          child: _originals.isEmpty
              ? const Center(child: Text('لا توجد فواتير قابلة للمرتجع.'))
              : ListView.separated(
                  itemCount: _originals.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 7),
                  itemBuilder: (context, index) {
                    final invoice = _originals[index];
                    final selected = _selected?['id'] == invoice['id'];
                    return Material(
                      color: selected
                          ? NizamiColors.blue.withValues(alpha: .09)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(13),
                      child: ListTile(
                        selected: selected,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                          side: BorderSide(
                            color: selected
                                ? NizamiColors.blue
                                : Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        leading: CircleAvatar(
                          backgroundColor: NizamiColors.blue.withValues(
                            alpha: .1,
                          ),
                          child: const Icon(Icons.receipt_rounded),
                        ),
                        title: Text(
                          compactDocumentNumber(invoice['number'].toString()),
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            fontFamily: 'ArialMTBlack',
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          '${invoice['party_name_snapshot'] ?? 'بدون اسم'}\nالإجمالي ${_amount(invoice['total_minor'])} • مرتجع سابق ${_amount(invoice['returned_minor'])}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.keyboard_return_rounded,
                          color: selected ? NizamiColors.green : null,
                        ),
                        onTap: _pending != null || _posting || _preparing
                            ? null
                            : () => _choose(invoice),
                      ),
                    );
                  },
                ),
        ),
        Row(
          children: [
            Text('صفحة $_originalPage من $_originalLast'),
            const Spacer(),
            IconButton(
              tooltip: 'السابق',
              onPressed: _originalPage > 1 && !_loading
                  ? () {
                      _originalPage--;
                      unawaited(_load());
                    }
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            IconButton(
              tooltip: 'التالي',
              onPressed: _originalPage < _originalLast && !_loading
                  ? () {
                      _originalPage++;
                      unawaited(_load());
                    }
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _directEditor({required bool desktop}) => NineSoftPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NineSoftEntryHeading(
          title: widget.purchase ? 'مرتجع مشتريات مباشر' : 'مرتجع مبيعات مباشر',
          subtitle: 'حدد الأصناف والكميات وطريقة التسوية، ثم اعتمد المستند',
          icon: Icons.assignment_return_rounded,
          status: 'إنشاء مرتجع',
          accent: widget.purchase ? NizamiColors.amber : NizamiColors.red,
        ),
        const SizedBox(height: 14),
        NineSoftEntrySection(
          title: 'الأصناف المرتجعة',
          subtitle: 'تدرج الحقول على الهاتف، وجدول مختصر على الكمبيوتر',
          icon: Icons.widgets_outlined,
          step: '01',
          accent: NizamiColors.blue,
          action: IconButton(
            tooltip: 'إضافة سطر',
            onPressed: _products.isEmpty || _posting
                ? null
                : () => setState(_addDirectRow),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_products.isEmpty)
                const NineSoftEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'لا توجد أصناف متاحة',
                  message:
                      'أضف الأصناف أولًا أو حدّث المزامنة ثم أعد فتح المرتجعات.',
                )
              else ...[
                if (desktop)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: NizamiColors.blue.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 28, child: Text('#')),
                        const Expanded(flex: 4, child: Text('الصنف')),
                        Expanded(
                          flex: desktop ? 2 : 3,
                          child: const Text('الكمية'),
                        ),
                        Expanded(
                          flex: desktop ? 2 : 3,
                          child: const Text('السعر'),
                        ),
                        const SizedBox(width: 42),
                      ],
                    ),
                  ),
                const SizedBox(height: 5),
                for (var index = 0; index < _directRows.length; index++)
                  _directInputRow(index),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _posting ? null : () => setState(_addDirectRow),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('إضافة سطر — أو اضغط Enter بعد السعر'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        NineSoftEntrySection(
          title: 'تسوية المرتجع',
          subtitle: 'اختر نقدًا أو آجلًا، واكتب سبب الإرجاع',
          icon: Icons.account_balance_wallet_outlined,
          step: '02',
          accent: NizamiColors.green,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'cash',
                    label: Text('نقدًا'),
                    icon: Icon(Icons.payments_outlined),
                  ),
                  ButtonSegment(
                    value: 'credit',
                    label: Text('آجل / على الحساب'),
                    icon: Icon(Icons.schedule_rounded),
                  ),
                ],
                selected: {_settlement},
                onSelectionChanged: _posting
                    ? null
                    : (value) => setState(() => _settlement = value.first),
              ),
              if (_settlement == 'credit') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _directContactId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: widget.purchase ? 'المورد' : 'العميل',
                    prefixIcon: Icon(
                      widget.purchase
                          ? Icons.local_shipping_outlined
                          : Icons.person_outline_rounded,
                    ),
                  ),
                  items: _contacts
                      .map(
                        (contact) => DropdownMenuItem(
                          value: contact['id'].toString(),
                          child: Text(
                            contact['name']?.toString() ?? 'بدون اسم',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _posting
                      ? null
                      : (value) => setState(() => _directContactId = value),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _reason,
                enabled: !_posting,
                minLines: 2,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'سبب المرتجع',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              if (_settlement == 'cash') ...[
                DropdownButtonFormField<String>(
                  initialValue: _channel,
                  decoration: InputDecoration(
                    labelText: widget.purchase
                        ? 'استلام المبلغ إلى'
                        : 'رد المبلغ من',
                    prefixIcon: const Icon(
                      Icons.account_balance_wallet_outlined,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('الصندوق')),
                    DropdownMenuItem(value: 'bank', child: Text('البنك')),
                    DropdownMenuItem(value: 'wallet', child: Text('المحفظة')),
                  ],
                  onChanged: _posting
                      ? null
                      : (value) => setState(() => _channel = value ?? 'cash'),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 13),
        NineSoftEntryFooter(
          onSave: _posting || _preparing || _initializing || !_canPost
              ? null
              : _submitDirect,
          enabled: !_posting && !_preparing && !_initializing && _canPost,
          label: widget.purchase
              ? 'ترحيل مرتجع المشتريات'
              : 'ترحيل مرتجع المبيعات',
          icon: Icons.fact_check_outlined,
          note: 'المستند المالي يُعتمد مرة واحدة فقط',
        ),
      ],
    ),
  );

  Widget _directInputRow(int index) {
    final row = _directRows[index];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final productField = DropdownButtonFormField<String>(
          key: ValueKey('return-item-$index'),
          initialValue: row['product_id']?.toString(),
          isExpanded: true,
          decoration: InputDecoration(
            labelText: compact ? 'الصنف المرتجع' : null,
            hintText: 'اختر الصنف',
            isDense: true,
          ),
          items: _products
              .map(
                (product) => DropdownMenuItem(
                  value: product['id'].toString(),
                  child: Text(
                    product['name']?.toString() ?? 'صنف',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: _posting
              ? null
              : (value) {
                  if (value == null) return;
                  final product = _products.firstWhere(
                    (item) => item['id'].toString() == value,
                  );
                  setState(() {
                    row['product_id'] = value;
                    final minor =
                        (product[widget.purchase
                                    ? 'purchase_price_minor'
                                    : 'sale_price_minor']
                                as num?)
                            ?.toInt() ??
                        0;
                    (row['price'] as TextEditingController).text = (minor / 100)
                        .toStringAsFixed(2);
                  });
                },
        );
        final quantity = TextField(
          controller: row['quantity'] as TextEditingController,
          enabled: !_posting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const [latinDigitFormatter],
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            labelText: compact ? 'الكمية' : null,
            isDense: true,
            hintText: '1',
          ),
        );
        final price = TextField(
          controller: row['price'] as TextEditingController,
          enabled: !_posting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const [latinDigitFormatter],
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            labelText: compact ? 'السعر' : null,
            isDense: true,
            hintText: '0.00',
          ),
          onSubmitted: (_) {
            if (index == _directRows.length - 1 && _products.isNotEmpty) {
              setState(_addDirectRow);
            }
          },
        );
        final remove = IconButton(
          tooltip: 'حذف السطر',
          onPressed: _posting || _directRows.length == 1
              ? null
              : () => setState(() {
                  final deleted = _directRows.removeAt(index);
                  (deleted['quantity'] as TextEditingController).dispose();
                  (deleted['price'] as TextEditingController).dispose();
                }),
          icon: const Icon(
            Icons.delete_outline_rounded,
            color: NizamiColors.red,
          ),
        );
        return Padding(
          key: ObjectKey(row),
          padding: const EdgeInsets.only(bottom: 9),
          child: compact
              ? NineSoftEntrySection(
                  title: 'بند مرتجع ${index + 1}',
                  icon: Icons.assignment_return_outlined,
                  step: '${index + 1}',
                  accent: NizamiColors.red,
                  action: remove,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      productField,
                      const SizedBox(height: 10),
                      NineSoftEntryFieldGrid(
                        minFieldWidth: 160,
                        maxColumns: 2,
                        children: [quantity, price],
                      ),
                    ],
                  ),
                )
              : Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(fontFamily: 'ArialMTBlack'),
                      ),
                    ),
                    Expanded(flex: 4, child: productField),
                    const SizedBox(width: 6),
                    Expanded(flex: 2, child: quantity),
                    const SizedBox(width: 6),
                    Expanded(flex: 2, child: price),
                    SizedBox(width: 42, child: remove),
                  ],
                ),
        );
      },
    );
  }

  Widget _returnEditor({required bool desktop}) {
    if (_selected == null || _pending != null) {
      return NineSoftPanel(
        child: NineSoftEmptyState(
          icon: Icons.assignment_return_outlined,
          title: _pending == null
              ? 'اختر فاتورة للبدء'
              : 'يوجد مرتجع بانتظار التأكيد',
          message: _pending == null
              ? 'ستظهر أصناف الفاتورة وكمياتها القابلة للإرجاع هنا.'
              : 'أعد إرسال نفس الطلب المحفوظ؛ لن ينشئ النظام عملية مالية مكررة.',
          action: _pending == null
              ? null
              : FilledButton.icon(
                  onPressed: _posting || !_canPost || _initializing
                      ? null
                      : _sendPending,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('إعادة إرسال الطلب نفسه'),
                ),
        ),
      );
    }
    final rows = <Widget>[];
    for (var index = 0; index < _items.length; index++) {
      final item = _items[index];
      final name = item['product_name_snapshot']?.toString() ?? 'صنف';
      final available =
          ((item['returnable_quantity_milli'] as num).toInt() / 1000)
              .toStringAsFixed(3);
      rows.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: index.isEven
                ? NizamiColors.blue.withValues(alpha: .035)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontFamily: 'ArialMTBlack'),
                ),
              ),
              Expanded(flex: 3, child: Text(name)),
              Expanded(
                child: Text(
                  available,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'ArialMTBlack'),
                ),
              ),
              SizedBox(
                width: desktop ? 150 : 105,
                child: TextField(
                  controller: _quantities[item['id'].toString()],
                  enabled: !_posting && !_preparing && _canPost,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [latinDigitFormatter],
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'المرتجع',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return NineSoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.assignment_return_rounded,
                color: NizamiColors.red,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'مرتجع الفاتورة ${compactDocumentNumber(_selected!['number']?.toString() ?? '')}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const NineSoftEntryHint(
            text:
                'لا يمكن إرجاع كمية أكبر من المتاح في الفاتورة الأصلية. راجع الكميات والتسوية قبل الترحيل.',
            icon: Icons.verified_rounded,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: NizamiColors.blue.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                SizedBox(width: 34, child: Text('#')),
                Expanded(flex: 3, child: Text('الصنف')),
                Expanded(child: Text('المتاح')),
                SizedBox(width: 105, child: Text('كمية الإرجاع')),
              ],
            ),
          ),
          ...rows,
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            enabled: !_posting && !_preparing && _canPost,
            maxLength: 500,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'سبب المرتجع',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: _channel,
            decoration: const InputDecoration(
              labelText: 'طريقة رد المبلغ',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('رد نقدي')),
              DropdownMenuItem(value: 'bank', child: Text('رد بنكي')),
              DropdownMenuItem(value: 'wallet', child: Text('رد عبر المحفظة')),
            ],
            onChanged: _posting || _preparing
                ? null
                : (value) => setState(() => _channel = value ?? 'cash'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _posting || _preparing || _initializing || !_canPost
                ? null
                : _submit,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('مراجعة وترحيل المرتجع'),
          ),
        ],
      ),
    );
  }

  Widget _postedReturnsPanel() => NineSoftPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'المرتجعات المرحلة',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (_returns.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('لا توجد مرتجعات مرحلة بعد.')),
          )
        else
          for (final record in _returns)
            ListTile(
              dense: true,
              leading: const CircleAvatar(
                child: Icon(Icons.keyboard_return_rounded, size: 18),
              ),
              title: SelectableText(
                compactDocumentNumber(record['number'].toString()),
              ),
              subtitle: Text(
                'الإجمالي ${_amount(record['total_minor'])} • رد المال ${_amount(record['paid_minor'])} • خفض الدين ${_amount(record['due_minor'])}',
              ),
            ),
        if (_returns.isNotEmpty)
          Row(
            children: [
              Text('صفحة $_returnPage من $_returnLast'),
              const Spacer(),
              IconButton(
                tooltip: 'السابق',
                onPressed: _returnPage > 1 && !_loading
                    ? () {
                        _returnPage--;
                        unawaited(_load());
                      }
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              IconButton(
                tooltip: 'التالي',
                onPressed: _returnPage < _returnLast && !_loading
                    ? () {
                        _returnPage++;
                        unawaited(_load());
                      }
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            ],
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 980;
    final color = widget.purchase ? NizamiColors.amber : NizamiColors.red;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.purchase ? 'مرتجعات المشتريات' : 'مرتجعات المبيعات',
          ),
          toolbarHeight: desktop ? 0 : null,
          actions: [
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: SafeArea(
          child: NineSoftResponsiveBody(
            child: Column(
              children: [
                NineSoftPageHeader(
                  title: widget.purchase
                      ? 'مرتجعات المشتريات'
                      : 'مرتجعات المبيعات',
                  subtitle:
                      'أدخل المرتجع مباشرة مثل الفاتورة، أو اربطه بفاتورة سابقة عند الحاجة.',
                  icon: Icons.assignment_return_rounded,
                  color: color,
                  actions: [
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('تحديث'),
                    ),
                  ],
                ),
                if (_loading || _posting || _preparing || _initializing) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(),
                ],
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SelectableText(_message!),
                  ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('مرتجع مباشر'),
                      icon: Icon(Icons.edit_note_rounded),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('مرتبط بفاتورة'),
                      icon: Icon(Icons.link_rounded),
                    ),
                  ],
                  selected: {_direct},
                  onSelectionChanged: _posting || _preparing || _pending != null
                      ? null
                      : (value) => setState(() {
                          _direct = value.first;
                          _message = null;
                          if (_direct) unawaited(_loadDirectCatalog());
                        }),
                ),
                if (widget.branchIds.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: DropdownButtonFormField<String>(
                      initialValue: _branch,
                      decoration: const InputDecoration(
                        labelText: 'الفرع',
                        prefixIcon: Icon(Icons.store_rounded),
                      ),
                      items: widget.branchIds
                          .map(
                            (id) => DropdownMenuItem(
                              value: id,
                              child: Text('الفرع $id'),
                            ),
                          )
                          .toList(),
                      onChanged: _posting || _preparing || _pending != null
                          ? null
                          : (value) {
                              setState(() {
                                _branch = value;
                                _selected = null;
                                _items = [];
                                _originalPage = 1;
                                _returnPage = 1;
                              });
                              unawaited(_load());
                            },
                    ),
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: _direct
                      ? ListView(
                          children: [
                            _pending != null
                                ? _returnEditor(desktop: desktop)
                                : _directEditor(desktop: desktop),
                            const SizedBox(height: 12),
                            _postedReturnsPanel(),
                            const SizedBox(height: 90),
                          ],
                        )
                      : desktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 390,
                              child: SingleChildScrollView(
                                child: _sourceInvoicesPanel(desktop: true),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    _returnEditor(desktop: true),
                                    const SizedBox(height: 12),
                                    _postedReturnsPanel(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          children: [
                            _sourceInvoicesPanel(desktop: false),
                            const SizedBox(height: 12),
                            _returnEditor(desktop: false),
                            const SizedBox(height: 12),
                            _postedReturnsPanel(),
                            const SizedBox(height: 90),
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
}
