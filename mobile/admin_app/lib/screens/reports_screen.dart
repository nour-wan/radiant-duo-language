import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/admin_api.dart';
import '../widgets/admin_widgets.dart';
import 'dashboard_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _period = 'day';
  late DateTimeRange _range = _defaultRange('day');

  static DateTimeRange _defaultRange(String period) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final days = {'day': 29, 'week': 7 * 12, 'month': 364}[period]!;
    return DateTimeRange(start: end.subtract(Duration(days: days)), end: end);
  }

  String _label(DateTime d) => switch (_period) {
        'month' => DateFormat('MMM y', context.lang).format(d),
        'week' => DateFormat('d/M').format(d),
        _ => DateFormat('d/M').format(d),
      };

  Future<void> _export() async {
    try {
      final bytes = await context.read<AdminApi>().reportCsv(_period, _range.start, _range.end);
      if (mounted) await shareCsv(context, bytes, 'alas-sales-$_period-${isoDate(_range.start)}_${isoDate(_range.end)}.csv');
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminApi>();
    final t = Theme.of(context);
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('more.reports')),
        actions: [IconButton(tooltip: context.tr('report.export'), icon: const Icon(Icons.file_download_outlined), onPressed: _export)],
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        SegmentedButton<String>(
          segments: [for (final p in ['day', 'week', 'month']) ButtonSegment(value: p, label: Text(context.tr('report.$p')))],
          selected: {_period},
          onSelectionChanged: (s) => setState(() {
            _period = s.first;
            _range = _defaultRange(_period);
          }),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range),
          label: Text(context.tr('report.range', {'a': formatDate(_range.start, lang), 'b': formatDate(_range.end, lang)})),
          onPressed: () async {
            final r = await showDateRangePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime.now(), initialDateRange: _range);
            if (r != null) setState(() => _range = r);
          },
        ),
        const SizedBox(height: 12),
        AsyncView<Report>(
          key: ValueKey('$_period|$_range'),
          load: () => api.report(_period, _range.start, _range.end),
          builder: (context, r, reload) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                _Kpi(context.tr('report.sales'), money(r.totalSales)),
                _Kpi(context.tr('report.orders'), '${r.totalOrders}'),
                _Kpi(context.tr('report.avg'), money(r.averageOrder)),
                _Kpi(context.tr('report.discounts'), money(r.totalDiscount)),
              ],
            ),
            const SizedBox(height: 12),
            if (r.series.isEmpty)
              EmptyView(icon: Icons.bar_chart, title: context.tr('report.empty'))
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                  child: SizedBox(height: 220, child: SalesBarChart(points: [for (final s in r.series) (label: _label(s.period), value: s.sales)])),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  for (final s in r.series.reversed)
                    ListTile(
                      dense: true,
                      title: Text(_label(s.period)),
                      subtitle: Text(context.tr('dash.orders_n', {'n': s.orders})),
                      trailing: Text(money(s.sales), style: const TextStyle(fontFamily: 'packages/alas_shared/Manrope', fontWeight: FontWeight.w700)),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              Text(context.tr('report.top'), style: t.textTheme.titleMedium),
              const SizedBox(height: 6),
              Card(
                child: Column(children: [
                  for (final p in r.topProducts)
                    ListTile(
                      dense: true,
                      title: Text(pick(lang, p['product_name_ar'] as String?, p['product_name_en'] as String?)),
                      subtitle: Text(context.tr('dash.qty', {'n': p['quantity']})),
                      trailing: Text(money(toMoney(p['revenue']))),
                    ),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          FittedBox(child: Text(value, style: t.textTheme.titleLarge?.copyWith(fontFamily: 'packages/alas_shared/Manrope', color: t.colorScheme.primary))),
        ]),
      ),
    );
  }
}
