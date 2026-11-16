import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/admin_api.dart';
import '../widgets/admin_widgets.dart';
import 'orders_screen.dart';

/// A customer's account: balance, credit limit, payments and corrections.
class CustomerStatementScreen extends StatefulWidget {
  const CustomerStatementScreen({super.key, required this.customerId});

  final int customerId;

  @override
  State<CustomerStatementScreen> createState() => _CustomerStatementScreenState();
}

class _CustomerStatementScreenState extends State<CustomerStatementScreen> {
  AdminCustomer? _customer;
  Statement? _statement;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AdminApi>();
    try {
      final results = await Future.wait([api.customer(widget.customerId), api.statement(widget.customerId)]);
      if (!mounted) return;
      setState(() {
        _customer = results[0] as AdminCustomer;
        _statement = results[1] as Statement;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (!mounted) return;
      showSnack(context, context.tr(done));
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    }
  }

  Future<void> _payment() async {
    final balance = _statement!.summary.balance;
    final r = await askAmount(context, title: context.tr('pay.record'), full: balance > 0 ? balance : null);
    if (r == null || !mounted) return;
    await _run(() => context.read<AdminApi>().recordPayment(widget.customerId, r.amount, r.note), 'pay.done');
  }

  Future<void> _adjust() async {
    final r = await askAmount(context, title: context.tr('pay.adjust'), signed: true, noteRequired: true, hint: context.tr('pay.adjust_hint'));
    if (r == null || !mounted) return;
    await _run(() => context.read<AdminApi>().recordAdjustment(widget.customerId, r.amount, r.note), 'app.saved');
  }

  Future<void> _editLimit() async {
    final ctl = TextEditingController(text: _customer?.creditLimit?.toStringAsFixed(2) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('pay.limit')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: ctx.tr('pay.amount'), helperText: ctx.tr('pay.limit_hint'), helperMaxLines: 2),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('app.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('app.save'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final text = ctl.text.trim();
    final limit = text.isEmpty ? null : parseAmount(text);
    if (text.isNotEmpty && (limit == null || limit < 0)) {
      showSnack(context, context.tr('err.invalid_amount'), error: true);
      return;
    }
    await _run(() => context.read<AdminApi>().setCreditLimit(widget.customerId, limit), 'app.saved');
  }

  Future<void> _export() async {
    try {
      final bytes = await context.read<AdminApi>().statementCsv(widget.customerId);
      if (mounted) await shareCsv(context, bytes, 'statement_${widget.customerId}.csv');
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _customer, st = _statement;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null ? context.tr('ledger.title') : (c.businessName.isNotEmpty ? c.businessName : c.fullName)),
        actions: [IconButton(tooltip: context.tr('orders.export'), onPressed: st == null ? null : _export, icon: const Icon(Icons.ios_share))],
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : st == null || c == null
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                    Card(
                      child: SwitchListTile(
                        value: c.creditEnabled,
                        secondary: Icon(Icons.credit_score_outlined, color: c.creditEnabled ? t.colorScheme.primary : null),
                        title: Text(context.tr('credit.enable')),
                        subtitle: Text(context.tr(c.creditEnabled ? 'credit.on_hint' : 'credit.off_hint')),
                        onChanged: (on) => _run(() => context.read<AdminApi>().setCreditEnabled(widget.customerId, on), 'app.saved'),
                      ),
                    ),
                    BalanceCard(summary: st.summary, admin: true, actions: [
                      FilledButton.icon(onPressed: _payment, icon: const Icon(Icons.payments_outlined), label: Text(context.tr('pay.record'))),
                      OutlinedButton.icon(onPressed: _adjust, icon: const Icon(Icons.edit_note), label: Text(context.tr('pay.adjust'))),
                      if (c.creditEnabled)
                        OutlinedButton.icon(onPressed: _editLimit, icon: const Icon(Icons.speed), label: Text(context.tr('pay.limit'))),
                    ]),
                    if (c.creditEnabled && c.creditLimit != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text('${context.tr('pay.limit')}: ${money(c.creditLimit)}', style: t.textTheme.bodySmall),
                      ),
                    const SizedBox(height: 8),
                    if (st.entries.items.isEmpty)
                      Padding(padding: const EdgeInsets.all(32), child: Text(context.tr('ledger.empty'), textAlign: TextAlign.center))
                    else
                      Card(
                        child: Column(children: [
                          for (final e in st.entries.items)
                            LedgerEntryTile(
                              entry: e,
                              showAuthor: true,
                              onOpenOrder: (id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminOrderScreen(orderId: id))),
                            ),
                        ]),
                      ),
                  ]),
                ),
    );
  }
}

/// All customers with an open balance, largest debt first.
class ReceivablesScreen extends StatefulWidget {
  const ReceivablesScreen({super.key});

  @override
  State<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends State<ReceivablesScreen> {
  final _key = GlobalKey();

  Future<void> _export() async {
    try {
      final bytes = await context.read<AdminApi>().receivablesCsv();
      if (mounted) await shareCsv(context, bytes, 'receivables.csv');
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminApi>();
    final t = Theme.of(context);
    const numbers = TextStyle(fontFamily: 'packages/alas_shared/Manrope', fontWeight: FontWeight.w700);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('more.receivables')),
        actions: [IconButton(tooltip: context.tr('orders.export'), onPressed: _export, icon: const Icon(Icons.ios_share))],
      ),
      body: AsyncView<({double total, List<Map<String, dynamic>> rows})>(
        key: _key,
        load: api.receivables,
        builder: (context, data, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: ListTile(
                title: Text(context.tr('recv.total')),
                trailing: Text(money(data.total), style: numbers.copyWith(fontSize: 20, color: AlasColors.destructive)),
              ),
            ),
            if (data.rows.isEmpty)
              EmptyView(icon: Icons.check_circle_outline, title: context.tr('recv.empty'))
            else
              for (final r in data.rows) _row(context, r, reload, numbers, t),
          ]),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> r, Future<void> Function() reload, TextStyle numbers, ThemeData t) {
    final balance = toMoney(r['balance']);
    final limit = toMoneyOrNull(r['credit_limit']);
    final business = r['business_name'] as String? ?? '';
    final name = r['full_name'] as String? ?? '';
    return Card(
      child: ListTile(
        title: Text(business.isNotEmpty ? business : name),
        subtitle: Text([if (business.isNotEmpty) name, r['phone'] ?? '', r['area_name'] ?? ''].where((s) => '$s'.isNotEmpty).join(' · ')),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(money(balance.abs()), style: numbers.copyWith(color: balance > 0 ? AlasColors.destructive : t.colorScheme.primary)),
          if (balance < 0) Text(context.tr('ledger.balance_credit_admin'), style: t.textTheme.bodySmall),
          if (limit != null && balance > limit)
            Text(context.tr('recv.over_limit'), style: t.textTheme.bodySmall?.copyWith(color: AlasColors.destructive)),
        ]),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomerStatementScreen(customerId: r['id'] as int)));
          reload();
        },
      ),
    );
  }
}
