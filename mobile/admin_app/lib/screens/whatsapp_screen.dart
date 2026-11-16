import 'dart:async';
import 'dart:convert';

import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/admin_api.dart';
import '../widgets/admin_widgets.dart';

/// The WhatsApp number that sends customers their verification codes: linked by
/// scanning a QR (like WhatsApp Web). Changing the number = unlink, then scan from the new phone.
/// The Meta Cloud API fields are kept under "Advanced" for later.
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
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : d == null
              ? const LoadingView()
              : ListView(padding: const EdgeInsets.all(12), children: [
                  const _LinkCard(),
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
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.tune),
                      title: Text(context.tr('wa.advanced')),
                      subtitle: Text(context.tr(d['configured'] == true ? 'wa.status_on' : 'wa.advanced_hint')),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
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
                    const SizedBox(height: 12),
                        FilledButton(onPressed: _busy ? null : _save, child: Text(context.tr('app.save'))),
                      ],
                    ),
                  ),
                ]),
    );
  }
}


/// Shows whether the store number is linked; otherwise the QR to scan. Refreshes itself.
class _LinkCard extends StatefulWidget {
  const _LinkCard();

  @override
  State<_LinkCard> createState() => _LinkCardState();
}

class _LinkCardState extends State<_LinkCard> {
  Map<String, dynamic>? _s;
  Timer? _timer;
  bool _busy = false;
  final _pairPhone = TextEditingController(text: '0995482494');
  String? _pairCode;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pairPhone.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    setState(() => _busy = true);
    try {
      final code = await context.read<AdminApi>().pairWhatsApp(_pairPhone.text.trim());
      if (mounted) setState(() => _pairCode = code);
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    try {
      final s = await context.read<AdminApi>().whatsAppLink();
      if (mounted) setState(() => _s = s);
    } catch (_) {}
  }

  Future<void> _unlink() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('wa.unlink')),
        content: Text(ctx.tr('wa.unlink_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('app.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('wa.unlink'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<AdminApi>().unlinkWhatsApp();
      await _refresh();
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = _s;
    final status = s?['status'] as String? ?? 'connecting';
    final qr = s?['qr'] as String?;
    final Widget body;
    if (s == null) {
      body = const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    } else if (status == 'open') {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.check_circle, color: AlasColors.primary, size: 32),
          title: Text(context.tr('wa.linked'), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('+${s['me'] ?? ''}', textDirection: TextDirection.ltr, textAlign: TextAlign.start),
        ),
        Text(context.tr('wa.linked_hint'), style: t.textTheme.bodySmall),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _unlink,
          icon: const Icon(Icons.link_off),
          label: Text(context.tr('wa.unlink')),
          style: OutlinedButton.styleFrom(foregroundColor: AlasColors.destructive),
        ),
      ]);
    } else if (status == 'qr' && qr != null && qr.contains(',')) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.tr('wa.scan_steps'), style: t.textTheme.bodyMedium),
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            color: Colors.white,
            child: Image.memory(base64Decode(qr.split(',').last), width: 260, height: 260, gaplessPlayback: true),
          ),
        ),
        const SizedBox(height: 8),
        Text(context.tr('wa.scan_note'), style: t.textTheme.bodySmall, textAlign: TextAlign.center),
        const Divider(height: 32),
        Text(context.tr('wa.pair_title'), style: t.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(context.tr('wa.pair_steps'), style: t.textTheme.bodySmall),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _pairPhone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: context.tr('wa.pair_phone'), isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _busy ? null : _pair, child: Text(context.tr('wa.pair_get'))),
        ]),
        if (_pairCode != null) ...[
          const SizedBox(height: 12),
          SelectableText(
            _pairCode!.length == 8 ? '${_pairCode!.substring(0, 4)}-${_pairCode!.substring(4)}' : _pairCode!,
            textAlign: TextAlign.center,
            style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 3, fontFamily: 'packages/alas_shared/Manrope'),
          ),
        ],
      ]);
    } else if (status == 'unavailable') {
      body = ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.cloud_off, color: AlasColors.destructive),
        title: Text(context.tr('wa.unavailable')),
        subtitle: Text(context.tr('wa.unavailable_hint')),
      );
    } else {
      body = ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
        title: Text(context.tr('wa.connecting')),
      );
    }
    return FormCard(title: context.tr('wa.link_title'), children: [body]);
  }
}
