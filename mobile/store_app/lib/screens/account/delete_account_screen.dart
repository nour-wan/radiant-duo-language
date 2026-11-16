import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/session.dart';

/// In-app account deletion (required by Google Play and the App Store).
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _understood = false, _busy = false;

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await context.read<Session>().deleteAccount(_password.text);
      if (!mounted) return;
      showSnack(context, context.tr('del.done'));
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hasPassword = context.watch<Session>().user?.hasPassword ?? true;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('acc.delete'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Icon(Icons.warning_amber_rounded, size: 56, color: AlasColors.destructive),
        const SizedBox(height: 12),
        Text(context.tr('del.title'), style: t.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(context.tr('del.body'), style: t.textTheme.bodyMedium),
        const SizedBox(height: 20),
        if (hasPassword)
          TextField(
            controller: _password,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: context.tr('del.password_hint')),
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _understood,
          onChanged: (v) => setState(() => _understood = v ?? false),
          title: Text(context.tr('del.confirm_check')),
        ),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AlasColors.destructive),
          onPressed: _understood && !_busy && (!hasPassword || _password.text.isNotEmpty) ? _delete : null,
          child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(context.tr('del.button')),
        ),
      ]),
    );
  }
}
