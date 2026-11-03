import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/ninesoft_confirm_shortcuts.dart';
import '../../theme/ninesoft_ui.dart';
import 'accounting_api.dart';

/// Owner-controlled accounting closing console. Unlike a business-document
/// register, these actions post or lock the actual GL, and are never queued
/// automatically in the background.
class AccountingPeriodsPage extends StatefulWidget {
  const AccountingPeriodsPage({
    super.key,
    required this.token,
    required this.branchIds,
    required this.roleCode,
    this.accountingApi,
  });
  final String token;
  final List<String> branchIds;
  final String roleCode;
  final AccountingApi? accountingApi;

  @override
  State<AccountingPeriodsPage> createState() => _AccountingPeriodsPageState();
}

class _AccountingPeriodsPageState extends State<AccountingPeriodsPage> {
  late final AccountingApi _api =
      widget.accountingApi ?? AccountingApi(token: widget.token);
  final _reason = TextEditingController();
  String? _branch;
  String? _error;
  String? _success;
  DateTime _closedThrough = DateTime.now().subtract(const Duration(days: 1));
  int _year = DateTime.now().year - 1;
  bool _busy = false;
  bool _loading = false;
  Map<String, dynamic> _integrity = const {};
  Map<String, dynamic> _metadata = const {};
  Map<String, dynamic> _consolidated = const {};
  bool _hasPendingYear = false;
  List<Map<String, dynamic>> _locks = const [];
  List<Map<String, dynamic>> _closings = const [];

  bool get _owner => widget.roleCode == 'owner';
  String get _date =>
      '${_closedThrough.year.toString().padLeft(4, '0')}-${_closedThrough.month.toString().padLeft(2, '0')}-${_closedThrough.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _branch = widget.branchIds.firstOrNull;
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final branch = _branch;
    if (branch == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _api.periodLocks(),
        _api.fiscalYearClosures(),
        _api.accountingIntegrity(branch),
        _api.administrationMetadata(),
      ]);
      if (!mounted || _branch != branch) return;
      setState(() {
        _locks = (results[0] as List<Map<String, dynamic>>);
        _closings = (results[1] as List<Map<String, dynamic>>);
        _integrity = results[2] as Map<String, dynamic>;
        _metadata = results[3] as Map<String, dynamic>;
      });
      await _refreshPendingYear();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'تعذر تحميل المطابقة أو الفترات: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _confirm(String heading, String detail) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => NineSoftEnterConfirmScope(
        onConfirm: () => Navigator.pop(context, true),
        child: AlertDialog(
          title: Text(heading),
          content: Text(detail),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('أوافق على التنفيذ'),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  Future<void> _run(
    Future<Map<String, dynamic>> Function() operation,
    String message,
  ) async {
    if (_busy || _branch == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await operation();
      if (!mounted) return;
      setState(() => _success = message);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'فشلت العملية أو تعذر تأكيد استجابة الخادم: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _closePeriod() async {
    if (!_owner || _busy || _branch == null) return;
    final reason = _reason.text.trim();
    if (reason.length < 8) {
      setState(() => _error = 'اكتب سببًا واضحًا لا يقل عن 8 أحرف.');
      return;
    }
    if (_integrity['status'] != 'balanced') {
      setState(
        () => _error =
            'تقرير المطابقة يحتوي فروقًا. لا تقفل فترة قبل معالجة الفروق.',
      );
      return;
    }
    if (!await _confirm(
      'إقفال فترة محاسبية',
      'سيُمنع ترحيل العمليات بتاريخ $_date أو قبله للفرع المحدد. تأكد من تسوية جميع الحركات قبل الإقفال.',
    )) {
      return;
    }
    await _run(
      () => _api.closeAccountingPeriod(
        branchId: _branch!,
        through: _date,
        reason: reason,
        restoreGeneration: (_metadata['restore_generation'] as num).toInt(),
        operationCreatedAt: DateTime.now().toUtc().toIso8601String(),
      ),
      'تم إقفال الفترة مع توثيق السبب.',
    );
  }

  Future<void> _reopenPeriod() async {
    if (!_owner || _busy || _branch == null) return;
    final reason = _reason.text.trim();
    if (reason.length < 8) {
      setState(() => _error = 'اكتب سببًا واضحًا لإعادة الفتح.');
      return;
    }
    if (!await _confirm(
      'إعادة فتح الفترة',
      'ستصبح الفترات غير المقفلة سنويًا قابلة للترحيل مجددًا، مع تسجيل المراجع والسبب.',
    )) {
      return;
    }
    await _run(
      () => _api.reopenAccountingPeriod(
        branchId: _branch!,
        reason: reason,
        restoreGeneration: (_metadata['restore_generation'] as num).toInt(),
        operationCreatedAt: DateTime.now().toUtc().toIso8601String(),
      ),
      'تم فتح الفترة المسموح بها وتوثيق العملية.',
    );
  }

  Future<void> _closeYear() async {
    if (!_owner || _busy || _branch == null) return;
    final branch = _branch!;
    final reason = _reason.text.trim();
    if (reason.length < 8) {
      setState(() => _error = 'أدخل سبب الإقفال السنوي أولًا.');
      return;
    }
    if (_integrity['status'] != 'balanced') {
      setState(
        () => _error = 'قبل إقفال السنة يجب نجاح مطابقة دفتر الأستاذ والمخزون.',
      );
      return;
    }
    if (_closings.any(
      (item) =>
          item['branch_id'] == branch &&
          item['fiscal_year'].toString() == _year.toString(),
    )) {
      setState(() => _error = 'هذه السنة مقفلة بالفعل. راجع سجل الإقفالات.');
      return;
    }
    if (!await _confirm(
      'إقفال السنة المالية $_year',
      'سيُنشأ قيد ترحيل صافي ربح/خسارة السنة إلى الأرباح المرحلة، ويُقفل الترحيل لتواريخ هذه السنة وما قبلها. '
          'لا يمكن التراجع عنه بزر إعادة فتح الفترة. لا تنفذ قبل مطابقة قيود وفواتير السنة.',
    )) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final key = 'ninesoft.accounting.year.pending.$branch.$_year';
    final previous = prefs.getString(key);
    final saved = previous == null ? null : jsonDecode(previous);
    final request = saved is Map
        ? Map<String, dynamic>.from(saved)
        : <String, dynamic>{
            'branch_id': branch,
            'fiscal_year': _year,
            'operation_id': const Uuid().v4(),
            'reason': reason,
            'restore_generation': (_metadata['restore_generation'] as num)
                .toInt(),
            'operation_created_at': DateTime.now().toUtc().toIso8601String(),
          };
    if (previous == null) await prefs.setString(key, jsonEncode(request));
    await _run(() async {
      final answer = await _api.closeFiscalYear(
        branchId: branch,
        year: _year,
        operationId: request['operation_id'].toString(),
        reason: request['reason'].toString(),
        restoreGeneration: (request['restore_generation'] as num).toInt(),
        operationCreatedAt: request['operation_created_at'].toString(),
      );
      await prefs.remove(key);
      return answer;
    }, 'تم ترحيل نتيجة السنة وإقفالها؛ يمكنك مراجعة قيدها والتقارير.');
  }

  String get _pendingYearKey =>
      'ninesoft.accounting.year.pending.${_branch ?? 'none'}.$_year';

  Future<void> _refreshPendingYear() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString(_pendingYearKey) != null;
    if (mounted) setState(() => _hasPendingYear = pending);
  }

  Future<void> _discardPendingYear() async {
    if (_branch == null || _busy) return;
    final branch = _branch!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // A timeout does not mean rollback. Read live server state first.
      final closures = await _api.fiscalYearClosures();
      final closed = closures.any(
        (item) =>
            item['branch_id'] == branch &&
            item['fiscal_year'].toString() == _year.toString(),
      );
      if (closed) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingYearKey);
        if (mounted) {
          setState(
            () => _success =
                'السنة مقفلة على الخادم؛ أزلنا حالة الانتظار المحلية فقط.',
          );
        }
        return;
      }
      if (!mounted) return;
      final accept = await _confirm(
        'إلغاء طلب الإقفال المعلق محليًا',
        'تأكدنا أن السنة ليست مقفلة في حالة الخادم الحالية. قد يكون الطلب السابق لم يصل. '
            'هل تريد إلغاء معرّفه المحلي وإنشاء طلب جديد عند الإقفال التالي؟',
      );
      if (accept) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingYearKey);
        if (mounted) {
          setState(
            () => _success = 'أُلغي الطلب المحلي فقط دون تغيير دفاتر الخادم.',
          );
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'تعذر التحقق من حالة الإقفال على الخادم: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refreshPendingYear();
      await _load();
    }
  }

  Future<void> _loadConsolidated() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.consolidatedBalanceSheet();
      if (mounted) setState(() => _consolidated = result);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'تعذر حساب المركز المالي المجمع: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _minor(dynamic value) {
    final n = int.tryParse(value?.toString() ?? '') ?? 0;
    return '${n ~/ 100}.${(n.abs() % 100).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final lock = _locks.where((r) => r['branch_id'] == _branch).firstOrNull;
    final records = _closings.where((r) => r['branch_id'] == _branch).toList();
    final canAct = _owner && !_busy && !_loading;
    return Scaffold(
      appBar: AppBar(title: const Text('السنوات والفترات المالية')),
      body: SafeArea(
        child: NineSoftResponsiveBody(
          child: ListView(
            children: [
              const NineSoftEntryHeading(
                title: 'السنوات والفترات المالية',
                subtitle: 'المطابقة والإقفال الدوري والسنوي بسجل مراجعة واضح',
                icon: Icons.calendar_month_outlined,
                status: 'إدارة محاسبية',
              ),
              const SizedBox(height: 12),
              NineSoftEntrySection(
                title: 'إدارة الفترة المحاسبية',
                subtitle: 'راجع المطابقة قبل تنفيذ أي إقفال أو إعادة فتح',
                icon: Icons.fact_check_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.branchIds.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: _branch,
                        decoration: const InputDecoration(
                          labelText: 'فرع المحاسبة',
                        ),
                        items: widget.branchIds
                            .map(
                              (id) => DropdownMenuItem(
                                value: id,
                                child: Text(
                                  id,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (v) {
                                setState(() {
                                  _branch = v;
                                  _integrity = const {};
                                });
                                _load();
                              },
                      ),
                    if (_loading) const LinearProgressIndicator(),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_success != null)
                      Text(
                        _success!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'مطابقة الحسابات والمخزون',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'الحالة: ${_integrity['status'] == 'balanced' ? 'متوازن وفق الفحوص المتاحة' : 'يتطلب مراجعة'}',
                    ),
                    Text(
                      'فارق قيمة المخزون عن الأستاذ: ${_minor(_integrity['inventory_difference_minor'])}',
                    ),
                    Text(
                      'حركات مخزون بلا قيمة: ${_integrity['inventory_unvalued_movements'] ?? '-'}',
                    ),
                    Text(
                      'أسطر ذمم بلا طرف: ${_integrity['unassigned_contact_ledger_lines'] ?? '-'}',
                    ),
                    Text(
                      'قيود غير متوازنة: ${(_integrity['journal_entry_errors'] as List?)?.length ?? '-'}',
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || _loading ? null : _load,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('تحديث المطابقة'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'فحص المطابقة للقراءة فقط؛ نجاحه لا يغني عن اختبار الفواتير والأجهزة والبيانات القديمة.',
                    ),
                    const Divider(height: 32),
                    const Text(
                      'الإقفال الدوري',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'الفترة المقفلة حتى: ${lock?['closed_through'] ?? 'غير مقفلة'}',
                    ),
                    NineSoftEntryFieldGrid(
                      maxColumns: 2,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('period-close-date'),
                          onPressed: canAct
                              ? () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _closedThrough,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null && mounted) {
                                    setState(() => _closedThrough = picked);
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.event),
                          label: Text('تاريخ الإقفال: $_date'),
                        ),
                        TextField(
                          key: const Key('period-reason-field'),
                          controller: _reason,
                          enabled: canAct,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'سبب الإجراء (إلزامي، 8 أحرف على الأقل)',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const Key('period-reopen-action'),
                      onPressed:
                          _owner && canAct && lock?['closed_through'] != null
                          ? _reopenPeriod
                          : null,
                      icon: const Icon(Icons.lock_open_outlined),
                      label: const Text('إعادة فتح المسموح'),
                    ),
                    const SizedBox(height: 10),
                    NineSoftEntryFooter(
                      key: const Key('period-close-footer'),
                      label: 'إقفال الفترة',
                      icon: Icons.lock_outline,
                      enabled: _owner && canAct,
                      onSave: _owner && canAct ? _closePeriod : null,
                      note: 'يتطلب الإقفال مطابقة متوازنة وسببًا موثقًا',
                    ),
                    const Divider(height: 32),
                    const Text(
                      'الإقفال السنوي والأرباح المرحلة',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    NineSoftEntryFieldGrid(
                      maxColumns: 2,
                      children: [
                        DropdownButtonFormField<int>(
                          key: const Key('annual-close-year'),
                          initialValue: _year,
                          decoration: const InputDecoration(
                            labelText: 'السنة المالية المنتهية',
                          ),
                          items: [
                            for (
                              var year = DateTime.now().year - 1;
                              year >= DateTime.now().year - 25;
                              year--
                            )
                              DropdownMenuItem(
                                value: year,
                                child: Text('$year'),
                              ),
                          ],
                          onChanged: canAct
                              ? (value) {
                                  if (value != null) {
                                    setState(() => _year = value);
                                    _refreshPendingYear();
                                  }
                                }
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_hasPendingYear)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          'يوجد طلب إقفال سنوي محفوظ غير مؤكد؛ ستُستخدم هويته الأصلية عند إعادة المحاولة.',
                        ),
                      ),
                    NineSoftEntryFooter(
                      key: const Key('annual-close-footer'),
                      label: 'مراجعة ثم إقفال السنة المختارة',
                      icon: Icons.event_available_outlined,
                      enabled: _owner && canAct,
                      onSave: _owner && canAct ? _closeYear : null,
                      note:
                          'ينشئ الإقفال السنوي قيد النتيجة ويثبت سجل المراجعة',
                    ),
                    if (_hasPendingYear)
                      TextButton(
                        onPressed: canAct ? _discardPendingYear : null,
                        child: const Text(
                          'التحقق من الخادم ثم تسوية الطلب السنوي المعلق',
                        ),
                      ),
                    for (final record in records)
                      ListTile(
                        title: Text(
                          'السنة ${record['fiscal_year']} — صافي النتيجة ${_minor(record['net_profit_minor'])}',
                        ),
                        subtitle: Text(
                          'قيد الإقفال: ${record['journal_entry_id'] ?? 'لم يلزم قيد'}',
                        ),
                        leading: const Icon(Icons.check_circle_outline),
                      ),
                    const Divider(height: 32),
                    const Text(
                      'المركز المالي المجمع بين الفروع',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'إلغاء داخلي تقريري لتحويلات المخزون المزدوجة المثبتة فقط، دون تعديل الأستاذ الأصلي.',
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || _loading ? null : _loadConsolidated,
                      icon: const Icon(Icons.account_balance_outlined),
                      label: const Text('عرض المركز المالي المجمع'),
                    ),
                    if (_consolidated.isNotEmpty) ...[
                      Text('الأصول: ${_minor(_consolidated['assets_minor'])}'),
                      Text(
                        'الخصوم: ${_minor(_consolidated['liabilities_minor'])}',
                      ),
                      Text(
                        'فرق التوازن: ${_minor(_consolidated['difference_minor'])}',
                      ),
                      Text(
                        'الإلغاء الداخلي المثبت: ${_minor((_consolidated['consolidation'] as Map?)?['eliminated_minor'])}',
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
