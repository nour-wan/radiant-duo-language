import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/admin_api.dart';
import '../widgets/admin_widgets.dart';

/// The WhatsApp Business number that sends customers their verification codes.
/// Changing the number later = put the new number's "Phone number ID" here.
class WhatsAppSettingsScreen extends StatefulWidget {
  const WhatsAppSettingsScreen({super.key});

  @override
  State<WhatsAppSettingsScreen> createState() => _WhatsAppSettingsScreenState();
}

class _WhatsAppSettingsScreenState extends State<WhatsAppSettingsScreen> {
  final _phoneId = TextEditingController();
  final _token = TextEditingController();
  final _template = TextEditingController();
  final _lang = TextEditingController();
  final _testPhone = TextEditingController();
  Map<String, dynamic>? _data;
  Object? _error;
  bool _busy = false, _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_phoneId, _token, _template, _lang, _testPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Map<String, dynamic> d) {
    _data = d;
    _phoneId.text = d['phone_number_id'] as String? ?? '';
    _template.text = d['otp_template'] as String? ?? '';
    _lang.text = d['template_lang'] as String? ?? 'ar';
    _token.clear();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<AdminApi>().whatsApp();
      if (mounted) setState(() => _fill(d));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final d = await context.read<AdminApi>().saveWhatsApp({
        'phone_number_id': _phoneId.text.trim(),
        'otp_template': _template.text.trim(),
        'template_lang': _lang.text.trim().isEmpty ? 'ar' : _lang.text.trim(),
        if (_token.text.trim().isNotEmpty) 'access_token': _token.text.trim(),
      });
      if (!mounted) return;
      setState(() => _fill(d));
      showSnack(context, context.tr('app.saved'));
    } on ApiException catch (e) {
      if (!mounted) return;
      final errors = e.extra['errors'];
      showSnack(context, errors is Map ? errors.keys.map((k) => context.tr('wa.$k')).join('، ') : context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final r = await context.read<AdminApi>().testWhatsApp(_testPhone.text.trim());
      if (!mounted) return;
      final ok = r['ok'] == true;
      setState(() {
        _testOk = ok;
        _testResult = ok
            ? context.tr('wa.test_ok', {'from': '${r['from']} (${r['name']})', 'to': r['to']})
            : r['error'] == 'not_configured'
                ? context.tr('wa.not_configured')
                : '${context.tr('wa.test_failed')}\n${r['error']}';
      });
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('wa.title'))),
      bottomNavigationBar: d == null ? null : SaveButton(busy: _busy, onPressed: _save),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : d == null
              ? const LoadingView()
              : ListView(padding: const EdgeInsets.all(12), children: [
                  Card(
                    color: d['configured'] == true ? t.colorScheme.primaryContainer : t.colorScheme.errorContainer,
                    child: ListTile(
                      leading: Icon(d['configured'] == true ? Icons.check_circle_outline : Icons.info_outline),
                      title: Text(context.tr(d['configured'] == true ? 'wa.status_on' : 'wa.status_off')),
                    ),
                  ),
                  FormCard(title: context.tr('wa.account'), children: [
                    TextField(
                      controller: _phoneId,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(labelText: context.tr('wa.phone_number_id'), helperText: context.tr('wa.phone_number_id_hint'), helperMaxLines: 3),
                    ),
                    TextField(
                      controller: _token,
                      obscureText: true,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: context.tr('wa.access_token'),
                        helperText: context.tr(d['token_saved'] == true ? 'wa.token_saved' : 'wa.token_hint'),
                        helperMaxLines: 3,
                      ),
                    ),
                    TextField(
                      controller: _template,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(labelText: context.tr('wa.otp_template'), hintText: 'alas_otp'),
                    ),
                    TextField(
                      controller: _lang,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(labelText: context.tr('wa.template_lang'), hintText: 'ar'),
                    ),
                  ]),
                  FormCard(title: context.tr('wa.test'), children: [
                    Text(context.tr('wa.test_hint'), style: t.textTheme.bodySmall),
                    TextField(
                      controller: _testPhone,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(labelText: context.tr('wa.test_phone'), hintText: '09xxxxxxxx'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _testing ? null : _test,
                      icon: _testing
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_outlined, color: Color(0xFF25D366)),
                      label: Text(context.tr('wa.test_send')),
                    ),
                    if (_testResult != null)
                      Text(_testResult!, style: TextStyle(color: _testOk ? AlasColors.primary : AlasColors.destructive, fontWeight: FontWeight.w600)),
                  ]),
                ]),
    );
  }
}
