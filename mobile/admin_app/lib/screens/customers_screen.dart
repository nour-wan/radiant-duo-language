import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/admin_api.dart';
import '../state/admin_session.dart';
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
  int _version = 0;

  Future<void> _add() async {
    final added = await Navigator.of(context).push<AdminCustomer>(MaterialPageRoute(builder: (_) => const AddCustomerScreen()));
    if (added != null && mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminApi>();
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('nav.customers'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-customer',
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt),
        label: Text(context.tr('cust.add')),
      ),
      body: PagedList<AdminCustomer>(
        key: ValueKey('$_q|$_type|$_version'),
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
              if (c.distributorName != null && context.read<AdminSession>().isOwner) context.tr('dist.via', {'n': c.distributorName}),
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

  /// Owner: move the customer to a distributor, or back to the store.
  Future<void> _changeDistributor() async {
    final api = context.read<AdminApi>();
    List<Map<String, dynamic>> people;
    try {
      people = (await api.staff()).where((w) => w['is_distributor'] == true && w['is_active'] == true).toList();
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
      return;
    }
    if (!mounted) return;
    const store = -1;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.tr('dist.move')),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, store), child: Text(ctx.tr('dist.store_customer'))),
          for (final w in people)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, w['id'] as int),
              child: Text('${w['full_name']} (${w['distributor_code'] ?? ''})'),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await api.setCustomerDistributor(c.id, picked == store ? null : picked);
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
    final session = context.watch<AdminSession>();
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
          if (session.isOwner)
            Row(children: [
              const Icon(Icons.handshake_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(c.distributorName == null ? context.tr('dist.store_customer') : context.tr('dist.via', {'n': c.distributorName}))),
              TextButton(onPressed: _changeDistributor, child: Text(context.tr('dist.change'))),
            ]),
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
        // Switching a customer off is not for distributors (only the store does that)
        if (!session.isDistributor)
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


/// Adds a customer: name, phone, business and area. The customer signs in later in the store app
/// with "Forgot password" (a code to their WhatsApp) and sets their own password.
class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _business = TextEditingController();
  final _address = TextEditingController();
  String? _type;
  int? _areaId;
  List<DeliveryZone> _zones = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.read<AdminApi>().zones().then((z) => mounted ? setState(() => _zones = z) : null).catchError((_) => null);
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _business, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? context.tr('app.required') : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final c = await context.read<AdminApi>().addCustomer({
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'business_name': _business.text.trim(),
        if (_type != null) 'business_type': _type,
        'delivery_area': _areaId,
        'address': _address.text.trim(),
      });
      if (!mounted) return;
      showSnack(context, context.tr('cust.added'));
      Navigator.of(context).pop(c);
    } on ApiException catch (e) {
      if (!mounted) return;
      final errors = e.extra['errors'];
      showSnack(
        context,
        errors is Map ? errors.values.expand((v) => v is List ? v : [v]).map((m) => L10n.error(context.lang, ApiException('invalid', '$m'))).join('\n') : context.trError(e),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final areas = [
      for (final z in _zones)
        for (final a in z.areas)
          if (a.isActive && a.id != null) a,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('cust.add'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: _name, decoration: InputDecoration(labelText: context.tr('cust.f_name')), validator: _req),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: context.tr('staff.phone'), hintText: '09xxxxxxxx'),
            validator: _req,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _business, decoration: InputDecoration(labelText: context.tr('cust.f_business')), validator: _req),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: InputDecoration(labelText: context.tr('cust.f_type')),
            items: [for (final b in businessTypes) DropdownMenuItem(value: b, child: Text(context.tr('biz.$b')))],
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _areaId,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.tr('cust.f_area')),
            items: [for (final a in areas) DropdownMenuItem(value: a.id, child: Text(pick(lang, a.nameAr, a.nameEn)))],
            onChanged: (v) => setState(() => _areaId = v),
            validator: (v) => v == null ? context.tr('app.required') : null,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _address, maxLines: 2, decoration: InputDecoration(labelText: context.tr('cust.f_address'))),
          const SizedBox(height: 12),
          Text(context.tr('cust.add_hint'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(context.tr('app.save')),
          ),
        ]),
      ),
    );
  }
}
