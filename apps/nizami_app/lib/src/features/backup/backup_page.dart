import 'dart:convert';
import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/ninesoft_confirm_shortcuts.dart';
import 'backup_api.dart';
import '../sync/realtime_sync_coordinator.dart';

String backupErrorMessage(
  Object error, {
  String fallback =
      'تعذر إكمال العملية. تحقق من الاتصال بالخادم ثم أعد المحاولة.',
}) {
  final value = error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceFirst(RegExp(r'^Bad state:\s*'), '')
      .trim();
  final normalized = value.toLowerCase();
  if (value.isEmpty ||
      value.startsWith('Instance of') ||
      value.contains('minified:') ||
      normalized == 'server error' ||
      normalized == 'internal server error' ||
      RegExp(r'\bhttp\s*5\d\d\b').hasMatch(normalized)) {
    return fallback;
  }
  return value;
}

class BackupPage extends StatefulWidget {
  const BackupPage({required this.token, this.api, super.key});
  final String token;
  final BackupApi? api;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  late final BackupApi _api;
  List<ServerBackup> _items = const [];
  bool _loading = true;
  bool _creating = false;
  bool _synchronizing = false;
  StreamSubscription<Set<String>>? _syncSubscription;
  String? _restoringName;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? BackupApi(token: widget.token);
    _load();
    _syncSubscription = RealtimeSyncCoordinator.instance.changes.listen((
      types,
    ) {
      if (types.contains('sync_failure') || types.contains('sync_recovered')) {
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final items = await _api.list();
      if (mounted) setState(() => _items = items);
    } catch (error) {
      _message(backupErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      await _api.create();
      await _load();
      _message('تم إنشاء نسخة احتياطية معزولة للمؤسسة على الخادم.');
    } catch (error) {
      _message(backupErrorMessage(error));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _download(ServerBackup item) async {
    try {
      final body = await _api.download(item.name);
      final location = await getSaveLocation(suggestedName: item.name);
      if (location == null) return;
      final file = XFile.fromData(
        utf8.encode(body),
        mimeType: 'application/json',
        name: item.name,
      );
      await file.saveTo(location.path);
      _message('تم تنزيل النسخة الاحتياطية.');
    } catch (error) {
      _message(backupErrorMessage(error));
    }
  }

  Future<void> _syncNow() async {
    if (_synchronizing || _creating) return;
    setState(() => _synchronizing = true);
    try {
      final synchronized = await RealtimeSyncCoordinator.instance
          .synchronizeNow();
      if (!synchronized) {
        _message(
          'تعذرت المزامنة الآن. تحقق من اتصال الخادم ثم أعد المحاولة بعد لحظات.',
        );
        return;
      }
      _message(
        'تم فحص التغييرات الجديدة. السجلات المعلقة يعاد إرسالها تلقائيًا.',
      );
    } catch (error) {
      _message(
        backupErrorMessage(
          error,
          fallback:
              'تعذرت المزامنة الآن. تحقق من اتصال الخادم ثم أعد المحاولة بعد لحظات.',
        ),
      );
    } finally {
      if (mounted) setState(() => _synchronizing = false);
    }
  }

  Future<void> _restore(ServerBackup item) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => NineSoftEnterConfirmScope(
        onConfirm: () => Navigator.pop(dialogContext, true),
        child: AlertDialog(
          title: const Text('استعادة النسخة الاحتياطية'),
          content: const Text(
            'ستُستبدل السجلات المحاسبية والمستندات بالنسخة المختارة. سيبقى شعار وكليشة الفروع والمستخدمون وكتالوج الأصناف اليمنية كما هي.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.restore_rounded),
              label: const Text('استعادة الآن'),
            ),
          ],
        ),
      ),
    );
    if (approved != true) return;
    setState(() => _restoringName = item.name);
    try {
      await _api.restore(item.name);
      await _load();
      _message('تمت الاستعادة بنجاح. حدّث الأقسام لعرض السجلات المستعادة.');
    } catch (error) {
      _message(backupErrorMessage(error));
    } finally {
      if (mounted) setState(() => _restoringName = null);
    }
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 700;
    final totalBytes = _items.fold<int>(0, (sum, item) => sum + item.size);
    return Scaffold(
    appBar: AppBar(toolbarHeight: 0),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _creating ? null : _create,
      icon: _creating
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cloud_upload_outlined),
      label: const Text('نسخة الآن'),
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(phone ? 10 : 16, phone ? 10 : 16, phone ? 10 : 16, 100),
        children: [
          NineSoftEntryHeading(
            title: 'المزامنة والنسخ الاحتياطي',
            subtitle: phone
                ? 'حماية البيانات والمزامنة بين النسخ'
                : 'نسخ مؤسسية معزولة واستعادة محمية بسجل واضح',
            status: RealtimeSyncCoordinator.instance.connectionHealthMessage,
            icon: Icons.cloud_sync_outlined,
            actions: [
              OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('تحديث'),
              ),
            ],
          ),
          SizedBox(height: phone ? 8 : 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final latest = _items.isEmpty
                  ? 'لا توجد'
                  : DateFormat('MM/dd HH:mm').format(_items.first.createdAt.toLocal());
              final values = [
                ('حالة المزامنة', _synchronizing ? 'تعمل الآن' : 'جاهزة', Icons.sync_rounded, const Color(0xFF20A56B)),
                ('آخر نسخة', latest, Icons.schedule_rounded, const Color(0xFF1689F8)),
                ('المساحة', '${(totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB', Icons.storage_rounded, const Color(0xFF7652D6)),
                ('عدد النسخ', '${_items.length}', Icons.inventory_2_outlined, const Color(0xFFF09A20)),
              ];
              final gap = phone ? 6.0 : 10.0;
              final width = (constraints.maxWidth - gap * 3) / 4;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in values)
                    SizedBox(
                      width: width,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: phone ? 4 : 9,
                          vertical: phone ? 8 : 11,
                        ),
                        decoration: BoxDecoration(
                          color: item.$4.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(phone ? 10 : 14),
                          border: Border.all(color: item.$4.withValues(alpha: .13)),
                        ),
                        child: Column(
                          children: [
                            Icon(item.$3, color: item.$4, size: phone ? 18 : 22),
                            SizedBox(height: phone ? 4 : 6),
                            Text(
                              item.$2,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: item.$4,
                                fontSize: phone ? 9.5 : 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.$1,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: TextStyle(
                                fontSize: phone ? 8 : 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          SizedBox(height: phone ? 8 : 14),
          NineSoftEntrySection(
            title: phone ? 'جدولة المزامنة والنسخ' : 'حماية بيانات المنشأة',
            subtitle: phone ? 'المزامنة والنسخة اليومية' : 'المزامنة والنسخ اليومية تعملان ضمن المؤسسة الحالية',
            icon: Icons.verified_user_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      color: Color(0xFF118E73),
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'نسخ احتياطية معزولة لكل مؤسسة',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'يحفظ الخادم نسخة يومية الساعة 02:30، ويمكن للمالك إنشاء نسخة وتنزيلها من جميع نسخ النظام.',
                ),
                const SizedBox(height: 8),
                Text(
                  'آخر نسخة: ${_items.isEmpty ? 'لا توجد بعد' : DateFormat('yyyy/MM/dd HH:mm').format(_items.first.createdAt.toLocal())}',
                ),
                const SizedBox(height: 14),
                Text(
                  RealtimeSyncCoordinator.instance.connectionHealthMessage,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _synchronizing ? null : _syncNow,
                    icon: _synchronizing
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: const Text('مزامنة التغييرات الآن'),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: phone ? 8 : 12),
          NineSoftEntrySection(
            title: 'النسخ الاحتياطية',
            subtitle: '${_items.length} نسخة متاحة على الخادم',
            icon: Icons.inventory_2_outlined,
            child: Column(
              children: [
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(30),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_items.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: Text('لا توجد نسخ احتياطية بعد.')),
                    ),
                  )
                else
                  for (final item in _items)
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.cloud_done_outlined),
                        ),
                        title: Text(
                          DateFormat(
                            'yyyy/MM/dd  HH:mm',
                          ).format(item.createdAt.toLocal()),
                        ),
                        subtitle: Text(
                          '${(item.size / 1024).toStringAsFixed(1)} KB • محفوظة على الخادم',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'استعادة',
                              onPressed: _restoringName == null
                                  ? () => _restore(item)
                                  : null,
                              icon: _restoringName == item.name
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.restore_rounded),
                            ),
                            IconButton(
                              tooltip: 'تنزيل',
                              onPressed: () => _download(item),
                              icon: const Icon(Icons.download_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }
}
