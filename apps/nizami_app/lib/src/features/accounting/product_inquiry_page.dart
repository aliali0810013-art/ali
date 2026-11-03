import 'package:flutter/material.dart';

import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/ninesoft_ui.dart';
import '../../theme/nizami_theme.dart';
import 'accounting_api.dart';

class ProductInquiryPage extends StatefulWidget {
  const ProductInquiryPage({
    required this.token,
    required this.branchIds,
    super.key,
  });

  final String token;
  final List<String> branchIds;

  @override
  State<ProductInquiryPage> createState() => _ProductInquiryPageState();
}

/// Responsive inventory result. It uses the page scroll only and never adds a
/// nested horizontal viewport around product data.
class ProductInquiryResultCard extends StatefulWidget {
  const ProductInquiryResultCard({required this.item, super.key});

  final Map<String, dynamic> item;

  @override
  State<ProductInquiryResultCard> createState() =>
      _ProductInquiryResultCardState();
}

class _ProductInquiryResultCardState extends State<ProductInquiryResultCard> {
  bool _expanded = false;

  String _quantity(dynamic milli, String unit) {
    final value = (int.tryParse(milli?.toString() ?? '') ?? 0) / 1000;
    final text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(3);
    return '$text $unit';
  }

  String _money(dynamic minor) =>
      '${((int.tryParse(minor?.toString() ?? '') ?? 0) / 100).toStringAsFixed(2)} YER';

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final unit = item['unit_name']?.toString() ?? '';
    final warehouses = (item['warehouses'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final last = item['last_purchase'] is Map
        ? Map<String, dynamic>.from(item['last_purchase'] as Map)
        : null;

    final rowId = item['id']?.toString() ?? item['sku']?.toString() ?? '';
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('product-inquiry-$rowId'),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: NizamiColors.amber.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: NizamiColors.amber,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${item['sku'] ?? ''}${(item['barcode']?.toString() ?? '').isEmpty ? '' : ' • ${item['barcode']}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _quantity(item['quantity_milli'], unit),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                  ),
                ],
              ),
              if (_expanded) ...[
                const Divider(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: warehouses
                      .map(
                        (warehouse) => Chip(
                          visualDensity: const VisualDensity(
                            horizontal: -3,
                            vertical: -3,
                          ),
                          avatar: const Icon(
                            Icons.warehouse_outlined,
                            size: 16,
                          ),
                          label: Text(
                            '${warehouse['branch_name'] ?? ''}: ${_quantity(warehouse['quantity_milli'], unit)}',
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 6),
                if (last == null)
                  const Text('لا توجد فاتورة شراء سابقة لهذا الصنف.')
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: NizamiColors.blue.withValues(alpha: .05),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        Text('آخر شراء: ${last['invoice_number'] ?? ''}'),
                        Text('المورد: ${last['supplier_name'] ?? ''}'),
                        Text(
                          'التاريخ: ${(last['occurred_at'] ?? '').toString().split('T').first}',
                        ),
                        Text(
                          'السعر: ${_money(last['unit_price_minor'])}',
                          textDirection: TextDirection.ltr,
                        ),
                        Text(
                          'الصافي: ${_money(last['net_unit_price_minor'])}',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductInquiryPageState extends State<ProductInquiryPage> {
  late final AccountingApi _api = AccountingApi(token: widget.token);
  final _search = TextEditingController();
  String? _branchId;
  List<Map<String, dynamic>> _items = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _branchId = widget.branchIds.firstOrNull;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final branchId = _branchId;
    if (branchId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await _api.productInquiry(
        branchId: branchId,
        query: _search.text.trim(),
      );
      if (mounted) setState(() => _items = values);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('استعلام الصنف والمخزون')),
    body: SafeArea(
      child: NineSoftResponsiveBody(
        child: ListView(
          children: [
            NineSoftEntryHeading(
              title: 'استعلام الصنف',
              subtitle: 'الرصيد حسب المخزن وآخر سعر شراء والمورد والتاريخ',
              icon: Icons.inventory_2_rounded,
              accent: NizamiColors.amber,
              actions: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('تحديث'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            NineSoftEntrySection(
              title: 'البحث في المخزون',
              subtitle:
                  'ابحث بالاسم أو الرمز أو الباركود وحدد الفرع عند الحاجة',
              icon: Icons.search_rounded,
              child: NineSoftEntryFieldGrid(
                maxColumns: 2,
                children: [
                  TextField(
                    controller: _search,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'اسم الصنف أو الرمز أو الباركود',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        onPressed: _load,
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                  if (widget.branchIds.length > 1)
                    DropdownButtonFormField<String>(
                      initialValue: _branchId,
                      decoration: const InputDecoration(
                        labelText: 'الفرع / المخزن',
                      ),
                      items: widget.branchIds
                          .map(
                            (id) =>
                                DropdownMenuItem(value: id, child: Text(id)),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() => _branchId = value);
                        _load();
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            NineSoftEntrySection(
              title: 'نتائج الاستعلام',
              icon: Icons.inventory_2_outlined,
              padding: const EdgeInsets.all(12),
              child: _loading
                  ? const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : _items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('لا توجد أصناف مطابقة.')),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, index) =>
                          ProductInquiryResultCard(item: _items[index]),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
