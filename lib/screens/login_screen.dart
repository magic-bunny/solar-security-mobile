import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../providers/device_provider.dart';
import '../providers/connection_provider.dart';
import '../widgets/animated_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _rememberMe = true;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool('remember_me') ?? false;
    if (remember) {
      _emailCtrl.text = prefs.getString('saved_email') ?? '';
      _passCtrl.text = prefs.getString('saved_pass') ?? '';
    }
    if (mounted) setState(() => _rememberMe = remember);
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', _rememberMe);
    if (_rememberMe) {
      await prefs.setString('saved_email', _emailCtrl.text.trim());
      await prefs.setString('saved_pass', _passCtrl.text);
    } else {
      await prefs.remove('saved_email');
      await prefs.remove('saved_pass');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthProvider>().clearError();

    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;

    final auth = context.read<AuthProvider>();
    final ok = await auth.signIn(email, pass, rememberMe: _rememberMe);
    if (ok && mounted) {
      await _saveCredentials();
      final dp = context.read<DeviceProvider>();
      final token = await auth.getIdToken();
      if (token != null) dp.setToken(token);
      dp.loadDevices(); // fire-and-forget, don't block navigation
      if (mounted) context.go('/');
    }
  }

  void _showForgotPassword(BuildContext context) {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final codeCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    bool codeSent = false;
    String? err;

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
      final auth = ctx.read<AuthProvider>();
      return AlertDialog(
        title: Text(codeSent ? 'Reset Password' : 'Forgot Password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (err != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(err!, style: const TextStyle(color: Colors.red, fontSize: 13))),
          if (!codeSent) ...[
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
          ] else ...[
            TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Verification Code'), keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            TextField(controller: newPassCtrl, decoration: const InputDecoration(labelText: 'New Password'), obscureText: true),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: auth.loading ? null : () async {
              setDlg(() => err = null);
              if (!codeSent) {
                final ok = await auth.forgotPassword(emailCtrl.text.trim());
                setDlg(() { if (ok) codeSent = true; else err = auth.error ?? 'Failed'; });
              } else {
                final ok = await auth.confirmForgotPassword(emailCtrl.text.trim(), codeCtrl.text.trim(), newPassCtrl.text);
                if (ok && ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset successfully')));
                } else {
                  setDlg(() => err = auth.error ?? 'Failed');
                }
              }
            },
            child: Text(codeSent ? 'Reset' : 'Send Code'),
          ),
        ],
      );
    }));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Form(
            key: _formKey,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AnimatedLogo(size: 150),
              const SizedBox(height: 32),
              if (auth.error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(auth.error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 13)),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                keyboardType: TextInputType.emailAddress,
                enabled: !auth.loading,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Please enter your email';
                  if (!v.contains('@')) return 'Please enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                enabled: !auth.loading,
                onFieldSubmitted: (_) => _submit(),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Please enter your password';
                  if (v.length < 8) return 'Password must be at least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Row(children: [
                SizedBox(width: 24, height: 24, child: Checkbox(
                  value: _rememberMe,
                  onChanged: auth.loading ? null : (v) => setState(() => _rememberMe = v ?? false),
                )),
                const SizedBox(width: 8),
                const Text('Remember me', style: TextStyle(fontSize: 14)),
              ]),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: auth.loading ? null : _submit,
                  child: auth.loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Sign In'),
                ),
              ),
              TextButton(
                onPressed: auth.loading ? null : () => _showForgotPassword(context),
                child: const Text('Forgot Password?'),
              ),
            ],
          )),
        ),
      ),
    );
  }
}
