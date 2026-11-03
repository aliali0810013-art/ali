import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/ninesoft_confirm_shortcuts.dart';
import 'whatsapp_api.dart';

class WhatsappPage extends StatefulWidget {
  const WhatsappPage({
    required this.branchIds,
    required this.token,
    this.api,
    super.key,
  });

  final List<String> branchIds;
  final String token;
  final WhatsappApi? api;

  @override
  State<WhatsappPage> createState() => _WhatsappPageState();
}

class _WhatsappPageState extends State<WhatsappPage> {
  late final WhatsappApi _api;
  late String _branchId;
  WhatsappStatus? _status;
  bool _loading = false;
  Timer? _statusTimer;

  List<String> get _branches =>
      widget.branchIds.isEmpty ? const ['MAIN'] : widget.branchIds;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? WhatsappApi(token: widget.token);
    _branchId = _branches.first;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _statusTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refresh(silent: true),
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final status = await _api.status(_branchId);
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (!silent) _show(error.toString());
    } finally {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    setState(() => _loading = true);
    try {
      final status = await _api.connect(_branchId);
      if (mounted) setState(() => _status = status);
    } catch (error) {
      _show(error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => NineSoftEnterConfirmScope(
        onConfirm: () => Navigator.pop(context, true),
        child: AlertDialog(
          title: const Text('فصل واتساب هذا الفرع؟'),
          content: const Text(
            'سيُحذف ربط الجهاز من الخادم، ويلزم مسح QR جديد لإعادة الاتصال.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('تراجع'),
            ),
            FilledButton(
              key: const ValueKey('confirm-disconnect-whatsapp'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('فصل الجهاز'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      final status = await _api.disconnect(_branchId);
      if (mounted) setState(() => _status = status);
    } catch (error) {
      _show(error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Uint8List? _qrBytes() {
    final source = _status?.qrCode;
    if (source == null || source.isEmpty) return null;
    try {
      return base64Decode(
        source.contains(',') ? source.split(',').last : source,
      );
    } catch (_) {
      return null;
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message.replaceFirst('Exception: ', ''))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final qr = _qrBytes();
    final connected = _status?.connected ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('ربط واتساب بالفروع')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NineSoftEntryHeading(
                    title: 'ربط واتساب',
                    subtitle: 'جلسة مستقلة وآمنة لكل فرع من فروع المنشأة',
                    status: 'قنوات التواصل',
                    icon: Icons.chat_outlined,
                    actions: _loading
                        ? const [
                            SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ]
                        : [
                            FilledButton.icon(
                              key: const ValueKey('connect-whatsapp'),
                              onPressed: connected ? _refresh : _connect,
                              icon: Icon(
                                connected
                                    ? Icons.refresh_rounded
                                    : Icons.qr_code_scanner_rounded,
                              ),
                              label: Text(
                                connected
                                    ? 'تحديث الحالة'
                                    : qr == null
                                    ? 'إنشاء رمز QR'
                                    : 'تجديد رمز QR',
                              ),
                            ),
                            if (connected)
                              OutlinedButton.icon(
                                key: const ValueKey('disconnect-whatsapp'),
                                onPressed: _disconnect,
                                icon: const Icon(Icons.link_off_rounded),
                                label: const Text('فصل الجهاز'),
                              ),
                          ],
                  ),
                  const SizedBox(height: 14),
                  NineSoftEntrySection(
                    title: 'اختيار الفرع',
                    subtitle: 'يُطبق الربط على الفرع المحدد فقط',
                    icon: Icons.store_mall_directory_outlined,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _branchId,
                      decoration: const InputDecoration(
                        labelText: 'الفرع',
                        prefixIcon: Icon(Icons.store_rounded),
                      ),
                      items: [
                        for (var i = 0; i < _branches.length; i++)
                          DropdownMenuItem(
                            value: _branches[i],
                            child: Text('الفرع ${i + 1}'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _branchId = value;
                          _status = null;
                        });
                        _refresh();
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  NineSoftEntrySection(
                    title: connected ? 'حالة الاتصال' : 'إنشاء جلسة الربط',
                    subtitle: connected
                        ? 'الجلسة جاهزة لإرسال المستندات'
                        : 'امسح رمز QR من واتساب على الهاتف',
                    icon: connected
                        ? Icons.verified_outlined
                        : Icons.qr_code_2_rounded,
                    child: Column(
                      children: [
                        Icon(
                          connected
                              ? Icons.verified_rounded
                              : Icons.qr_code_2_rounded,
                          size: 54,
                          color: connected
                              ? const Color(0xFF22B968)
                              : Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          connected
                              ? 'واتساب هذا الفرع متصل'
                              : 'اربط واتساب هذا الفرع',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          connected
                              ? 'أصبح زر إرسال الفاتورة جاهزًا لهذا الفرع.'
                              : 'من الهاتف: واتساب ← الأجهزة المرتبطة ← ربط جهاز، ثم امسح الرمز.',
                          textAlign: TextAlign.center,
                        ),
                        if (qr != null && !connected) ...[
                          const SizedBox(height: 18),
                          Container(
                            color: Colors.white,
                            padding: const EdgeInsets.all(12),
                            child: Image.memory(qr, width: 260, height: 260),
                          ),
                          const SizedBox(height: 10),
                          const Text('يتجدد الرمز تلقائيًا عند طلبه من جديد.'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline_rounded),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'كل فرع يملك جلسة مستقلة على الخادم. لا يستطيع أي فرع استخدام أو مشاهدة جلسة فرع آخر.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
