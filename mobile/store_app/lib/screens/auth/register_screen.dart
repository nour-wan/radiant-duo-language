import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/session.dart';
import '../../widgets/phone_code.dart';
import '../../widgets/profile_form.dart';
import '../account/legal_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _profile = BusinessProfile.from(null);
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _profile.dispose();
    for (final c in [_phone, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<Session>().register(
          phone: cleanPhone(_phone.text), code: cleanPhone(_code.text), password: _password.text, profile: _profile.toJson(), lang: context.lang);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      final errors = e.extra['errors'];
      if (errors is Map && errors['password'] != null) {
        showSnack(context, (errors['password'] as List).join('\n'), error: true);
      } else {
        showSnack(context, context.trError(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('auth.register'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Text(context.tr('auth.register_sub'), style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          PhoneCodeFields(purpose: 'register', phone: _phone, code: _code),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(labelText: context.tr('app.password')),
            validator: (v) => (v == null || v.length < 8) ? context.tr('app.password_short') : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirm,
            obscureText: true,
            decoration: InputDecoration(labelText: context.tr('auth.confirm_password')),
            validator: (v) => v != _password.text ? context.tr('auth.password_mismatch') : null,
          ),
          const SizedBox(height: 24),
          Text(context.tr('profile.complete_title'), style: t.textTheme.titleMedium),
          const SizedBox(height: 12),
          BusinessProfileFields(profile: _profile),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(context.tr('auth.register')),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LegalScreen(slug: 'privacy'))),
            child: Text(context.tr('auth.terms_note'),
                textAlign: TextAlign.center, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, decoration: TextDecoration.underline)),
          ),
        ]),
      ),
    );
  }
}

/// Shown for older accounts until the business profile (and a verified phone number) is filled.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _profile = BusinessProfile.from(context.read<Session>().user);
  late final _needsPhone = (context.read<Session>().user?.phone ?? '').isEmpty;
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _profile.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final session = context.read<Session>();
      if (_needsPhone) await session.changePhone(cleanPhone(_phone.text), cleanPhone(_code.text));
      await session.updateProfile(_profile.toJson());
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
      appBar: AppBar(title: Text(context.tr('profile.complete_title'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Text(context.tr('profile.complete_sub'), style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          if (_needsPhone) ...[
            PhoneCodeFields(purpose: 'change', phone: _phone, code: _code),
            const SizedBox(height: 12),
          ],
          BusinessProfileFields(profile: _profile),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(context.tr('app.save')),
          ),
        ]),
      ),
    );
  }
}
