import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/admin_api.dart';
import '../state/admin_session.dart';
import '../widgets/admin_widgets.dart';

/// The dollar rate: product prices are entered in USD and customers see them in Syrian pounds
/// at this rate. Everyone on staff can see it; only the owner changes how it is set.
class ExchangeRateScreen extends StatefulWidget {
  const ExchangeRateScreen({super.key});

  @override
  State<ExchangeRateScreen> createState() => _ExchangeRateScreenState();
}

class _ExchangeRateScreenState extends State<ExchangeRateScreen> {
  RateStatus? _s;
  Object? _error;
  bool _busy = false;
  String _mode = 'auto', _side = 'sell';
  int _rounding = 10;
  final _manual = TextEditingController();

  static const _roundings = [1, 5, 10, 25, 50, 100, 500];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  void _apply(RateStatus s) {
    _s = s;
    _mode = s.mode;
    _side = s.side;
    _rounding = s.rounding;
    _manual.text = s.manual == null ? '' : _plain(s.manual!);
  }

  String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await context.read<AdminApi>().exchangeRate();
      if (mounted) setState(() => _apply(s));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<RateStatus> Function() call, {String? done}) async {
    setState(() => _busy = true);
    try {
      final s = await call();
      if (!mounted) return;
      setState(() => _apply(s));
      if (done != null) showSnack(context, context.tr(done));
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final manual = parseAmount(_manual.text);
    if (_mode == 'manual' && (manual == null || manual <= 0)) {
      showSnack(context, context.tr('rate.manual_required'), error: true);
      return;
    }
    final api = context.read<AdminApi>();
    await _run(() async {
      await api.saveRateSettings({
        'usd_rate_mode': _mode,
        'usd_rate_side': _side,
        'syp_rounding': _rounding,
        'usd_rate_manual': manual?.toStringAsFixed(2),
      });
      return api.exchangeRate();
    }, done: 'app.saved');
  }

  @override
  Widget build(BuildContext context) {
    final owner = context.watch<AdminSession>().isOwner;
    final t = Theme.of(context);
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('rate.title'))),
      bottomNavigationBar: owner && s != null ? SaveButton(busy: _busy, onPressed: _save) : null,
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : s == null
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(context.tr('rate.current'), style: t.textTheme.titleSmall),
                          const SizedBox(height: 6),
                          Text(s.rate == null ? '—' : '1 \$ = ${money(s.rate)}',
                              style: t.textTheme.headlineMedium?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(context.tr(s.mode == 'manual' ? 'rate.from_manual' : (s.side == 'sell' ? 'rate.from_auto_sell' : 'rate.from_auto_buy')),
                              style: t.textTheme.bodySmall),
                          if (s.autoSell != null)
                            Text(context.tr('rate.auto_values', {'sell': _plain(s.autoSell!), 'buy': _plain(s.autoBuy ?? 0)}), style: t.textTheme.bodySmall),
                          if (s.fetchedAt != null)
                            Text(context.tr('rate.updated', {'t': formatDateTime(s.fetchedAt!, context.lang)}), style: t.textTheme.bodySmall),
                          Text(context.tr('rate.rounding_now', {'n': s.rounding}), style: t.textTheme.bodySmall),
                          if (s.stale) ...[
                            const SizedBox(height: 8),
                            Text(context.tr('rate.stale'), style: t.textTheme.bodyMedium?.copyWith(color: AlasColors.warning)),
                          ],
                          if (owner && s.mode == 'auto') ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => _run(() => context.read<AdminApi>().exchangeRateAction('refresh'), done: 'rate.refreshed'),
                              icon: const Icon(Icons.refresh),
                              label: Text(context.tr('rate.refresh')),
                            ),
                          ],
                        ]),
                      ),
                    ),
                    if (s.held != null)
                      Card(
                        color: AlasColors.warning.withValues(alpha: 0.12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(context.tr('rate.held_title'), style: t.textTheme.titleSmall),
                            const SizedBox(height: 6),
                            Text(context.tr('rate.held_body', {'sell': '${s.held!['sell']}', 'buy': '${s.held!['buy']}'})),
                            if (owner) ...[
                              const SizedBox(height: 10),
                              FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() => context.read<AdminApi>().exchangeRateAction('accept', id: s.held!['id'] as int), done: 'rate.accepted'),
                                child: Text(context.tr('rate.accept')),
                              ),
                            ],
                          ]),
                        ),
                      ),
                    if (owner) ...[
                      const SizedBox(height: 4),
                      FormCard(title: context.tr('rate.settings'), children: [
                        SegmentedButton<String>(
                          segments: [
                            ButtonSegment(value: 'auto', label: Text(context.tr('rate.mode_auto'))),
                            ButtonSegment(value: 'manual', label: Text(context.tr('rate.mode_manual'))),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (v) => setState(() => _mode = v.first),
                        ),
                        if (_mode == 'auto')
                          SegmentedButton<String>(
                            segments: [
                              ButtonSegment(value: 'sell', label: Text(context.tr('rate.side_sell'))),
                              ButtonSegment(value: 'buy', label: Text(context.tr('rate.side_buy'))),
                            ],
                            selected: {_side},
                            onSelectionChanged: (v) => setState(() => _side = v.first),
                          ),
                        TextField(
                          controller: _manual,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: context.tr('rate.manual'),
                            helperText: context.tr(_mode == 'manual' ? 'rate.manual_hint' : 'rate.manual_backup'),
                            helperMaxLines: 3,
                          ),
                        ),
                        DropdownButtonFormField<int>(
                          initialValue: _roundings.contains(_rounding) ? _rounding : 10,
                          decoration: InputDecoration(labelText: context.tr('rate.rounding'), helperText: context.tr('rate.rounding_hint'), helperMaxLines: 3),
                          items: [for (final r in _roundings) DropdownMenuItem(value: r, child: Text(money(r)))],
                          onChanged: (v) => setState(() => _rounding = v ?? 10),
                        ),
                      ]),
                    ],
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(context.tr('rate.explain'), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                    ),
                  ]),
                ),
    );
  }
}
