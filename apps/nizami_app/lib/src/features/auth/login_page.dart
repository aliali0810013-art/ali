import 'package:flutter/material.dart';

import '../../auth/auth_api.dart';
import '../../theme/ninesoft_entry_ui.dart';
import '../../widgets/ninesoft_brand_logo.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    required this.authApi,
    required this.onAuthenticated,
    super.key,
  });

  final AuthApi authApi;
  final ValueChanged<AuthSession> onAuthenticated;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final session = await widget.authApi.login(
        tenant: '',
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) widget.onAuthenticated(session);
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب.' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F6FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const NineSoftEntryHeading(
                    title: 'NineSoft',
                    subtitle: 'دخول آمن إلى مساحة العمل المحاسبية',
                    status: 'بوابة النظام',
                    icon: Icons.shield_outlined,
                  ),
                  const SizedBox(height: 14),
                  NineSoftEntrySection(
                    title: 'بيانات الدخول',
                    subtitle: 'أدخل بيانات حسابك للمتابعة',
                    icon: Icons.login_rounded,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Align(
                            alignment: Alignment.center,
                            child: NineSoftBrandLogo(
                              width: 180,
                              height: 90,
                              padding: EdgeInsets.all(8),
                              borderRadius: 18,
                            ),
                          ),
                          const SizedBox(height: 18),
                          NineSoftEntryFieldGrid(
                            maxColumns: 1,
                            children: [
                              TextFormField(
                                key: const Key('login-username'),
                                controller: _usernameController,
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.left,
                                style: const TextStyle(
                                  fontFamily: 'ArialMTBlack',
                                  fontWeight: FontWeight.w900,
                                ),
                                textInputAction: TextInputAction.next,
                                validator: _required,
                                decoration: const InputDecoration(
                                  labelText: 'اسم المستخدم',
                                  prefixIcon: Icon(Icons.person_rounded),
                                ),
                              ),
                              TextFormField(
                                key: const Key('login-password'),
                                controller: _passwordController,
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.left,
                                style: const TextStyle(
                                  fontFamily: 'ArialMTBlack',
                                  fontWeight: FontWeight.w900,
                                ),
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                validator: _required,
                                decoration: InputDecoration(
                                  labelText: 'كلمة المرور',
                                  prefixIcon: const Icon(Icons.lock_rounded),
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword
                                        ? 'إظهار كلمة المرور'
                                        : 'إخفاء كلمة المرور',
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_rounded
                                          : Icons.visibility_off_rounded,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            key: const Key('login-submit'),
                            onPressed: _submitting ? null : _submit,
                            icon: _submitting
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.login_rounded),
                            label: Text(
                              _submitting ? 'جارٍ التحقق...' : 'تسجيل الدخول',
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
