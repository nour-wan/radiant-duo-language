import 'dart:math';

import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/store_api.dart';
import '../state/cart.dart';
import '../state/session.dart';
import '../widgets/common.dart';
import '../widgets/pin_field.dart';
import '../widgets/profile_form.dart';
import 'account/legal_screen.dart';
import 'orders/order_detail_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _form = GlobalKey<FormState>();
  late final AppUser _user = context.read<Session>().user!;
  late final _name = TextEditingController(text: _user.fullName);
  late final _phone = TextEditingController(text: _user.phone);
  late final _business = TextEditingController(text: _user.businessName);
  final _details = TextEditingController();
  final _notes = TextEditingController();
  DeliveryInfo? _info;
  List<Address>? _addresses;
  int? _addressId; // null = new address
  AreaChoice? _newArea;
  LatLng? _newPin;
  String _method = 'delivery';
  bool _saveAddress = true;
  bool _placing = false;
  Object? _loadError;
  // Same reference for retries so a double tap never creates two orders.
  final _clientRef = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<StoreApi>();
    try {
      final results = await Future.wait([api.delivery(), api.addresses()]);
      if (!mounted) return;
      final info = results[0] as DeliveryInfo;
      final list = results[1] as List<Address>;
      setState(() {
        _info = info;
        _addresses = list;
        _addressId = list.where((a) => a.isDefault).firstOrNull?.id ?? list.firstOrNull?.id;
        _method = info.deliveryEnabled ? 'delivery' : 'pickup';
        _loadError = null;
      });
      _syncQuote();
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  int? get _areaId {
    if (_method != 'delivery') return null;
    if (_addressId != null) return _addresses?.where((a) => a.id == _addressId).firstOrNull?.deliveryAreaId;
    return _newArea?.id;
  }

  void _syncQuote() => context.read<Cart>().setDelivery(_method, _areaId);

  @override
  void dispose() {
    for (final c in [_name, _phone, _business, _details, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _place() async {
    if (!_form.currentState!.validate()) return;
    final cart = context.read<Cart>();
    final api = context.read<StoreApi>();
    setState(() => _placing = true);
    try {
      var addressId = _method == 'delivery' ? _addressId : null;
      if (_method == 'delivery' && addressId == null && _saveAddress) {
        final saved = await api.saveAddress(Address(
          label: _business.text.trim(),
          recipientName: _name.text.trim(),
          phone: _phone.text.trim(),
          deliveryAreaId: _newArea?.id,
          area: _newArea?.name ?? '',
          details: _details.text.trim(),
          latitude: _newPin?.latitude,
          longitude: _newPin?.longitude,
          isDefault: (_addresses ?? []).isEmpty,
        ));
        addressId = _addressId = saved.id;
      }
      final order = await api.placeOrder({
        'items': cart.items,
        if (cart.coupon != null) 'coupon_code': cart.coupon,
        'client_ref': _clientRef,
        'customer_name': _name.text.trim(),
        'customer_phone': _phone.text.trim(),
        'business_name': _business.text.trim(),
        'delivery_method': _method,
        if (addressId != null) 'address_id': addressId,
        if (_method == 'delivery' && addressId == null) ...{
          'delivery_area_id': _newArea?.id,
          'area': _newArea?.name ?? '',
          'address_details': _details.text.trim(),
          if (_newPin != null) 'latitude': _newPin!.latitude.toStringAsFixed(6),
          if (_newPin != null) 'longitude': _newPin!.longitude.toStringAsFixed(6),
        },
        'notes': _notes.text.trim(),
        // The total the customer saw; if the dollar rate moved since, the server asks to confirm again
        if (cart.quote != null) 'expected_total': cart.quote!.total.toStringAsFixed(2),
      });
      cart.clear();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => _SuccessScreen(order: order)), (r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, context.trError(e), error: true);
      cart.refreshQuote();
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? context.tr('app.required') : null;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final q = cart.quote;
    final lang = context.lang;
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('co.title'))),
      body: _loadError != null
          ? ErrorView(error: _loadError!, onRetry: _load)
          : info == null
              ? const LoadingView()
              : Form(
                  key: _form,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    if (info.appDiscountPercent > 0) _AppDiscountBanner(percent: info.appDiscountPercent),
                    _Section(title: context.tr('co.contact'), children: [
                      TextFormField(controller: _name, decoration: InputDecoration(labelText: context.tr('co.name')), validator: _required),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(labelText: context.tr('profile.contact_phone')),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(controller: _business, decoration: InputDecoration(labelText: context.tr('profile.business_name'))),
                    ]),
                    _Section(title: context.tr('co.delivery_method'), children: [
                      if (info.deliveryEnabled)
                        _MethodTile(
                          selected: _method == 'delivery',
                          icon: Icons.local_shipping_outlined,
                          title: context.tr('delivery.delivery'),
                          subtitle: context.tr('co.delivery_hint'),
                          onTap: () {
                            setState(() => _method = 'delivery');
                            _syncQuote();
                          },
                        ),
                      if (info.pickupEnabled)
                        _MethodTile(
                          selected: _method == 'pickup',
                          icon: Icons.storefront_outlined,
                          title: context.tr('delivery.pickup'),
                          subtitle: context.tr('co.pickup_hint', {'a': info.pickupAddress(lang)}),
                          trailing: context.tr('delivery.free'),
                          onTap: () {
                            setState(() => _method = 'pickup');
                            _syncQuote();
                          },
                        ),
                    ]),
                    if (_method == 'delivery') _addressSection(context, info),
                    _Section(title: context.tr('co.payment'), children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(Icons.payments_outlined, color: Theme.of(context).colorScheme.primary),
                        ),
                        title: Text(context.tr('co.cod')),
                        subtitle: Text(context.tr('co.cod_hint')),
                        trailing: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                      ),
                    ]),
                    _Section(title: context.tr('co.notes'), children: [TextFormField(controller: _notes, maxLines: 3, maxLength: 500)]),
                    _Section(title: context.tr('co.summary'), children: [
                      for (final l in cart.lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            Expanded(child: Text('${l.name(lang)} · ${l.label(lang)} × ${l.quantity}', style: Theme.of(context).textTheme.bodySmall)),
                            Text(money(l.total), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'packages/alas_shared/Manrope')),
                          ]),
                        ),
                      const Divider(height: 20),
                      OrderTotals(quote: q, fallbackSubtotal: cart.localSubtotal),
                    ]),
                    InkWell(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LegalScreen(slug: 'returns'))),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(context.tr('co.agree'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  decoration: TextDecoration.underline,
                                )),
                      ),
                    ),
                    const SizedBox(height: 80),
                  ]),
                ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _placing || cart.isEmpty || info == null || cart.quoting ? null : _place,
            child: _placing
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text('${context.tr('co.place')} · ${money(q?.total ?? cart.localSubtotal)}'),
          ),
        ),
      ),
    );
  }

  Address? get _selectedAddress => _addressId == null ? null : _addresses?.where((a) => a.id == _addressId).firstOrNull;

  Future<void> _pinAddress(Address a, LatLng p) async {
    try {
      final saved = await context.read<StoreApi>().saveAddress(Address(
        id: a.id, label: a.label, recipientName: a.recipientName, phone: a.phone, city: a.city, deliveryAreaId: a.deliveryAreaId,
        area: a.area, street: a.street, details: a.details, latitude: p.latitude, longitude: p.longitude, isDefault: a.isDefault,
      ));
      if (!mounted) return;
      setState(() => _addresses = [for (final x in _addresses ?? <Address>[]) x.id == saved.id ? saved : x]);
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    }
  }

  Widget _addressSection(BuildContext context, DeliveryInfo info) {
    final q = context.watch<Cart>().quote;
    const newAddress = -1;
    return _Section(title: context.tr('co.address'), children: [
      RadioGroup<int>(
        groupValue: _addressId ?? newAddress,
        onChanged: (v) {
          setState(() => _addressId = v == newAddress ? null : v);
          _syncQuote();
        },
        child: Column(children: [
          for (final a in _addresses ?? <Address>[])
            RadioListTile<int>(
              contentPadding: EdgeInsets.zero,
              value: a.id!,
              title: Text(a.label.isNotEmpty ? a.label : a.recipientName),
              subtitle: Text('${a.oneLine}\n${a.phone}'),
              isThreeLine: true,
            ),
          RadioListTile<int>(contentPadding: EdgeInsets.zero, value: newAddress, title: Text(context.tr('co.new_address'))),
        ]),
      ),
      // A saved address without a map pin: offer to add one (saved on the address for next time)
      if (_selectedAddress case final a? when a.pin == null) ...[
        PinField(value: null, onChanged: (p) => _pinAddress(a, p)),
        const SizedBox(height: 4),
      ],
      if (_addressId == null) ...[
        AreaField(
          info: info,
          initialValue: _newArea,
          onChanged: (a) {
            setState(() => _newArea = a);
            _syncQuote();
          },
          validator: (v) => v == null ? context.tr('app.required') : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _details,
          maxLines: 2,
          decoration: InputDecoration(labelText: context.tr('profile.address'), hintText: context.tr('profile.address_hint')),
          validator: _required,
        ),
        const SizedBox(height: 12),
        PinField(value: _newPin, onChanged: (p) => setState(() => _newPin = p)),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _saveAddress,
          onChanged: (v) => setState(() => _saveAddress = v ?? false),
          title: Text(context.tr('co.save_address')),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
      if (q != null && q.deliveryMethod == 'delivery') ...[
        const Divider(height: 20),
        Row(children: [
          const Icon(Icons.local_shipping_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(context.tr('co.delivery_fee'))),
          Text(money(q.deliveryFee), style: Theme.of(context).textTheme.titleSmall),
        ]),
        if (!q.deliveryAreaListed && (_addressId != null || _newArea != null))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              context.tr('co.fee_estimate', {'fee': money(q.deliveryFee)}),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AlasColors.warning),
            ),
          ),
      ],
    ]);
  }
}

/// Subtotal, coupon, app discount and total plus the delivery fee (all in Syrian pounds).
class OrderTotals extends StatelessWidget {
  const OrderTotals({super.key, required this.quote, required this.fallbackSubtotal});

  final Quote? quote;
  final double fallbackSubtotal;

  @override
  Widget build(BuildContext context) {
    final q = quote;
    return Column(children: [
      SummaryRow(context.tr('cart.subtotal'), money(q?.subtotal ?? fallbackSubtotal)),
      if ((q?.discount ?? 0) > 0) SummaryRow('${context.tr('cart.discount')} (${q!.couponCode})', '- ${money(q.discount)}', color: AlasColors.sale),
      if ((q?.appDiscount ?? 0) > 0)
        SummaryRow('${context.tr('app_discount')} (${q!.appDiscountPercent.toStringAsFixed(q.appDiscountPercent % 1 == 0 ? 0 : 1)}%)',
            '- ${money(q.appDiscount)}',
            color: AlasColors.primary),
      const Divider(height: 18),
      SummaryRow(context.tr('cart.total'), money(q?.total ?? fallbackSubtotal), bold: true),
      if (q != null && q.creditToApply > 0) ...[
        SummaryRow(context.tr('ledger.credit_used'), '- ${money(q.creditToApply)}', color: AlasColors.primary),
        SummaryRow(context.tr('ledger.to_collect'), money(q.dueOnDelivery ?? 0), bold: true),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(context.tr('co.credit_note', {'c': money(q.accountCredit)}),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AlasColors.primary)),
        ),
      ],
      if (q != null && q.deliveryMethod == 'delivery' && q.deliveryFee > 0) ...[
        SummaryRow(context.tr('co.delivery_fee'), '+ ${money(q.deliveryFee)}'),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(context.tr('co.delivery_fee_note'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        const Divider(height: 18),
        SummaryRow(context.tr('co.pay_on_receipt'), money((q.dueOnDelivery ?? q.total) + q.deliveryFee), bold: true),
      ],
    ]);
  }
}

class _AppDiscountBanner extends StatelessWidget {
  const _AppDiscountBanner({required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(Icons.phone_iphone, color: t.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(context.tr('co.app_discount_banner', {'p': percent.toStringAsFixed(percent % 1 == 0 ? 0 : 1)}),
              style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.onPrimaryContainer)),
        ),
      ]),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.selected, required this.icon, required this.title, required this.subtitle, required this.onTap, this.trailing});

  final bool selected;
  final IconData icon;
  final String title, subtitle;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? scheme.primary : scheme.outline, width: selected ? 1.6 : 1),
          ),
          child: Row(children: [
            Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
            if (trailing != null) Text(trailing!, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary)),
            const SizedBox(width: 6),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? scheme.primary : scheme.outline),
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ]),
          ),
        ),
      );
}

class _SuccessScreen extends StatelessWidget {
  const _SuccessScreen({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(color: t.colorScheme.primaryContainer, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, size: 64, color: t.colorScheme.primary),
              ),
            ),
            const SizedBox(height: 28),
            Text(context.tr('co.success'), style: t.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(context.tr('co.success_body', {'n': order.number}),
                style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(money(order.total),
                textAlign: TextAlign.center,
                style: t.textTheme.headlineSmall?.copyWith(color: t.colorScheme.primary, fontFamily: 'packages/alas_shared/Manrope')),
            if (!order.isPickup && order.deliveryFee > 0)
              Text('+ ${money(order.deliveryFee)} ${context.tr('co.delivery_fee')}', textAlign: TextAlign.center, style: t.textTheme.titleSmall),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id))),
              child: Text(context.tr('co.view_order')),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('co.continue'))),
          ]),
        ),
      ),
    );
  }
}
