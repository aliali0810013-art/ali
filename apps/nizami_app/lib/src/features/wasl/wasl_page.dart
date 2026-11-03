import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import '../../theme/ninesoft_entry_ui.dart';
import 'wasl_api.dart';

class WaslPage extends StatefulWidget {
  const WaslPage({
    super.key,
    required this.token,
    required this.tenantName,
    required this.branchIds,
    this.invoiceNumber,
    this.api,
  });
  final String token;
  final String tenantName;
  final List<String> branchIds;
  final String? invoiceNumber;
  final WaslApi? api;
  @override
  State<WaslPage> createState() => _WaslPageState();
}

class _WaslPageState extends State<WaslPage> {
  late String _branchId = widget.branchIds.isEmpty
      ? 'MAIN'
      : widget.branchIds.first;
  late WaslApi _api =
      widget.api ?? WaslApi(token: widget.token, branchId: _branchId);
  Timer? _poll;
  Timer? _noticePoll;
  bool _loading = false;
  bool _pairing = false;
  bool _noticesLoading = false;
  Map<String, dynamic> _permissions = const {};
  Map<String, dynamic> _status = const {};
  List<WaslTransfer> _records = const [];
  String? _error;
  String _filter = 'all';

  bool _allowed(String action) => _permissions[action] == true;
  // Backward compatibility for installations created before the dedicated
  // unlink permission existed.
  bool get _canUnlink => _allowed('unlink_devices') || _allowed('pair_devices');
  bool get _linked => _status['linked'] == true;
  bool get _active => widget.api != null || WaslApi.enabled;

  @override
  void initState() {
    super.initState();
    if (_active) {
      _refresh();
      _poll = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _refresh(silent: true),
      );
      // Webhooks store new notices locally; this lightweight poll reads only
      // the local NineSoft inbox and never runs a full WASL synchronization.
      _noticePoll = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _refreshNotices(),
      );
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _noticePoll?.cancel();
    super.dispose();
  }

  Future<void> _refreshNotices() async {
    if (_noticesLoading || !_allowed('view_transfers')) return;
    _noticesLoading = true;
    try {
      final records = await _api.transfers();
      if (!mounted) return;
      final known = _records.map((item) => item.id).toSet();
      final fresh = records.where((item) => !known.contains(item.id)).toList();
      if (fresh.isNotEmpty && _records.isNotEmpty) {
        final newest = fresh.first;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'وصل إشعار تحويل جديد ${_arrivalLabel(newest.receivedAt)}',
            ),
          ),
        );
      }
      setState(() => _records = _newestFirst(records));
    } catch (_) {
      // The 30-second status refresh reports connectivity errors. Keep this
      // frequent inbox check quiet and non-blocking.
    } finally {
      _noticesLoading = false;
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (!silent) _error = null;
    });
    try {
      final permissions = await _api.getCapabilities();
      // A user without view permission must not request protected status/data.
      final canView = permissions['view_transfers'] == true;
      final status = canView ? await _api.getStatus() : <String, dynamic>{};
      final records = canView ? await _api.transfers() : <WaslTransfer>[];
      if (!mounted) return;
      final recent =
          _records.isNotEmpty &&
          records.any((r) => !_records.any((old) => old.id == r.id));
      if (recent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تحويل بنكي جديد - للمراجعة')),
        );
      }
      setState(() {
        _permissions = permissions;
        _status = status;
        _records = _newestFirst(records);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = {..._status, 'server_reachable': false};
          _error = _message(e);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pair() async {
    if (_pairing || !_allowed('pair_devices')) return;
    if (_linked) {
      _showError(
        'هذا الفرع مرتبط بالفعل بتطبيق وَصْل. لا يحتاج إلى باركود جديد.',
      );
      return;
    }
    setState(() {
      _pairing = true;
      _error = null;
    });
    try {
      final data = await _api.newPairingQr();
      if (!mounted) return;
      final encoded = data['qr_png_base64']?.toString();
      if (encoded == null || encoded.isEmpty) {
        throw const WaslApiError('لم يرجع الخادم صورة QR.');
      }
      final bytes = base64Decode(encoded);
      final pairingId = data['pairing_id']?.toString();
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('رمز ربط مؤقت - استخدام واحد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.memory(
                bytes,
                width: 220,
                height: 220,
                gaplessPlayback: true,
              ),
              const SizedBox(height: 12),
              const Text(
                'افتح WASL على الهاتف وسجّل الدخول ثم وافق على ربط هذه النسخة. صلاحية الرمز 3 دقائق.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
      if (pairingId != null && pairingId.isNotEmpty) {
        for (var attempt = 0; attempt < 12; attempt++) {
          final state = await _api.pairingStatus(pairingId);
          if (state['linked'] == true) break;
          await Future<void>.delayed(const Duration(seconds: 5));
        }
      }
      await _refresh();
    } catch (e) {
      _showError(_message(e));
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
  }

  Future<void> _sync() async {
    if (!_allowed('sync_transfers')) return;
    if (!_linked) {
      _showError('اربط الجهاز أولاً بواسطة QR ثم نفّذ المزامنة.');
      return;
    }
    try {
      await _api.sync();
      await _refresh();
    } catch (e) {
      _showError(_message(e));
    }
  }

  Future<void> _unlink() async {
    if (!_canUnlink || _loading) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('فصل جهاز وَصْل'),
        content: const Text(
          'سيتوقف هذا الفرع عن استقبال الإشعارات من الجهاز الحالي. يمكنك الربط مجددًا برمز QR جديد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('فصل الجهاز'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    setState(() => _loading = true);
    try {
      await _api.unlink();
      if (!mounted) return;
      setState(() {
        _status = {..._status, 'linked': false};
        _error = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم فصل جهاز وَصْل.')));
      await _refresh(silent: true);
    } catch (e) {
      _showError(_message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _match(WaslTransfer item) async {
    final number = widget.invoiceNumber;
    if (number == null || !_allowed('match_invoice')) return;
    try {
      await _api.matchInvoice(transferId: item.id, invoiceNumber: number);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم إرسال طلب المطابقة للمراجعة. لم تُعتمد الدفعة تلقائيًا.',
            ),
          ),
        );
      }
    } catch (e) {
      _showError(_message(e));
    }
  }

  Future<void> _review(WaslTransfer item) async {
    if (!_allowed('approve_payment')) return;
    final reason = TextEditingController();
    String? choice;
    try {
      choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('مراجعة تحويل مطابق مبدئيًا'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'رسالة SMS وحدها ليست دليل وصول الأموال. الاعتماد اليدوي يتطلب تحققًا مستقلاً من كشف الحساب وسند قبض عبر الخادم.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'سبب القرار وطريقة التحقق (8 حروف على الأقل)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'reject'),
              child: const Text('رفض'),
            ),
            if (_allowed('create_receipt'))
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, 'manual_approve'),
                child: const Text('اعتماد يدوي وإصدار سند قبض'),
              ),
          ],
        ),
      );
      if (choice == null) return;
      if (reason.text.trim().length < 8) {
        _showError('يجب كتابة سبب مفصل للقرار قبل المتابعة.');
        return;
      }
      await _api.review(
        transferId: item.id,
        decision: choice,
        reason: reason.text.trim(),
      );
      await _refresh();
    } catch (e) {
      _showError(_message(e));
    } finally {
      reason.dispose();
    }
  }

  void _showError(String error) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  String _message(Object error) => error is WaslApiError
      ? error.message
      : 'تعذر إكمال العملية. تحقق من الاتصال ثم أعد المحاولة.';

  Future<void> _details(WaslTransfer item) async {
    if (!_allowed('view_raw_sms')) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إشعار التحويل الأصلي'),
        content: SelectableText(item.body ?? 'النص غير متاح من الخادم.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteNotice(WaslTransfer item) async {
    if (!_allowed('approve_payment')) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف إشعار التحويل'),
        content: const Text(
          'سيُحذف الإشعار من خادم NineSoft ومن جميع النسخ المتزامنة. لا يمكن التراجع عن هذه العملية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await _api.deleteNotice(item.id);
      if (!mounted) return;
      setState(
        () => _records = _records.where((r) => r.id != item.id).toList(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الإشعار من الخادم.')),
      );
    } catch (e) {
      _showError(_message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final color = const Color(0xFF4B45CA);
    final entries = _records
        .where((r) => _filter == 'all' || r.state == _filter)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('التحويلات البنكية'),
        actions: [
          IconButton(
            onPressed: _active ? _refresh : null,
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            NineSoftEntryHeading(
              title: 'وَصْل | WASL',
              subtitle: !_active
                  ? 'التكامل معطل حتى تهيئة خادم NineSoft'
                  : !_allowed('view_transfers')
                  ? 'لا توجد صلاحية لعرض تحويلات وَصْل'
                  : _loading && _status.isEmpty
                  ? 'جاري التحقق من اتصال خادم وَصْل...'
                  : _status['server_reachable'] == false
                  ? 'خادم وَصْل غير متصل - حالة الجهاز غير مؤكدة'
                  : _status['linked'] == true
                  ? 'خادم وَصْل متصل - الجهاز مرتبط'
                  : 'خادم وَصْل متصل - لا يوجد جهاز مرتبط',
              status: widget.tenantName,
              icon: Icons.account_balance_rounded,
              accent: color,
            ),
            const SizedBox(height: 18),
            if (widget.branchIds.length > 1)
              DropdownButtonFormField<String>(
                initialValue: _branchId,
                decoration: const InputDecoration(labelText: 'الفرع'),
                items: widget.branchIds
                    .map((id) => DropdownMenuItem(value: id, child: Text(id)))
                    .toList(),
                onChanged: (value) {
                  if (value == null || value == _branchId) return;
                  setState(() {
                    _branchId = value;
                    _api =
                        widget.api ??
                        WaslApi(token: widget.token, branchId: value);
                    _records = const [];
                  });
                  _refresh();
                },
              ),
            if (!_active)
              const _Info(
                text:
                    'هذه واجهة تكامل جاهزة للتطوير. لا يمكن استقبال رسائل حقيقية أو إنشاء سند قبض قبل تثبيت طبقة Laravel وتفعيلها على الخادم.',
              ),
            if (_error != null) _Info(text: _error!),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 12),
            NineSoftEntrySection(
              title: 'الاتصال والأجهزة',
              subtitle: 'الربط والمزامنة حسب صلاحيات الحساب الحالي',
              icon: Icons.phonelink_rounded,
              child: Material(
                color: Colors.transparent,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: Color(0xFF32A079),
                      ),
                      title: const Text('ربط جهاز استقبال الرسائل'),
                      subtitle: const Text('QR مؤقت وبموافقة مالك اشتراك WASL'),
                      trailing: _pairing
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_left),
                      enabled:
                          _active &&
                          _allowed('pair_devices') &&
                          !_linked &&
                          !_pairing,
                      onTap: _pair,
                    ),
                    if (_active && _canUnlink)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFC74646),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _loading || !_linked ? null : _unlink,
                            icon: const Icon(Icons.link_off_rounded),
                            label: Text(
                              _linked
                                  ? 'فصل جهاز وَصْل'
                                  : 'لا يوجد جهاز وَصْل مرتبط',
                            ),
                          ),
                        ),
                      ),
                    const Divider(height: 1, indent: 18, endIndent: 18),
                    ListTile(
                      leading: const Icon(
                        Icons.phonelink_rounded,
                        color: Color(0xFF665AF0),
                      ),
                      title: const Text('المحافظ والأجهزة'),
                      subtitle: Text(
                        'آخر مزامنة: ${_status['last_sync_at'] ?? 'غير متوفرة'}',
                      ),
                    ),
                    if (_active && _allowed('sync_transfers'))
                      ListTile(
                        leading: const Icon(
                          Icons.cloud_sync_rounded,
                          color: Color(0xFF2A8EAC),
                        ),
                        title: const Text('مزامنة التحويلات'),
                        enabled: !_loading && _linked,
                        onTap: _sync,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'التحويلات والإشعارات',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in const [
                    ('all', 'الكل'),
                    ('sms_received', 'واردة'),
                    ('preliminary_match', 'مطابقة مبدئيًا'),
                    ('needs_review', 'تحتاج مراجعة'),
                    ('confirmed', 'مؤكدة'),
                  ])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        selected: _filter == entry.$1,
                        onSelected: (_) => setState(() => _filter = entry.$1),
                        label: Text(entry.$2),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 38,
                      color: Color(0xFF8795A5),
                    ),
                    SizedBox(height: 14),
                    Text('لا توجد تحويلات للعرض'),
                    Text(
                      'لن تُعتبر الرسالة البنكية دفعة مؤكدة بمجرد استلامها.',
                    ),
                  ],
                ),
              ),
            for (final item in entries)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _allowed('view_raw_sms') ? () => _details(item) : null,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: color.withValues(alpha: .1),
                          child: const Icon(
                            Icons.notifications_active_rounded,
                            color: Color(0xFF4B45CA),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.amount} ${item.currency}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(item.source),
                              const SizedBox(height: 7),
                              Row(
                                children: [
                                  const Icon(Icons.schedule_rounded, size: 17),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(_arrivalLabel(item.receivedAt)),
                                  ),
                                ],
                              ),
                              if (item.reference?.isNotEmpty == true) ...[
                                const SizedBox(height: 5),
                                Text('المرجع: ${item.reference}'),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                _statusLabel(item.state),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.state == 'preliminary_match' &&
                                _allowed('approve_payment'))
                              TextButton(
                                onPressed: () => _review(item),
                                child: const Text('مراجعة'),
                              )
                            else if (widget.invoiceNumber != null &&
                                _allowed('match_invoice') &&
                                item.state == 'sms_received')
                              TextButton(
                                onPressed: () => _match(item),
                                child: const Text('مطابقة'),
                              ),
                            if (_allowed('approve_payment'))
                              IconButton(
                                tooltip: 'حذف الإشعار',
                                onPressed: () => _deleteNotice(item),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.redAccent,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const _Info(
              text:
                  'الأصل: رسالة SMS لا تثبت وصول الأموال. الاعتماد المالي وسند القبض يتمان فقط عبر سيرفر المحاسبة وصلاحياته وسجل التدقيق.',
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String state) => switch (state) {
    'confirmed' => 'مؤكد بمصدر رسمي',
    'manually_approved' => 'اعتماد يدوي',
    'preliminary_match' => 'مطابقة مبدئية',
    'rejected' => 'مرفوض',
    'needs_review' => 'يحتاج مراجعة',
    _ => 'إشعار تحويل مستلم',
  };

  List<WaslTransfer> _newestFirst(List<WaslTransfer> records) {
    final sorted = records.toList();
    sorted.sort((a, b) {
      final left = DateTime.tryParse(a.receivedAt);
      final right = DateTime.tryParse(b.receivedAt);
      if (left != null && right != null) return right.compareTo(left);
      return b.id.compareTo(a.id);
    });
    return sorted;
  }

  String _arrivalLabel(String raw) {
    final instant = DateTime.tryParse(raw);
    // NineSoft displays WASL notices in Yemen time consistently, regardless
    // of the browser/device time zone. Yemen is UTC+03:00 year-round.
    final parsed = instant?.toUtc().add(const Duration(hours: 3));
    if (parsed == null) return 'وصل الآن';
    final now = DateTime.now();
    final sameDay =
        parsed.year == now.year &&
        parsed.month == now.month &&
        parsed.day == now.day;
    final yesterday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));
    final previousDay =
        parsed.year == yesterday.year &&
        parsed.month == yesterday.month &&
        parsed.day == yesterday.day;
    final hourValue = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
    final hour = hourValue.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    final second = parsed.second.toString().padLeft(2, '0');
    final period = parsed.hour < 12 ? 'ص' : 'م';
    final day = sameDay
        ? 'اليوم'
        : previousDay
        ? 'أمس'
        : '${parsed.year}/${parsed.month.toString().padLeft(2, '0')}/${parsed.day.toString().padLeft(2, '0')}';
    return 'وصل $day الساعة $hour:$minute:$second $period';
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFDA8A31)),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}
