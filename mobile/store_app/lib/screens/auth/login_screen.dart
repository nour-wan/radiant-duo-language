import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/session.dart';
import '../../widgets/phone_code.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

/// Pops with `true` after a successful login.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false, _obscure = true;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<Session>().login(cleanPhone(_phone.text), _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
          const Center(child: LeafLogo(size: 64)),
          const SizedBox(height: 20),
          Text(context.tr('auth.welcome_back'), style: t.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(context.tr('auth.login_sub'), style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
          const SizedBox(height: 28),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: InputDecoration(labelText: context.tr('auth.phone'), hintText: '09xxxxxxxx', prefixIcon: const Icon(Icons.phone_iphone)),
            validator: (v) => validatePhone(context, v),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => _login(),
            decoration: InputDecoration(
              labelText: context.tr('app.password'),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _obscure = !_obscure)),
            ),
            validator: (v) => (v == null || v.isEmpty) ? context.tr('app.required') : null,
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ForgotPasswordScreen(phone: _phone.text))),
              child: Text(context.tr('auth.forgot')),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _login,
            child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(context.tr('auth.login')),
          ),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(context.tr('auth.no_account')),
            TextButton(
              onPressed: () async {
                final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const RegisterScreen()));
                if (ok == true && context.mounted) Navigator.of(context).pop(true);
              },
              child: Text(context.tr('auth.register')),
            ),
          ]),
        ]),
      ),
    );
  }
}
