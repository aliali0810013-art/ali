import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../../core/formatters/latin_digit_formatter.dart';
import '../../theme/ninesoft_entry_ui.dart';

import '../../settings/business_identity_store.dart';
import 'identity_api.dart';

class IdentitySettingsPage extends StatefulWidget {
  const IdentitySettingsPage({
    required this.branchIds,
    required this.tenantName,
    this.tenantId,
    required this.token,
    this.api,
    super.key,
  });

  final List<String> branchIds;
  final String tenantName;
  final String? tenantId;
  final String token;
  final IdentityApi? api;

  @override
  State<IdentitySettingsPage> createState() => _IdentitySettingsPageState();
}

class _IdentitySettingsPageState extends State<IdentitySettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _store = BusinessIdentityStore.instance;
  late String _branchId;
  late final IdentityApi _api;
  late final TextEditingController _name;
  late final TextEditingController _nameEn;
  late final TextEditingController _tagline;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _email;
  late final TextEditingController _header;
  late final TextEditingController _footer;
  Uint8List? _logo;
  int _color = 0xFF123E78;
  double _logoScale = 1.0;

  List<String> get _branches =>
      widget.branchIds.isEmpty ? const ['MAIN'] : widget.branchIds;

  @override
  void initState() {
    super.initState();
    _branchId = _branches.first;
    _api = widget.api ?? IdentityApi(token: widget.token);
    _name = TextEditingController();
    _nameEn = TextEditingController();
    _tagline = TextEditingController();
    _phone = TextEditingController();
    _address = TextEditingController();
    _email = TextEditingController();
    _header = TextEditingController();
    _footer = TextEditingController();
    _loadBranch();
    _syncBranch();
  }

  Future<void> _syncBranch() async {
    try {
      final profile = await _api.load(
        _branchId,
        widget.tenantId ?? widget.tenantName,
      );
      _store.save(profile);
      if (mounted) setState(_loadBranch);
    } catch (_) {
      // Keep the cached identity available while offline.
    }
  }

  void _loadBranch() {
    final profile = _store.profileFor(
      _branchId,
      widget.tenantId ?? widget.tenantName,
      displayName: widget.tenantName,
    );
    _name.text = profile.businessName;
    _nameEn.text = profile.businessNameEn;
    _tagline.text = profile.tagline;
    _phone.text = profile.phone;
    _address.text = profile.address;
    _email.text = profile.email;
    _header.text = profile.header;
    _footer.text = profile.footer;
    _logo = profile.logoBytes;
    _color = profile.primaryColorValue;
    _logoScale = profile.logoScale;
  }

  @override
  void dispose() {
    _name.dispose();
    _nameEn.dispose();
    _tagline.dispose();
    _phone.dispose();
    _address.dispose();
    _email.dispose();
    _header.dispose();
    _footer.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    const group = XTypeGroup(
      label: 'صور الشعار',
      extensions: ['png', 'jpg', 'jpeg', 'webp'],
      mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 3 * 1024 * 1024) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حجم الشعار يجب ألا يتجاوز 3 ميجابايت.')),
      );
      return;
    }
    if (mounted) {
      setState(() => _logo = bytes);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final current = _store.profileFor(
      _branchId,
      widget.tenantId ?? widget.tenantName,
      displayName: widget.tenantName,
    );
    final profile = current.copyWith(
      businessName: _name.text.trim(),
      businessNameEn: _nameEn.text.trim(),
      tagline: _tagline.text.trim(),
      phone: _phone.text.trim(),
      address: _address.text.trim(),
      email: _email.text.trim(),
      header: _header.text.trim(),
      footer: _footer.text.trim(),
      primaryColorValue: _color,
      logoScale: _logoScale,
      logoBytes: _logo,
      removeLogo: _logo == null,
    );
    try {
      await _api.save(profile);
      _store.save(profile);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم حفظ هوية هذا الفرع وتطبيقها على الفواتير.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('هوية النشاط والفواتير')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const NineSoftEntryHeading(
                      title: 'هوية النشاط والفواتير',
                      subtitle: 'الشعار وبيانات التواصل الظاهرة في المستندات',
                      status: 'إعدادات الفرع',
                      icon: Icons.storefront_outlined,
                    ),
                    const SizedBox(height: 14),
                    NineSoftEntrySection(
                      title: 'الفرع الحالي',
                      subtitle: 'لكل فرع هوية مستقلة داخل المنشأة',
                      icon: Icons.store_mall_directory_outlined,
                      child: _BranchSelector(
                        branches: _branches,
                        value: _branchId,
                        onChanged: (value) {
                          setState(() {
                            _branchId = value;
                            _loadBranch();
                            _syncBranch();
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 52,
                              backgroundColor: Color(
                                _color,
                              ).withValues(alpha: .10),
                              backgroundImage: _logo == null
                                  ? null
                                  : MemoryImage(_logo!),
                              child: _logo == null
                                  ? Icon(
                                      Icons.storefront_rounded,
                                      size: 48,
                                      color: Color(_color),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: _pickLogo,
                                  icon: const Icon(Icons.add_photo_alternate),
                                  label: const Text('اختيار شعار النشاط'),
                                ),
                                if (_logo != null)
                                  TextButton.icon(
                                    onPressed: () =>
                                        setState(() => _logo = null),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('إزالة'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'اسم النشاط بالعربي',
                        helperText:
                            'يظهر في الجهة اليمنى من الفاتورة وجميع المستندات.',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'اسم النشاط مطلوب.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameEn,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'اسم النشاط بالإنجليزي',
                        helperText: 'يظهر أسفل الاسم العربي في الجهة اليمنى.',
                        prefixIcon: Icon(Icons.translate_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _tagline,
                      decoration: const InputDecoration(
                        labelText: 'وصف النشاط أو الخدمات',
                        helperText:
                            'مثال: مواد غذائية • خدمات عامة. اتركه فارغًا إن لم ترده.',
                        prefixIcon: Icon(Icons.short_text_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: const [latinDigitFormatter],
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف',
                        helperText: 'يظهر في الجهة اليسرى مع البريد والعنوان.',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _address,
                      decoration: const InputDecoration(
                        labelText: 'العنوان',
                        helperText: 'يظهر في الجهة اليسرى من ترويسة المستند.',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني',
                        helperText: 'يظهر في الجهة اليسرى من ترويسة المستند.',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _header,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظة أعلى المستند',
                        helperText:
                            'تطبق على الفاتورة والسندات وبقية المستندات.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _footer,
                      decoration: const InputDecoration(
                        labelText: 'رسالة أسفل المستند',
                        helperText:
                            'تطبق على جميع المستندات مثل: شكرًا لتعاملكم معنا.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'حجم الشعار في المستند: ${(_logoScale * 100).round()}%',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Slider(
                      value: _logoScale,
                      min: .55,
                      max: 1.6,
                      divisions: 21,
                      label: '${(_logoScale * 100).round()}%',
                      onChanged: (value) => setState(() => _logoScale = value),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'لون الهوية',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      children: [
                        for (final value in const [
                          0xFF123E78,
                          0xFF087FE7,
                          0xFF22B968,
                          0xFF6A5AE0,
                          0xFFCA6F1E,
                        ])
                          ChoiceChip(
                            label: CircleAvatar(
                              radius: 10,
                              backgroundColor: Color(value),
                            ),
                            selected: _color == value,
                            onSelected: (_) => setState(() => _color = value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    NineSoftEntryFooter(
                      key: const Key('identity-save-footer'),
                      label: 'حفظ هوية الفرع',
                      icon: Icons.save_rounded,
                      onSave: _save,
                      note: 'تُطبق الهوية على الفواتير والمستندات الجديدة',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BranchSelector extends StatelessWidget {
  const _BranchSelector({
    required this.branches,
    required this.value,
    required this.onChanged,
  });

  final List<String> branches;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'الفرع',
        prefixIcon: Icon(Icons.store_mall_directory_rounded),
      ),
      items: [
        for (var index = 0; index < branches.length; index++)
          DropdownMenuItem(
            value: branches[index],
            child: Text('الفرع ${index + 1} - ${_shortId(branches[index])}'),
          ),
      ],
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

String _shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);
