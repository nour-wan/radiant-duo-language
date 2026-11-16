import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/admin_api.dart';
import '../widgets/admin_widgets.dart';
import 'orders_screen.dart';
import 'statement_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _q = '';
  String? _type;

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminApi>();
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('nav.customers'))),
      body: PagedList<AdminCustomer>(
        key: ValueKey('$_q|$_type'),
        load: (page) => api.customers(page: page, q: _q, businessType: _type),
        header: Column(children: [
          SearchBox(hint: context.tr('cust.search'), onChanged: (v) => setState(() => _q = v.trim())),
          SizedBox(
            height: 48,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
              ChoiceChip(label: Text(context.tr('cust.all_types')), selected: _type == null, onSelected: (_) => setState(() => _type = null)),
              for (final b in businessTypes) ...[
                const SizedBox(width: 6),
                ChoiceChip(label: Text(context.tr('biz.$b')), selected: _type == b, onSelected: (_) => setState(() => _type = b)),
              ],
            ]),
          ),
        ]),
        empty: EmptyView(icon: Icons.people_outline, title: context.tr('cust.empty')),
        itemBuilder: (context, c, reload) => Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: c.isActive ? t.colorScheme.primaryContainer : AlasColors.destructive.withValues(alpha: .15),
              child: Text(c.fullName.isNotEmpty ? c.fullName.characters.first : '?'),
            ),
            title: Text(c.businessName.isNotEmpty ? c.businessName : c.fullName),
            subtitle: Text([
              if (c.businessName.isNotEmpty) c.fullName,
              if (c.businessType.isNotEmpty) context.tr('biz.${c.businessType}'),
              if (c.areaName.isNotEmpty) c.areaName,
            ].join(' · ')),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(c.totalSpent), style: const TextStyle(fontFamily: 'packages/alas_shared/Manrope', fontWeight: FontWeight.w700)),
              Text('${c.orderCount} ×', style: t.textTheme.bodySmall),
              if (c.balance > 0)
                Text('−${money(c.balance)}', style: t.textTheme.bodySmall?.copyWith(color: AlasColors.destructive, fontFamily: 'packages/alas_shared/Manrope')),
            ]),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomerDetailScreen(customer: c)));
              reload();
            },
          ),
        ),
      ),
    );
  }
}

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customer});

  final AdminCustomer customer;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late AdminCustomer c = widget.customer;

  Future<void> _toggleActive() async {
    final api = context.read<AdminApi>();
    try {
      await api.setCustomerActive(c.id, !c.isActive);
      final fresh = await api.customer(c.id);
      if (mounted) setState(() => c = fresh);
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(title: Text(c.businessName.isNotEmpty ? c.businessName : c.fullName)),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        FormCard(title: context.tr('order.customer'), children: [
          Text(c.fullName, style: t.textTheme.titleMedium),
          if (c.businessType.isNotEmpty) Text('${context.tr('biz.${c.businessType}')} · ${c.businessName}'),
          if (c.areaName.isNotEmpty) Text('${c.areaName} — ${c.address}'),
          if (c.email.isNotEmpty) Text(c.email, style: t.textTheme.bodySmall),
          Row(children: [
            Icon(c.phoneVerified ? Icons.verified_outlined : Icons.help_outline, size: 16,
                color: c.phoneVerified ? AlasColors.primary : t.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(context.tr(c.phoneVerified ? 'cust.phone_verified' : 'cust.phone_unverified'), style: t.textTheme.bodySmall),
            if (c.creditEnabled) ...[
              const SizedBox(width: 12),
              const Icon(Icons.credit_score_outlined, size: 16, color: AlasColors.primary),
              const SizedBox(width: 4),
              Text(context.tr('credit.enabled_badge'), style: t.textTheme.bodySmall),
            ],
          ]),
          Text(context.tr('cust.joined', {'d': formatDate(c.dateJoined, lang)}), style: t.textTheme.bodySmall),
          Text(context.tr('cust.orders', {'n': c.orderCount, 'v': money(c.totalSpent)}), style: t.textTheme.titleSmall),
          if (!c.isActive) Text(context.tr('cust.disabled'), style: const TextStyle(color: AlasColors.destructive, fontWeight: FontWeight.w700)),
          if (c.phone.isNotEmpty)
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse('tel:${c.phone}')), icon: const Icon(Icons.call), label: Text(c.phone))),
            ]),
        ]),
        if (c.interests.isNotEmpty)
          FormCard(title: context.tr('cust.interests'), children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final i in c.interests) Chip(label: Text(pick(lang, i['name_ar'] as String?, i['name_en'] as String?))),
            ]),
          ]),
        FilledButton.icon(
          onPressed: () async {
            final api = context.read<AdminApi>();
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomerStatementScreen(customerId: c.id)));
            final fresh = await api.customer(c.id);
            if (mounted) setState(() => c = fresh);
          },
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: Text(c.balance > 0 ? '${context.tr('ledger.title')} · −${money(c.balance)}' : context.tr('ledger.title')),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => OrdersScreen(customerId: c.id, title: context.tr('cust.order_history')))),
          icon: const Icon(Icons.receipt_long_outlined),
          label: Text(context.tr('cust.order_history')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: c.isActive ? AlasColors.destructive : AlasColors.primary),
          onPressed: _toggleActive,
          icon: Icon(c.isActive ? Icons.block : Icons.check_circle_outline),
          label: Text(context.tr(c.isActive ? 'cust.block' : 'cust.unblock')),
        ),
      ]),
    );
  }
}
