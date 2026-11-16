import 'dart:async';

import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session.dart';

const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';

/// Western digits only ("٠٩٤٤…" → "0944…"), keeping a leading +.
String cleanPhone(String raw) {
  final s = raw.trim();
  final digits = StringBuffer();
  for (final ch in s.split('')) {
    final i = _arabicDigits.indexOf(ch);
    if (i >= 0) {
      digits.write(i);
    } else if (RegExp(r'\d').hasMatch(ch)) {
      digits.write(ch);
    }
  }
  return (s.startsWith('+') ? '+' : '') + digits.toString();
}

String? validatePhone(BuildContext context, String? v) {
  final p = cleanPhone(v ?? '');
  if (p.isEmpty) return context.tr('app.required');
  final n = p.replaceAll('+', '').length;
  if (n < 9 || n > 15) return context.tr('err.invalid_phone');
  return null;
}

/// Phone number field plus "send the code on WhatsApp" and the 6-digit code.
/// The code field fails validation until a code was requested for this number.
class PhoneCodeFields extends StatefulWidget {
  const PhoneCodeFields({super.key, required this.purpose, required this.phone, required this.code, this.label});

  /// 'register', 'reset' or 'change'
  final String purpose;
  final TextEditingController phone, code;
  final String? label;

  @override
  State<PhoneCodeFields> createState() => _PhoneCodeFieldsState();
}

class _PhoneCodeFieldsState extends State<PhoneCodeFields> {
  String? _sentTo, _channel;
  bool _sending = false;
  int _wait = 0;
  Timer? _timer;

  bool get _sent => _sentTo != null && cleanPhone(widget.phone.text) == _sentTo;

  @override
  void initState() {
    super.initState();
    widget.phone.addListener(_phoneChanged);
  }

  @override
  void dispose() {
    widget.phone.removeListener(_phoneChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _phoneChanged() {
    if (_sentTo != null && !_sent) setState(() {}); // number edited: a new code is needed
  }

  Future<void> _send() async {
    final error = validatePhone(context, widget.phone.text);
    if (error != null) {
      showSnack(context, error, error: true);
      return;
    }
    final phone = cleanPhone(widget.phone.text);
    setState(() => _sending = true);
    try {
      final channel = await context.read<Session>().requestCode(phone, widget.purpose, context.lang);
      if (!mounted) return;
      setState(() {
        _sentTo = phone;
        _channel = channel;
        _wait = 60;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _wait <= 1) {
          t.cancel();
          if (mounted) setState(() => _wait = 0);
        } else {
          setState(() => _wait--);
        }
      });
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final sent = _sent;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextFormField(
        controller: widget.phone,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumber],
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: widget.label ?? context.tr('auth.phone'),
          hintText: '09xxxxxxxx',
          prefixIcon: const Icon(Icons.phone_iphone),
        ),
        validator: (v) => validatePhone(context, v),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _sending || (sent && _wait > 0) ? null : _send,
        icon: _sending
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chat_outlined, color: Color(0xFF25D366)),
        label: Text(!sent
            ? context.tr('auth.send_code_wa')
            : _wait > 0
                ? context.tr('auth.resend_in', {'n': _wait})
                : context.tr('auth.resend')),
      ),
      if (sent) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: t.colorScheme.primaryContainer.withValues(alpha: .5), borderRadius: BorderRadius.circular(12)),
          child: Text(
            context.tr(_channel == 'manual' ? 'auth.code_manual' : 'auth.code_wa', {'p': _sentTo}),
            style: t.textTheme.bodyMedium,
          ),
        ),
      ],
      const SizedBox(height: 10),
      TextFormField(
        controller: widget.code,
        keyboardType: TextInputType.number,
        maxLength: 6,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(labelText: context.tr('auth.code'), prefixIcon: const Icon(Icons.pin_outlined), counterText: ''),
        validator: (v) {
          if (!sent) return context.tr('auth.code_first');
          return cleanPhone(v ?? '').length != 6 ? context.tr('auth.code_6') : null;
        },
      ),
    ]);
  }
}
