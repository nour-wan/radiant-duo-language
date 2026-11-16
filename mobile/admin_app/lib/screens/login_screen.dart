import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/admin_session.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false, _obscure = true;

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<AdminSession>().login(_email.text, _password.text);
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final settings = context.watch<AppSettings>();
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(28), children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => settings.setLang(settings.lang == 'ar' ? 'en' : 'ar'),
                child: Text(settings.lang == 'ar' ? 'English' : 'العربية'),
              ),
            ),
            const SizedBox(height: 40),
            const Center(child: LeafLogo(size: 76)),
            const SizedBox(height: 20),
            Text(context.tr('login.title'), style: t.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(context.tr('login.sub'), style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: context.tr('login.id'),
                helperText: context.tr('login.id_hint'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
              validator: (v) => (v == null || v.trim().length < 6) ? context.tr('app.required') : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              onFieldSubmitted: (_) => _login(),
              decoration: InputDecoration(
                labelText: context.tr('app.password'),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? context.tr('app.required') : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _login,
              child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(context.tr('login.button')),
            ),
          ]),
        ),
      ),
    );
  }
}
