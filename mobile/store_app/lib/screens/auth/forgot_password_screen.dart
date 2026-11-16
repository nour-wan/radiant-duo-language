import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/session.dart';
import '../../widgets/phone_code.dart';

/// New password with a code sent on WhatsApp to the account's phone number.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.phone = ''});

  final String phone;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _phone = TextEditingController(text: widget.phone);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_phone, _code, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<Session>().confirmReset(cleanPhone(_phone.text), cleanPhone(_code.text), _password.text);
      if (!mounted) return;
      showSnack(context, context.tr('auth.password_changed'));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      final errors = e.extra['errors'];
      showSnack(context, errors is Map && errors['new_password'] != null ? (errors['new_password'] as List).join('\n') : context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('auth.reset_title'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Text(context.tr('auth.reset_sub'), style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          PhoneCodeFields(purpose: 'reset', phone: _phone, code: _code),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(labelText: context.tr('auth.new_password'), prefixIcon: const Icon(Icons.lock_outline)),
            validator: (v) => (v == null || v.length < 8) ? context.tr('app.password_short') : null,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(context.tr('auth.change_password')),
          ),
        ]),
      ),
    );
  }
}
