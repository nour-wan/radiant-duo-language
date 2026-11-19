import 'package:alas_shared/alas_shared.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'exchange_rate_screen.dart';
import 'inbox_screen.dart';
import 'statement_screen.dart';

import '../services/admin_api.dart';
import '../state/admin_session.dart';
import 'product_form_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onOpenOrders});

  final VoidCallback onOpenOrders;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Key _key = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminApi>();
    // Distributors see their own sales in pounds only (no dollar figures, no rate card)
    final dist = context.watch<AdminSession>().isDistributor;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [const LeafLogo(size: 30), const SizedBox(width: 10), Text(context.tr('title'))]),
        actions: [
          InboxButton(key: ValueKey(_key)),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() => _key = UniqueKey())),
        ],
      ),
      body: AsyncView<Dashboard>(
        key: _key,
        load: api.dashboard,
        builder: (context, d, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            if (d.rate != null && !dist)
              Card(
                color: d.rate!.stale || d.rate!.held != null ? AlasColors.warning.withValues(alpha: .12) : null,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.currency_exchange, color: d.rate!.stale || d.rate!.held != null ? AlasColors.warning : AlasColors.primary),
                  title: Text(context.tr('dash.rate', {'r': d.rate!.rate == null ? '—' : money(d.rate!.rate)}), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: d.rate!.held != null
                      ? Text(context.tr('rate.held_title'))
                      : d.rate!.stale
                          ? Text(context.tr('rate.stale'))
                          : d.rate!.fetchedAt == null || d.rate!.mode == 'manual'
                              ? Text(context.tr('rate.from_manual'))
                              : Text(context.tr('rate.updated', {'t': formatDateTime(d.rate!.fetchedAt!, context.lang)})),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExchangeRateScreen())).then((_) => reload()),
                ),
              ),
            Row(children: [
              Expanded(
                  child: _Stat(
                      label: context.tr('dash.today'),
                      value: money(d.todaySales),
                      sub: dist ? context.tr('dash.orders_n', {'n': d.todayOrders}) : '${context.tr('dash.orders_n', {'n': d.todayOrders})} · ≈ ${usd(d.todaySalesUsd)}')),
              const SizedBox(width: 10),
              Expanded(
                  child: _Stat(
                      label: context.tr('dash.month'),
                      value: moneyCompact(d.monthSales),
                      sub: dist ? context.tr('dash.orders_n', {'n': d.monthOrders}) : '${context.tr('dash.orders_n', {'n': d.monthOrders})} · ≈ ${usd(d.monthSalesUsd)}')),
            ]),
            const SizedBox(height: 10),
            if (d.pendingOrders > 0)
              Card(
                color: AlasColors.warning.withValues(alpha: .12),
                child: ListTile(
                  leading: const Icon(Icons.hourglass_top_rounded, color: AlasColors.warning),
                  title: Text('${context.tr('dash.pending')}: ${d.pendingOrders}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onOpenOrders,
                ),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _Stat(label: context.tr('dash.customers'), value: '${d.customers}', icon: Icons.people_outline)),
              const SizedBox(width: 10),
              Expanded(child: _Stat(label: context.tr('dash.products'), value: '${d.products}', icon: Icons.inventory_2_outlined)),
            ]),
            if (d.receivablesTotal > 0) ...[
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined, color: AlasColors.destructive),
                  title: Text(context.tr('dash.receivables')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(money(d.receivablesTotal),
                        style: const TextStyle(fontFamily: 'packages/alas_shared/Manrope', fontWeight: FontWeight.w700, color: AlasColors.destructive)),
                    const Icon(Icons.chevron_right),
                  ]),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReceivablesScreen())),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr('dash.chart'), style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  SizedBox(height: 180, child: SalesBarChart(points: [for (final p in d.chart) (label: DateFormat('d/M').format(p.date), value: p.sales)])),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            _ListCard(
              title: context.tr('dash.best'),
              children: [
                for (final b in d.bestSellers)
                  ListTile(
                    dense: true,
                    title: Text(pick(context.lang, b['product_name_ar'] as String?, b['product_name_en'] as String?)),
                    subtitle: Text(context.tr('dash.qty', {'n': b['quantity']})),
                    trailing: Text(money(toMoney(b['revenue'])), style: const TextStyle(fontFamily: 'packages/alas_shared/Manrope', fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _ListCard(
              title: context.tr('dash.low_stock'),
              empty: context.tr('dash.low_stock_none', {'n': d.lowStockThreshold}),
              children: [
                for (final v in d.lowStock)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.warning_amber_rounded, color: (v['stock'] as int) == 0 ? AlasColors.destructive : AlasColors.warning),
                    title: Text(pick(context.lang, v['product_name_ar'] as String?, v['product_name_en'] as String?)),
                    subtitle: Text(pick(context.lang, v['label_ar'] as String?, v['label_en'] as String?)),
                    trailing: Text(context.tr('dash.stock_left', {'n': v['stock']}), style: const TextStyle(fontWeight: FontWeight.w700)),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductFormScreen(productId: v['product_id'] as int)));
                      reload();
                    },
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class SalesBarChart extends StatelessWidget {
  const SalesBarChart({super.key, required this.points});

  final List<({String label, double value})> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxY = points.fold<double>(0, (m, p) => p.value > m ? p.value : m);
    final step = (points.length / 7).ceil().clamp(1, 100);
    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 10 : maxY * 1.15,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: scheme.outline.withValues(alpha: .5), strokeWidth: 1, dashArray: [4, 4]),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${points[group.x].label}\n${money(rod.toY)}',
              TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) => v == meta.max ? const SizedBox.shrink() : Text(NumberFormat.compact().format(v), style: const TextStyle(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i % step != 0 || i >= points.length) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 4), child: Text(points[i].label, style: const TextStyle(fontSize: 10)));
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < points.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: points[i].value,
                width: points.length > 20 ? 6 : 12,
                color: scheme.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.sub, this.icon});

  final String label, value;
  final String? sub;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 18, color: t.colorScheme.onSurfaceVariant), const SizedBox(width: 6)],
            Expanded(child: Text(label, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant))),
          ]),
          const SizedBox(height: 6),
          Text(value, style: t.textTheme.headlineSmall?.copyWith(fontFamily: 'packages/alas_shared/Manrope', color: t.colorScheme.primary)),
          if (sub != null) Text(sub!, style: t.textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.title, required this.children, this.empty});

  final String title;
  final List<Widget> children;
  final String? empty;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 4), child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
            if (children.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(empty ?? context.tr('app.empty'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              )
            else
              ...children,
          ]),
        ),
      );
}
