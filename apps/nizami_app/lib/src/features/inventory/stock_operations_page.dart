import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/ninesoft_ui.dart';
import '../modules/catalog_sync_api.dart';
import '../sync/realtime_sync_coordinator.dart';
import '../sync/stock_operation_outbox.dart';
import 'stock_operations_api.dart';

/// Physical count and branch transfer must post through stock_movements + GL.
/// Historical generic business_documents remain read-only archive notes.
class StockOperationsPage extends StatefulWidget {
  const StockOperationsPage({
    super.key,
    required this.token,
    required this.tenantId,
    required this.branchIds,
    required this.isTransfer,
    required this.canWrite,
  });

  final String token;
  final String tenantId;
  final List<String> branchIds;
  final bool isTransfer;
  final bool canWrite;

  @override
  State<StockOperationsPage> createState() => _StockOperationsPageState();
}

class _StockOperationsPageState extends State<StockOperationsPage> {
  final _quantity = TextEditingController();
  final _unitCost = TextEditingController();
  final _reason = TextEditingController();
  String? _branch;
  String? _destination;
  String? _product;
  List<Map<String, dynamic>> _products = const [];
  bool _loading = false;
  bool _saving = false;
  int _pending = 0;
  String? _error;
  StreamSubscription<Set<String>>? _updates;

  @override
  void initState() {
    super.initState();
    _branch = widget.branchIds.firstOrNull;
    _destination = widget.branchIds.where((id) => id != _branch).firstOrNull;
    unawaited(_load());
    _updates = RealtimeSyncCoordinator.instance.changes.listen((types) {
      if (types.contains('inventory_balance') ||
          types.contains('inventory_adjustment') ||
          types.contains('snapshot_restore') ||
          types.contains('purchase_invoice') ||
          types.contains('invoice')) {
        unawaited(_load());
      }
    });
  }

  @override
  void dispose() {
    _updates?.cancel();
    _quantity.dispose();
    _unitCost.dispose();
    _reason.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _selected {
    for (final value in _products) {
      if (value['id']?.toString() == _product) return value;
    }
    return null;
  }

  StockOperationOutbox? get _outbox =>
      _branch == null ? null : StockOperationOutbox(widget.tenantId, _branch!);

  Future<void> _load() async {
    final branch = _branch;
    if (branch == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await CatalogSyncApi(
        token: widget.token,
      ).list('products', branchId: branch);
      if (!mounted || _branch != branch) return;
      setState(() {
        _products = products
            .where((row) => row['kind']?.toString() == 'stock')
            .toList(growable: false);
        if (!_products.any((row) => row['id']?.toString() == _product)) {
          _product = null;
        }
      });
    } catch (error) {
      if (mounted && _branch == branch) {
        setState(() => _error = 'تعذر تحميل رصيد المخزون المعتمد: $error');
      }
    } finally {
      final queue = StockOperationOutbox(widget.tenantId, branch);
      try {
        final count = await queue.count();
        if (mounted && _branch == branch) setState(() => _pending = count);
      } catch (error) {
        if (mounted && _branch == branch) {
          setState(() => _error = 'تعذر قراءة العمليات المعلقة: $error');
        }
      }
      if (mounted && _branch == branch) setState(() => _loading = false);
    }
  }

  // A decimal string is converted to milli-units exactly, without double.
  static int? parseMilli(String value) {
    final clean = value.trim();
    if (!RegExp(r'^\d{1,9}(?:\.\d{1,3})?$').hasMatch(clean)) return null;
    final parts = clean.split('.');
    final whole = int.parse(parts.first);
    final fraction = parts.length == 1
        ? 0
        : int.parse(parts.last.padRight(3, '0'));
    return whole * 1000 + fraction;
  }

  // Positive money only, to exact integer minor units.
  static int? parseMinor(String value) {
    final clean = value.trim();
    if (!RegExp(r'^\d{1,9}(?:\.\d{1,2})?$').hasMatch(clean)) return null;
    final parts = clean.split('.');
    return int.parse(parts.first) * 100 +
        (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
  }

  Future<void> _submit() async {
    if (_saving ||
        _pending > 0 ||
        !widget.canWrite ||
        _branch == null ||
        _selected == null) {
      return;
    }
    final count = parseMilli(_quantity.text);
    final current = (_selected!['stock_quantity_milli'] as num?)?.toInt();
    final cost = _unitCost.text.trim().isEmpty
        ? null
        : parseMinor(_unitCost.text);
    if (count == null ||
        current == null ||
        (widget.isTransfer &&
            (count == 0 ||
                count > current ||
                _destination == null ||
                _destination == _branch)) ||
        _reason.text.trim().length < 3 ||
        (cost == null && _unitCost.text.trim().isNotEmpty) ||
        (!widget.isTransfer && current == 0 && count > 0 && cost == null)) {
      _message(
        'أدخل الصنف والكمية والسبب بصورة صحيحة. عند زيادة مخزون فارغ يلزم تحديد تكلفة الوحدة.',
      );
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final operation = const Uuid().v4();
    final request = widget.isTransfer
        ? <String, dynamic>{
            'kind': 'stock_transfer',
            'source_branch_id': _branch,
            'destination_branch_id': _destination,
            'product_id': _product,
            'local_operation_id': operation,
            'quantity_milli': count,
            'expected_source_quantity_milli': current,
            'reason': _reason.text.trim(),
            'restore_generation':
                RealtimeSyncCoordinator.instance.restoreGeneration,
            'operation_created_at': now,
          }
        : <String, dynamic>{
            'kind': 'inventory_count',
            'branch_id': _branch,
            'product_id': _product,
            'operation_id': operation,
            'expected_quantity_milli': current,
            'target_quantity_milli': count,
            'valuation_unit_cost_minor': ?cost,
            'reason': _reason.text.trim(),
            'restore_generation':
                RealtimeSyncCoordinator.instance.restoreGeneration,
            'operation_created_at': now,
          };
    setState(() => _saving = true);
    try {
      final queue = _outbox!;
      // Save the operation BEFORE contacting the server. A timeout must never
      // create a second stock movement with a new operation ID.
      await queue.enqueue(request);
      final result = await queue.flush(
        api: StockOperationsApi(token: widget.token),
        currentRestoreGeneration:
            RealtimeSyncCoordinator.instance.restoreGeneration,
        restoreEpoch: RealtimeSyncCoordinator.instance.restoreEpoch,
      );
      if (!mounted) return;
      _quantity.clear();
      _unitCost.clear();
      _reason.clear();
      _message(
        result.sent > 0
            ? 'تم ترحيل العملية إلى المخزون والقيود المحاسبية.'
            : 'حُفظت العملية معلقة بنفس المعرّف، وستُعاد المحاولة تلقائيًا. ${result.error ?? ''}',
      );
      await _load();
    } catch (error) {
      _message('لم تُعتمد العملية؛ راجع التخزين أو الاتصال: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final current = (selected?['stock_quantity_milli'] as num?)?.toInt();
    final caption = widget.isTransfer
        ? 'يُرحَّل التحويل بين فرعين مع حركتي مخزون وقيود متوازنة. لا يمثل نقلًا بين مخزنين داخل الفرع.'
        : 'يُعدّل رصيد الصنف الفعلي بقيد تسوية وحركة مخزون؛ لا يُحفظ كملاحظة غير مرحلة.';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isTransfer
              ? 'تحويل المخزون بين الفروع'
              : 'الجرد والتسويات المحاسبية',
        ),
      ),
      body: SafeArea(
        child: NineSoftResponsiveBody(
          child: ListView(
            children: [
              NineSoftEntryHeading(
                title: widget.isTransfer
                    ? 'تحويل المخزون بين الفروع'
                    : 'الجرد والتسويات المحاسبية',
                subtitle: caption,
                icon: widget.isTransfer
                    ? Icons.swap_horiz_rounded
                    : Icons.inventory_outlined,
                status: 'حركة مخزون',
              ),
              const SizedBox(height: 12),
              NineSoftEntrySection(
                title: 'بيانات الحركة',
                subtitle: 'حدد المصدر والصنف والكمية ثم راجع سبب الحركة',
                icon: Icons.edit_note_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_pending > 0)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.schedule_rounded),
                          title: Text(
                            '$_pending حركة مخزون بانتظار تأكيد الخادم',
                          ),
                          subtitle: const Text(
                            'لا تعِد إدخال العملية؛ يحتفظ النظام بمعرفها عند إعادة المحاولة.',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.sync_rounded),
                            onPressed: _saving
                                ? null
                                : () async {
                                    await RealtimeSyncCoordinator.instance
                                        .synchronizeNow();
                                    await _load();
                                  },
                          ),
                        ),
                      ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_loading) const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    NineSoftEntryFieldGrid(
                      maxColumns: 2,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _branch,
                          decoration: const InputDecoration(
                            labelText: 'الفرع المصدر',
                          ),
                          items: widget.branchIds
                              .map(
                                (id) => DropdownMenuItem(
                                  value: id,
                                  child: Text(id),
                                ),
                              )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (value) {
                                  setState(() {
                                    _branch = value;
                                    _product = null;
                                    _products = const [];
                                    _destination = widget.branchIds
                                        .where((id) => id != value)
                                        .firstOrNull;
                                  });
                                  unawaited(_load());
                                },
                        ),
                        if (widget.isTransfer)
                          DropdownButtonFormField<String>(
                            initialValue: _destination,
                            decoration: const InputDecoration(
                              labelText: 'الفرع المستلم',
                            ),
                            items: widget.branchIds
                                .where((id) => id != _branch)
                                .map(
                                  (id) => DropdownMenuItem(
                                    value: id,
                                    child: Text(id),
                                  ),
                                )
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (value) =>
                                      setState(() => _destination = value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _product,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'الصنف المخزني',
                      ),
                      items: _products
                          .map(
                            (row) => DropdownMenuItem(
                              value: row['id'].toString(),
                              child: Text(
                                row['name']?.toString() ?? '',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (id) => setState(() => _product = id),
                    ),
                    if (selected != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        current == null
                            ? 'الرصيد غير متاح'
                            : 'الرصيد المتاح: ${(current / 1000).toStringAsFixed(3)} ${selected['unit_name'] ?? ''}',
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _quantity,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: InputDecoration(
                        labelText: widget.isTransfer
                            ? 'كمية التحويل'
                            : 'الكمية الفعلية بعد الجرد',
                      ),
                    ),
                    if (!widget.isTransfer) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _unitCost,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'تكلفة الوحدة إذا كان المخزون صفرًا',
                          helperText:
                              'تقييم الفروقات من متوسط التكلفة عند وجود رصيد مقيم',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reason,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'سبب الحركة (لأثر المراجعة)',
                      ),
                    ),
                    const SizedBox(height: 20),
                    NineSoftEntryFooter(
                      label: _saving ? 'جار الترحيل' : 'اعتماد وترحيل الحركة',
                      enabled:
                          !_loading &&
                          !_saving &&
                          _pending == 0 &&
                          widget.canWrite &&
                          _products.isNotEmpty,
                      onSave:
                          !_loading &&
                              !_saving &&
                              _pending == 0 &&
                              widget.canWrite &&
                              _products.isNotEmpty
                          ? _submit
                          : null,
                      note:
                          'تُرحّل الحركة إلى المخزون والقيد المحاسبي بنفس العملية',
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _loading || _saving ? null : _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('تحديث الأرصدة المعتمدة'),
                    ),
                    if (!widget.canWrite)
                      const Text('هذه الجلسة لا تملك صلاحية ترحيل المخزون.'),
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
