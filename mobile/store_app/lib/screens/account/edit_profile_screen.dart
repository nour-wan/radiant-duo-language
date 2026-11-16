import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/session.dart';
import '../../widgets/phone_code.dart';
import '../../widgets/profile_form.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _profile = BusinessProfile.from(context.read<Session>().user);
  bool _busy = false;

  @override
  void dispose() {
    _profile.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<Session>().updateProfile({..._profile.toJson(), 'language': context.lang});
      if (!mounted) return;
      showSnack(context, context.tr('acc.profile_saved'));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    final user = context.read<Session>().user!;
    final current = TextEditingController();
    final next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('auth.change_password')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (user.hasPassword)
            TextField(controller: current, obscureText: true, decoration: InputDecoration(labelText: ctx.tr('auth.current_password'))),
          const SizedBox(height: 12),
          TextField(controller: next, obscureText: true, decoration: InputDecoration(labelText: ctx.tr('auth.new_password'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('app.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('app.save'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (next.text.length < 8) {
      showSnack(context, context.tr('app.password_short'), error: true);
      return;
    }
    try {
      await context.read<Session>().changePassword(current.text, next.text);
      if (mounted) showSnack(context, context.tr('app.saved'));
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('acc.profile'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.phone_iphone),
              title: Text(context.tr('auth.phone')),
              subtitle: Text(user?.phone.isNotEmpty == true ? user!.phone : '—', textDirection: TextDirection.ltr, textAlign: TextAlign.start),
              trailing: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePhoneScreen())),
                child: Text(context.tr('auth.change_phone')),
              ),
            ),
          ),
          const SizedBox(height: 16),
          BusinessProfileFields(profile: _profile),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(context.tr('app.save')),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _changePassword, icon: const Icon(Icons.lock_reset), label: Text(context.tr('auth.change_password'))),
        ]),
      ),
    );
  }
}

/// New phone number, confirmed with a code sent on WhatsApp to that number.
class ChangePhoneScreen extends StatefulWidget {
  const ChangePhoneScreen({super.key});

  @override
  State<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends State<ChangePhoneScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<Session>().changePhone(cleanPhone(_phone.text), cleanPhone(_code.text));
      if (!mounted) return;
      showSnack(context, context.tr('app.saved'));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('auth.change_phone'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          PhoneCodeFields(purpose: 'change', phone: _phone, code: _code, label: context.tr('auth.new_phone')),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(context.tr('app.save')),
          ),
        ]),
      ),
    );
  }
}
