import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/ninesoft_entry_ui.dart';
import 'quarantined_operation_store.dart';

class QuarantineReviewPage extends StatefulWidget {
  const QuarantineReviewPage({
    super.key,
    required this.tenantId,
    required this.reviewer,
    required this.isOwner,
  });

  final String tenantId;
  final String reviewer;
  final bool isOwner;

  @override
  State<QuarantineReviewPage> createState() => _QuarantineReviewPageState();
}

class _QuarantineReviewPageState extends State<QuarantineReviewPage> {
  late final QuarantinedOperationStore _store;
  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> _audit = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store = QuarantinedOperationStore(widget.tenantId);
    _load();
  }

  Future<void> _load() async {
    final items = await _store.list();
    final audit = await _store.auditLog();
    if (!mounted) return;
    setState(() {
      _items = items.reversed.toList(growable: false);
      _audit = audit.reversed.toList(growable: false);
      _loading = false;
    });
  }

  Future<void> _decide(Map<String, dynamic> item, String decision) async {
    if (!widget.isOwner) return;
    await _store.resolve(
      operationId: item['operation_id']?.toString() ?? '',
      decision: decision,
      reviewer: widget.reviewer,
      note: decision == 'discard'
          ? 'Discarded after restore review; no automatic repost.'
          : 'Kept in quarantine for later accounting review.',
    );
    await _load();
  }

  Future<void> _export() async {
    final report = const JsonEncoder.withIndent('  ').convert({
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'tenant_id': widget.tenantId,
      'quarantined_operations': _items,
      'review_audit': _audit,
    });
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نسخ تقرير المراجعة بصيغة JSON.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('مراجعة العمليات المحجوزة'),
      actions: [
        IconButton(
          onPressed: _export,
          tooltip: 'تصدير تقرير المراجعة',
          icon: const Icon(Icons.file_download_outlined),
        ),
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        NineSoftEntryHeading(
          title: 'مراجعة العمليات المحجوزة',
          subtitle: 'قرارات موثقة للعمليات التي لم تُرحّل تلقائيًا',
          status: widget.isOwner ? 'صلاحية المالك' : 'عرض محمي',
          icon: Icons.shield_outlined,
        ),
        const SizedBox(height: 14),
        if (!widget.isOwner)
          const NineSoftEntrySection(
            title: 'صلاحية غير متاحة',
            subtitle: 'هذه الصفحة متاحة لمالك النظام فقط',
            icon: Icons.lock_outline_rounded,
            child: Text(
              'سجّل الدخول بحساب المالك لمراجعة العمليات واتخاذ القرار.',
            ),
          )
        else if (_loading)
          const Padding(
            padding: EdgeInsets.all(36),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          NineSoftEntrySection(
            title: 'قائمة المراجعة',
            subtitle: '${_items.length} عملية محجوزة',
            icon: Icons.fact_check_outlined,
            child: Column(
              children: [
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.shield_outlined),
                    title: Text('لا يوجد زر إعادة إرسال جماعي'),
                    subtitle: Text(
                      'أي تصحيح محاسبي يجب إنشاؤه كعملية جديدة بمعرّف مستقل بعد المراجعة.',
                    ),
                  ),
                ),
                for (final item in _items)
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(
                        '${item['kind'] ?? 'operation'} • ${item['operation_id'] ?? ''}',
                      ),
                      subtitle: Text(
                        '${item['reason'] ?? ''}\n${item['quarantined_at'] ?? ''}',
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                            const JsonEncoder.withIndent(
                              '  ',
                            ).convert(item['payload']),
                          ),
                        ),
                        OverflowBar(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () => _decide(item, 'keep'),
                              icon: const Icon(Icons.lock_clock_outlined),
                              label: const Text('إبقاء للمراجعة'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _decide(item, 'discard'),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('استبعاد دون ترحيل'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'سجل قرارات المراجعة (${_audit.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final row in _audit)
                  ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: Text(
                      '${row['decision'] ?? ''} • ${row['operation_id'] ?? ''}',
                    ),
                    subtitle: Text(
                      '${row['reviewer'] ?? ''} • ${row['reviewed_at'] ?? ''}',
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
