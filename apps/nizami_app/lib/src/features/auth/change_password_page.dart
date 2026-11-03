import 'package:flutter/material.dart';

import '../../auth/auth_api.dart';
import '../../theme/ninesoft_entry_ui.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({
    required this.authApi,
    required this.session,
    required this.onChanged,
    required this.onLogout,
    super.key,
  });

  final AuthApi authApi;
  final AuthSession session;
  final VoidCallback onChanged;
  final VoidCallback onLogout;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.authApi.changePassword(
        token: widget.session.token,
        currentPassword: _currentController.text,
        password: _passwordController.text,
        passwordConfirmation: _confirmationController.text,
      );
      if (mounted) widget.onChanged();
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.length < 12 ||
        !RegExp('[A-Z]').hasMatch(password) ||
        !RegExp('[a-z]').hasMatch(password) ||
        !RegExp('[0-9]').hasMatch(password) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      return 'استخدم 12 حرفًا على الأقل مع حروف كبيرة وصغيرة ورقم ورمز.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F6FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const NineSoftEntryHeading(
                    title: 'تأمين الحساب',
                    subtitle: 'أنشئ كلمة مرور قوية قبل متابعة استخدام النظام',
                    status: 'حماية حساب المالك',
                    icon: Icons.security_rounded,
                  ),
                  const SizedBox(height: 14),
                  NineSoftEntrySection(
                    title: 'تغيير كلمة المرور',
                    subtitle: 'لا تُشارك كلمة المرور الجديدة مع أي شخص',
                    icon: Icons.password_rounded,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'كلمة المرور الحالية مؤقتة. أنشئ كلمة قوية قبل متابعة استخدام النظام.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          NineSoftEntryFieldGrid(
                            maxColumns: 1,
                            children: [
                              TextFormField(
                                key: const Key('change-password-current'),
                                controller: _currentController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'كلمة المرور المؤقتة',
                                  prefixIcon: Icon(Icons.lock_clock_rounded),
                                ),
                                validator: (value) =>
                                    value == null || value.isEmpty
                                    ? 'هذا الحقل مطلوب.'
                                    : null,
                              ),
                              TextFormField(
                                key: const Key('change-password-new'),
                                controller: _passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'كلمة المرور الجديدة',
                                  prefixIcon: Icon(Icons.password_rounded),
                                ),
                                validator: _validatePassword,
                              ),
                              TextFormField(
                                key: const Key('change-password-confirmation'),
                                controller: _confirmationController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'تأكيد كلمة المرور الجديدة',
                                  prefixIcon: Icon(Icons.verified_user_rounded),
                                ),
                                validator: (value) =>
                                    value != _passwordController.text
                                    ? 'كلمتا المرور غير متطابقتين.'
                                    : null,
                              ),
                            ],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          NineSoftEntryFooter(
                            key: const Key('change-password-footer'),
                            label: _submitting
                                ? 'جارٍ الحفظ...'
                                : 'حفظ ومتابعة',
                            icon: Icons.security_update_good_rounded,
                            enabled: !_submitting,
                            onSave: _submitting ? null : _submit,
                            note: 'استخدم 12 حرفًا مع رقم ورمز وحروف متنوعة',
                          ),
                          TextButton(
                            onPressed: _submitting ? null : widget.onLogout,
                            child: const Text('تسجيل الخروج'),
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
