import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/formatters/latin_digit_formatter.dart';
import '../../theme/ninesoft_confirm_shortcuts.dart';
import '../../theme/ninesoft_entry_ui.dart';

import 'administration_api.dart';

class AdministrationPage extends StatefulWidget {
  const AdministrationPage({
    super.key,
    required this.token,
    required this.tenantName,
    required this.showUsers,
    required this.roleCode,
    this.api,
  });
  final String token;
  final String tenantName;
  final bool showUsers;
  final String roleCode;
  final AdministrationApi? api;
  @override
  State<AdministrationPage> createState() => _AdministrationPageState();
}

class _AdministrationPageState extends State<AdministrationPage> {
  static const _permissionLabels = <String, String>{
    'catalog.read': 'عرض الأصناف',
    'catalog.write': 'إضافة وتعديل الأصناف',
    'contacts.read': 'عرض العملاء والموردين',
    'contacts.write': 'إضافة وتعديل العملاء والموردين',
    'invoices.read': 'عرض الفواتير السابقة',
    'invoices.create': 'إنشاء فواتير مبيعات ومشتريات',
    'invoices.update': 'تعديل الفواتير',
    'invoices.delete': 'حذف الفواتير',
    'documents.read': 'عرض السندات والمستندات',
    'documents.create': 'إنشاء السندات والمستندات',
    'documents.update': 'تعديل السندات والمستندات',
    'documents.delete': 'حذف السندات والمستندات',
    'receipts.read': 'عرض سندات القبض',
    'receipts.create': 'إنشاء سند قبض',
    'receipts.void': 'إلغاء سند قبض',
    'payments.read': 'عرض سندات الصرف',
    'payments.create': 'إنشاء سند صرف',
    'payments.void': 'إلغاء سند صرف',
    'branches.read': 'عرض الفرع المصرح به',
    'branch.identity.update': 'تعديل شعار وبيانات الفرع المصرح به',
    'wasl.view_transfers': 'عرض تحويلات وَصْل',
    'wasl.view_raw_sms': 'عرض نص رسالة التحويل',
    'wasl.pair_devices': 'ربط نسخة المحاسبة بتطبيق وَصْل',
    'wasl.unlink_devices': 'إلغاء ربط نسخة المحاسبة من وَصْل',
    'wasl.sync_transfers': 'مزامنة تحويلات وَصْل',
    'wasl.match_invoice': 'مطابقة التحويل مع فاتورة',
    'wasl.approve_payment': 'اعتماد مطابقة التحويل بعد المراجعة',
    'wasl.create_receipt': 'إنشاء سند قبض بعد الاعتماد',
    'wasl.void_receipt': 'إلغاء سند قبض مرتبط بتحويل',
  };
  late final AdministrationApi _api;
  List<Map<String, dynamic>> _branches = const [];
  List<Map<String, dynamic>> _users = const [];
  bool _loading = true;

  bool get _isOwner => widget.roleCode == 'owner';

  Widget _permissionsEditor(
    Set<String> selected,
    void Function(void Function()) update,
  ) {
    final permissionKeys = _permissionLabels.keys.toSet();
    final allSelected = permissionKeys.every(selected.contains);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('صلاحيات الفرع أو الموظف'),
      subtitle: Text('محدد ${selected.length} صلاحيات'),
      children: [
        CheckboxListTile(
          key: const Key('administration-all-permissions'),
          dense: true,
          value: allSelected,
          title: const Text('جميع الصلاحيات'),
          subtitle: const Text('حدد الكل أو ألغِ تحديد الكل بضغطة واحدة'),
          onChanged: (value) => update(() {
            if (value == true) {
              selected.addAll(permissionKeys);
            } else {
              selected.removeAll(permissionKeys);
            }
          }),
        ),
        const Divider(height: 1),
        for (final entry in _permissionLabels.entries)
          CheckboxListTile(
            dense: true,
            value: selected.contains(entry.key),
            title: Text(entry.value),
            onChanged: (value) => update(() {
              value == true
                  ? selected.add(entry.key)
                  : selected.remove(entry.key);
            }),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? AdministrationApi(token: widget.token);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final branchesOrCopies = widget.showUsers
          ? await _api.branches()
          : await _api.customerCopies();
      final users = widget.showUsers
          ? await _api.users()
          : const <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _branches = branchesOrCopies;
          _users = users;
        });
      }
    } catch (error) {
      _message(_clean(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _clean(Object value) =>
      value.toString().replaceFirst('Exception: ', '');

  bool _isValidPassword(String value) => value.isNotEmpty;

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  DateTime _expiry(int amount, String unit, [DateTime? from]) {
    final start = from != null && from.isAfter(DateTime.now())
        ? from
        : DateTime.now();
    return unit == 'days'
        ? start.add(Duration(days: amount))
        : DateTime(start.year, start.month + amount, start.day);
  }

  Future<void> _addCustomerCopy() async {
    if (!_isOwner) {
      _message('إنشاء نسخ العملاء متاح للمالك الأساسي فقط.');
      return;
    }
    final name = TextEditingController(),
        slug = TextEditingController(),
        address = TextEditingController(),
        phone = TextEditingController(),
        username = TextEditingController(),
        password = TextEditingController(),
        duration = TextEditingController(text: '1');
    var unit = 'months';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('نسخة عميل مستقلة مع بيانات الدخول'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'اسم نسخة العميل أو المنشأة',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: slug,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    decoration: const InputDecoration(
                      labelText: 'رمز النسخة لتسجيل الدخول',
                      hintText: 'مثال: alharthi',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: address,
                    decoration: const InputDecoration(labelText: 'العنوان'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: const [latinDigitFormatter],
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    style: const TextStyle(fontFamily: 'ArialMTBlack'),
                    decoration: const InputDecoration(
                      labelText: 'رقم هاتف العميل',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: username,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'كلمة المرور'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: duration,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [latinDigitFormatter],
                          decoration: const InputDecoration(labelText: 'المدة'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: unit,
                          items: const [
                            DropdownMenuItem(value: 'days', child: Text('يوم')),
                            DropdownMenuItem(
                              value: 'months',
                              child: Text('شهر'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setDialogState(() => unit = v);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isEmpty) {
      _message('اكتب اسم نسخة العميل أولاً.');
      return;
    }
    if (!RegExp(
      r'^[a-z0-9][a-z0-9-]*$',
    ).hasMatch(slug.text.trim().toLowerCase())) {
      _message('رمز النسخة يقبل حروف إنجليزية صغيرة وأرقام وشرطة فقط.');
      return;
    }
    if (username.text.trim().length < 3) {
      _message('اسم المستخدم يجب أن يكون 3 أحرف على الأقل.');
      return;
    }
    if (!_isValidPassword(password.text)) {
      _message('اكتب كلمة المرور.');
      return;
    }
    try {
      final amount = int.tryParse(duration.text) ?? 1;
      final expires = _expiry(amount.clamp(1, 120), unit);
      final copy = await _api.createCustomerCopy(
        name: name.text,
        slug: slug.text,
        ownerUsername: username.text,
        ownerName: name.text,
        password: password.text,
        accessExpiresAt: expires,
        address: address.text,
        phone: phone.text,
      );
      await Clipboard.setData(
        ClipboardData(
          text:
              'ناين سوفت - نسخة عميل مستقلة\nالمنشأة: ${copy['name']}\nرمز النسخة: ${copy['slug']}\nالهاتف: ${phone.text.trim()}\nاسم المستخدم: ${username.text.trim()}\nكلمة المرور: ${password.text}\nالصلاحية حتى: ${expires.toString().split(' ').first}\nhttps://ninesoft.qodynex.tech',
        ),
      );
      _message('تم إنشاء نسخة عميل مستقلة ونسخ بيانات دخولها للمشاركة.');
      await _load();
    } catch (error) {
      _message(_clean(error));
    }
  }

  Future<void> _addUser() async {
    if (!_isOwner) {
      _message('إضافة المستخدمين وتحديد صلاحياتهم متاح للمالك الأساسي فقط.');
      return;
    }
    if (_branches.isEmpty) {
      _message('أنشئ فرعاً أولاً.');
      return;
    }
    final name = TextEditingController(),
        username = TextEditingController(),
        password = TextEditingController();
    final selected = <String>{_branches.first['id'].toString()};
    var role = 'manager';
    final permissions = <String>{
      'catalog.read',
      'contacts.read',
      'invoices.read',
      'documents.read',
    };
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (pageContext, update) => Scaffold(
            appBar: AppBar(toolbarHeight: 0),
            body: SafeArea(
              child: NineSoftResponsiveBody(
                child: ListView(
                  children: [
                    const NineSoftEntryHeading(
                      title: 'إضافة مستخدم',
                      subtitle: 'بيانات الدخول والدور والفروع والصلاحيات',
                      status: 'مستخدم جديد',
                      icon: Icons.person_add_alt_1_rounded,
                      accent: NizamiColors.blue,
                    ),
                    const SizedBox(height: 12),
                    NineSoftEntrySection(
                      title: 'بيانات المستخدم',
                      subtitle: 'الحساب والدور ونطاق الوصول',
                      icon: Icons.manage_accounts_outlined,
                      step: '01',
                      accent: NizamiColors.blue,
                      child: Column(
                        children: [
                          NineSoftEntryFieldGrid(
                            minFieldWidth: 220,
                            maxColumns: 2,
                            children: [
                              TextField(
                                controller: name,
                                decoration: const InputDecoration(
                                  labelText: 'الاسم',
                                ),
                              ),
                              TextField(
                                controller: username,
                                decoration: const InputDecoration(
                                  labelText: 'اسم المستخدم',
                                ),
                              ),
                              TextField(
                                controller: password,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'كلمة المرور',
                                ),
                              ),
                              DropdownButtonFormField<String>(
                                initialValue: role,
                                decoration: const InputDecoration(
                                  labelText: 'الدور',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'manager',
                                    child: Text('مدير'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'accountant',
                                    child: Text('محاسب'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'cashier',
                                    child: Text('أمين صندوق'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'sales',
                                    child: Text('مبيعات'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'purchases',
                                    child: Text('مشتريات'),
                                  ),
                                ],
                                onChanged: (v) => update(() {
                                  if (v != null) role = v;
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              'الفروع',
                              style: Theme.of(pageContext)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          for (final b in _branches)
                            CheckboxListTile(
                              value: selected.contains(b['id'].toString()),
                              title: Text(b['name'].toString()),
                              onChanged: (v) => update(() {
                                v == true
                                    ? selected.add(b['id'].toString())
                                    : selected.remove(b['id'].toString());
                              }),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    NineSoftEntrySection(
                      title: 'الصلاحيات',
                      subtitle: 'حدد الوحدات والإجراءات المتاحة لهذا المستخدم',
                      icon: Icons.admin_panel_settings_outlined,
                      step: '02',
                      accent: NizamiColors.purple,
                      child: _permissionsEditor(permissions, update),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                Navigator.pop(pageContext, false),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('إلغاء'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: selected.isEmpty
                                ? null
                                : () => Navigator.pop(pageContext, true),
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('إنشاء المستخدم'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isEmpty) {
      _message('اكتب اسم المستخدم أولاً.');
      return;
    }
    if (username.text.trim().length < 3) {
      _message('اسم المستخدم يجب أن يكون 3 أحرف على الأقل.');
      return;
    }
    if (!_isValidPassword(password.text)) {
      _message('اكتب كلمة المرور.');
      return;
    }
    try {
      await _api.createUser(
        username: username.text,
        displayName: name.text,
        password: password.text,
        roleCode: role,
        branchIds: selected.toList(),
        permissions: permissions.toList(),
      );
      _message('تم إنشاء المستخدم.');
      await _load();
    } catch (e) {
      _message(_clean(e));
    }
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    if (!_isOwner) {
      _message('تعديل كلمات المرور والصلاحيات متاح للمالك الأساسي فقط.');
      return;
    }
    final password = TextEditingController(),
        duration = TextEditingController(text: '1');
    var unit = 'months';
    final permissions = (user['permissions'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (pageContext, update) => Scaffold(
            appBar: AppBar(toolbarHeight: 0),
            body: SafeArea(
              child: NineSoftResponsiveBody(
                child: ListView(
                  children: [
                    NineSoftEntryHeading(
                      title: 'تعديل ${user['display_name']}',
                      subtitle: 'كلمة المرور ومدة الوصول والصلاحيات',
                      status: user['username']?.toString() ?? 'مستخدم',
                      icon: Icons.manage_accounts_rounded,
                      accent: NizamiColors.blue,
                    ),
                    const SizedBox(height: 12),
                    NineSoftEntrySection(
                      title: 'الوصول',
                      subtitle: 'غيّر كلمة المرور أو مدد مدة الحساب',
                      icon: Icons.lock_clock_outlined,
                      step: '01',
                      accent: NizamiColors.blue,
                      child: NineSoftEntryFieldGrid(
                        minFieldWidth: 220,
                        maxColumns: 2,
                        children: [
                          TextField(
                            controller: password,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'كلمة مرور جديدة (اختياري)',
                            ),
                          ),
                          TextField(
                            controller: duration,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [latinDigitFormatter],
                            decoration: const InputDecoration(
                              labelText: 'تمديد المدة',
                            ),
                          ),
                          DropdownButtonFormField<String>(
                            initialValue: unit,
                            decoration: const InputDecoration(
                              labelText: 'وحدة المدة',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'days',
                                child: Text('يوم'),
                              ),
                              DropdownMenuItem(
                                value: 'months',
                                child: Text('شهر'),
                              ),
                            ],
                            onChanged: (v) => update(() {
                              if (v != null) unit = v;
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    NineSoftEntrySection(
                      title: 'الصلاحيات',
                      subtitle: 'تعديل صلاحيات الوصول إلى وحدات النظام',
                      icon: Icons.admin_panel_settings_outlined,
                      step: '02',
                      accent: NizamiColors.purple,
                      child: _permissionsEditor(permissions, update),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                Navigator.pop(pageContext, false),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('إلغاء'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: () =>
                                Navigator.pop(pageContext, true),
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('حفظ التعديلات'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (ok != true) return;
    if (password.text.isNotEmpty && !_isValidPassword(password.text)) {
      _message('اكتب كلمة المرور الجديدة.');
      return;
    }
    try {
      final previous = DateTime.tryParse(
        user['access_expires_at']?.toString() ?? '',
      );
      await _api.updateUser(
        user['id'].toString(),
        password: password.text,
        accessExpiresAt: _expiry(
          int.tryParse(duration.text) ?? 1,
          unit,
          previous,
        ),
        permissions: permissions.toList(),
      );
      _message('تم تحديث كلمة المرور والمدة.');
      await _load();
    } catch (e) {
      _message(_clean(e));
    }
  }

  Future<void> _shareLogin(Map<String, dynamic> user) async {
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مشاركة بيانات الدخول'),
        content: TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'كلمة مرور جديدة للمشاركة',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تحديث ونسخ البيانات'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!_isValidPassword(password.text)) {
      _message('اكتب كلمة المرور.');
      return;
    }
    await _api.updateUser(user['id'].toString(), password: password.text);
    final expiry =
        user['access_expires_at']?.toString().split('T').first ??
        'بدون مدة محددة';
    await Clipboard.setData(
      ClipboardData(
        text:
            'نظام NineSoft\nالرابط: https://ninesoft.qodynex.tech\nاسم المستخدم: ${user['username']}\nكلمة المرور: ${password.text}\nالصلاحية حتى: $expiry',
      ),
    );
    _message('تم تحديث كلمة المرور ونسخ بيانات الدخول كاملة للمشاركة.');
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => NineSoftEnterConfirmScope(
        onConfirm: () => Navigator.pop(context, true),
        child: AlertDialog(
          title: const Text('حذف المستخدم'),
          content: Text(
            'سيتم إيقاف وحذف حساب ${user['display_name']}. هل أنت متأكد؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteUser(user['id'].toString());
      await _load();
      _message('تم حذف المستخدم وإغلاق جلساته.');
    } catch (error) {
      _message(_clean(error));
    }
  }

  Future<void> _stopCustomerCopy(Map<String, dynamic> copy) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => NineSoftEnterConfirmScope(
        onConfirm: () => Navigator.pop(c, true),
        child: AlertDialog(
          title: const Text('إيقاف نسخة العميل'),
          content: Text(
            'سيتم إيقاف نسخة ${copy['name']} وكل جلساتها، مع إبقاء بياناتها محفوظة للاستعادة. هل أنت متأكد؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('إيقاف النسخة'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await _api.stopCustomerCopy(copy['id'].toString());
        _message('تم إيقاف نسخة العميل وجلساتها.');
        await _load();
      } catch (e) {
        _message(_clean(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(toolbarHeight: 0),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
              children: [
                NineSoftEntryHeading(
                  title: widget.showUsers
                      ? 'إدارة المستخدمين'
                      : 'إدارة نسخ العملاء',
                  subtitle: widget.showUsers
                      ? 'الحسابات والصلاحيات ومدد الوصول في مكان واحد'
                      : 'كل عميل في منشأة مستقلة ببيانات ومزامنة ونسخ احتياطية منفصلة',
                  status: widget.tenantName,
                  icon: widget.showUsers
                      ? Icons.manage_accounts_outlined
                      : Icons.store_mall_directory_outlined,
                  actions: _isOwner
                      ? [
                          FilledButton.icon(
                            key: const Key('administration-create-action'),
                            onPressed: widget.showUsers
                                ? _addUser
                                : _addCustomerCopy,
                            icon: const Icon(Icons.add),
                            label: Text(
                              widget.showUsers
                                  ? 'مستخدم جديد'
                                  : 'نسخة عميل جديدة',
                            ),
                          ),
                        ]
                      : const [],
                ),
                const SizedBox(height: 14),
                NineSoftEntrySection(
                  title: widget.showUsers
                      ? 'حسابات المستخدمين'
                      : 'قائمة نسخ العملاء',
                  subtitle: widget.showUsers
                      ? '${_users.length} حساب مسجل'
                      : '${_branches.length} نسخة عميل مسجلة',
                  icon: widget.showUsers
                      ? Icons.people_alt_outlined
                      : Icons.account_tree_outlined,
                  child: Column(
                    children: widget.showUsers
                        ? _users.map(_userCard).toList(growable: false)
                        : _branches
                              .map(_customerCopyCard)
                              .toList(growable: false),
                  ),
                ),
              ],
            ),
          ),
  );

  Widget _userCard(Map<String, dynamic> user) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
      title: Text(user['display_name'].toString()),
      subtitle: Text('${user['username']}\n${_expiryLabel(user)}'),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') _editUser(user);
          if (value == 'share') _shareLogin(user);
          if (value == 'delete') _deleteUser(user);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('تعديل المدة والصلاحيات')),
          PopupMenuItem(value: 'share', child: Text('مشاركة بيانات الدخول')),
          PopupMenuItem(value: 'delete', child: Text('حذف المستخدم')),
        ],
      ),
    ),
  );

  Widget _customerCopyCard(Map<String, dynamic> copy) {
    final owner = copy['owner'] is Map
        ? Map<String, dynamic>.from(copy['owner'] as Map)
        : const <String, dynamic>{};
    final isActive = copy['active'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            isActive ? Icons.store_outlined : Icons.pause_circle_outline,
          ),
        ),
        title: Text(copy['name'].toString()),
        subtitle: Text(
          'رمز النسخة: ${copy['slug']}\nالمستخدم: ${owner['username'] ?? 'غير متوفر'} · ${_expiryLabel(owner)}',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'stop') _stopCustomerCopy(copy);
          },
          itemBuilder: (_) => isActive
              ? const [
                  PopupMenuItem(
                    value: 'stop',
                    child: Text('إيقاف نسخة العميل'),
                  ),
                ]
              : const [],
        ),
      ),
    );
  }

  String _expiryLabel(Map<String, dynamic> user) {
    final raw = user['access_expires_at']?.toString();
    return raw == null
        ? 'بدون مدة محددة'
        : 'الصلاحية حتى ${raw.split('T').first}';
  }
}
