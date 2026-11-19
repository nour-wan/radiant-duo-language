import 'dart:async';

import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'statement_screen.dart';

import '../services/admin_api.dart';
import '../state/admin_session.dart';
import '../state/delivery_tracker.dart';
import '../widgets/admin_widgets.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.customerId, this.title});

  /// When set, shows only this customer's orders.
  final int? customerId;
  final String? title;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String? _status;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminApi>();
    final t = Theme.of(context);
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? context.tr('nav.orders')),
        actions: [
          IconButton(
            tooltip: context.tr('orders.export'),
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () async {
              try {
                final bytes = await api.exportOrders(status: _status);
                if (context.mounted) await shareCsv(context, bytes, 'alas-orders-${isoDate(DateTime.now())}.csv');
              } catch (e) {
                if (context.mounted) showSnack(context, context.trError(e), error: true);
              }
            },
          ),
        ],
      ),
      body: PagedList<OrderSummary>(
        key: ValueKey('$_status|$_q'),
        load: (page) => api.orders(page: page, status: _status, q: _q, customer: widget.customerId),
        header: Column(children: [
          if (widget.customerId == null) SearchBox(hint: context.tr('orders.search'), onChanged: (v) => setState(() => _q = v.trim())),
          SizedBox(
            height: 48,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
              ChoiceChip(label: Text(context.tr('app.all')), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
              for (final s in orderStatuses) ...[
                const SizedBox(width: 6),
                ChoiceChip(label: Text(context.tr(s == 'shipped' ? 'status.shipped_any' : 'status.$s')), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
              ],
            ]),
          ),
        ]),
        empty: EmptyView(icon: Icons.receipt_long_outlined, title: context.tr('orders.empty')),
        itemBuilder: (context, o, reload) => Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminOrderScreen(orderId: o.id)));
              reload();
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(o.number, style: t.textTheme.titleSmall),
                      const SizedBox(width: 8),
                      StatusChip(o.status, pickup: o.isPickup),
                    ]),
                    const SizedBox(height: 4),
                    Text(o.businessName.isNotEmpty ? '${o.businessName} · ${o.customerName}' : o.customerName, style: t.textTheme.bodyMedium),
                    Text('${formatDateTime(o.createdAt, lang)} · ${o.itemCount} ×',
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ]),
                ),
                Text(money(o.total), style: t.textTheme.titleMedium?.copyWith(fontFamily: 'packages/alas_shared/Manrope')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminOrderScreen extends StatefulWidget {
  const AdminOrderScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<AdminOrderScreen> createState() => _AdminOrderScreenState();
}

class _AdminOrderScreenState extends State<AdminOrderScreen> {
  OrderDetail? _order;
  Object? _error;
  final _note = TextEditingController();
  bool _busy = false;
  Timer? _live;

  @override
  void initState() {
    super.initState();
    _load();
    // While out for delivery, refresh so the driver's position on the map stays current
    _live = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_order?.status == 'shipped' && !_busy) _load();
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    _note.dispose();
    super.dispose();
  }

  int? get _me => context.read<AdminSession>().user?.id;

  /// Start or stop sharing this phone's location to match the order.
  Future<void> _syncTracking(OrderDetail o) async {
    final tracker = context.read<DeliveryTracker>();
    if (o.status == 'shipped' && !o.isPickup && o.driverId != null && o.driverId == _me) {
      if (!await tracker.start(o.id) && mounted) showSnack(context, context.tr('drv.permission'), error: true);
    } else if (tracker.orders.contains(o.id)) {
      await tracker.stop(o.id);
    }
  }

  Future<void> _takeDelivery() async {
    setState(() => _busy = true);
    try {
      final o = await context.read<AdminApi>().takeDelivery(widget.orderId);
      if (!mounted) return;
      setState(() => _order = o);
      await _syncTracking(o);
      if (mounted) showSnack(context, context.tr('drv.taken'));
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    try {
      final o = await context.read<AdminApi>().order(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = o;
        _error = null;
        _note.text = o.adminNote;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _changeStatus(String status) async {
    final noteCtl = TextEditingController();
    final paidCtl = TextEditingController();
    final o = _order!;
    final askPaid = status == 'delivered' && o.userId != null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('order.to', {'s': statusLabel(ctx, status, pickup: o.isPickup)})),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (status == 'cancelled') Text(ctx.tr('order.cancel_warning'), style: const TextStyle(color: AlasColors.destructive)),
          TextField(controller: noteCtl, decoration: InputDecoration(labelText: ctx.tr('order.status_note'))),
          if (askPaid) ...[
            const SizedBox(height: 12),
            if (o.creditApplied > 0)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: AlasColors.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)),
                child: Text(ctx.tr('pay.credit_hint', {'c': money(o.creditApplied), 'd': money(o.toCollect ?? 0)}),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            TextField(
              controller: paidCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: ctx.tr('pay.paid_now'),
                helperText: ctx.tr('pay.paid_now_hint'),
                helperMaxLines: 3,
                suffix: TextButton(
                  onPressed: () => paidCtl.text = (o.toCollect ?? (o.total - o.paidAmount)).clamp(0, double.infinity).toStringAsFixed(0),
                  child: Text(ctx.tr('pay.full')),
                ),
              ),
            ),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('app.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('app.confirm'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final paid = parseAmount(paidCtl.text);
      final o = await context.read<AdminApi>().setStatus(widget.orderId, status, note: noteCtl.text.trim(), paidAmount: paid != null && paid > 0 ? paid : null);
      if (!mounted) return;
      setState(() => _order = o);
      showSnack(context, context.tr('order.updated'));
      await _syncTracking(o);
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recordPayment() async {
    final o = _order!;
    final r = await askAmount(context, title: context.tr('pay.record'), full: (o.remaining ?? o.total - o.paidAmount));
    if (r == null || !mounted) return;
    try {
      final fresh = await context.read<AdminApi>().recordOrderPayment(o.id, r.amount, r.note);
      if (!mounted) return;
      setState(() => _order = fresh);
      showSnack(context, context.tr('pay.done'));
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    }
  }

  Future<void> _saveNote() async {
    try {
      await context.read<AdminApi>().setNote(widget.orderId, _note.text.trim());
      if (mounted) showSnack(context, context.tr('app.saved'));
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    }
  }

  /// Customer's pin with directions, who is delivering, and the live position while shipped.
  Widget _deliveryMap(BuildContext context, OrderDetail o) {
    final t = Theme.of(context);
    final tracker = context.watch<DeliveryTracker>();
    final mine = o.driverId != null && o.driverId == _me;
    final shipped = o.status == 'shipped';
    final driverAt = mine ? (tracker.lastPosition ?? o.tracking?.position) : o.tracking?.position;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (o.pin != null) ...[
        DeliveryMap(destination: o.pin, driver: shipped ? driverAt : null, height: 200),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => openDirections(o.pin!),
          icon: const Icon(Icons.directions),
          label: Text(context.tr('map.directions')),
        ),
      ] else
        Text(context.tr('map.no_pin'), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      if (shipped) ...[
        const Divider(height: 20),
        Row(children: [
          const Icon(Icons.local_shipping_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(o.driverName == null ? context.tr('drv.no_driver') : context.tr('drv.driver', {'n': o.driverName}))),
          if (!mine) TextButton(onPressed: _busy ? null : _takeDelivery, child: Text(context.tr('drv.take'))),
        ]),
        if (mine)
          Row(children: [
            Icon(tracker.isTracking(o.id) ? Icons.my_location : Icons.location_disabled,
                size: 18, color: tracker.isTracking(o.id) ? AlasColors.primary : AlasColors.destructive),
            const SizedBox(width: 8),
            Expanded(
              child: Text(context.tr(tracker.isTracking(o.id) ? 'drv.sharing' : 'drv.not_sharing'),
                  style: t.textTheme.bodySmall?.copyWith(color: tracker.isTracking(o.id) ? AlasColors.primary : AlasColors.destructive)),
            ),
            if (!tracker.isTracking(o.id)) TextButton(onPressed: () => _syncTracking(o), child: Text(context.tr('drv.start'))),
          ]),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final t = Theme.of(context);
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(title: Text(o == null ? '' : context.tr('order.title', {'n': o.number}))),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : o == null
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                    Row(children: [
                      StatusChip(o.status, pickup: o.isPickup),
                      const Spacer(),
                      Text(formatDateTime(o.createdAt, lang), style: t.textTheme.bodySmall),
                    ]),
                    const SizedBox(height: 12),
                    if (o.allowedStatuses.isNotEmpty)
                      FormCard(title: context.tr('order.change_status'), children: [
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final s in o.allowedStatuses)
                            FilledButton.tonal(
                              style: s == 'cancelled' ? FilledButton.styleFrom(foregroundColor: AlasColors.destructive) : null,
                              onPressed: _busy ? null : () => _changeStatus(s),
                              child: Text(statusLabel(context, s, pickup: o.isPickup)),
                            ),
                        ]),
                      ]),
                    FormCard(title: context.tr('order.customer'), children: [
                      if (o.customerDeleted)
                        Text(context.tr('order.deleted_customer'), style: const TextStyle(color: AlasColors.destructive))
                      else ...[
                        if (o.businessName.isNotEmpty) Text(o.businessName, style: t.textTheme.titleSmall),
                        Text(o.customerName),
                        Text(o.customerPhone, textDirection: TextDirection.ltr, textAlign: lang == 'ar' ? TextAlign.right : TextAlign.left),
                        if (o.customerEmail.isNotEmpty) Text(o.customerEmail, style: t.textTheme.bodySmall),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => launchUrl(Uri.parse('tel:${o.customerPhone}')),
                              icon: const Icon(Icons.call),
                              label: Text(context.tr('order.call')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => launchUrl(Uri.parse('https://wa.me/${_waNumber(o.customerPhone)}'), mode: LaunchMode.externalApplication),
                              icon: const Icon(Icons.chat),
                              label: Text(context.tr('order.whatsapp')),
                            ),
                          ),
                        ]),
                      ],
                    ]),
                    FormCard(title: context.tr(o.isPickup ? 'delivery.pickup' : 'delivery.delivery'), children: [
                      if (!o.isPickup) ...[
                        Text(o.address),
                        _deliveryMap(context, o),
                        if (o.deliveryZone.isNotEmpty) Text('${context.tr('order.zone')}: ${o.deliveryZone}', style: t.textTheme.bodySmall),
                        Text('${context.tr('order.delivery_fee')}: ${o.deliveryFee.toStringAsFixed(0)} ${o.deliveryCurrency}',
                            style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.primary)),
                      ],
                      if (o.notes.isNotEmpty) Text('${context.tr('order.customer_note')}: ${o.notes}'),
                    ]),
                    FormCard(title: context.tr('order.items'), children: [
                      for (final i in o.items)
                        Row(children: [
                          SizedBox.square(dimension: 44, child: NetImage(i.image, radius: 6)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(i.productName(lang), style: t.textTheme.titleSmall),
                              Text('${i.variantLabel(lang)} · ${money(i.unitPrice)} × ${i.quantity}', style: t.textTheme.bodySmall),
                            ]),
                          ),
                          Text(money(i.lineTotal), style: const TextStyle(fontFamily: 'packages/alas_shared/Manrope')),
                        ]),
                      const Divider(),
                      _row(context, context.tr('order.subtotal'), money(o.subtotal)),
                      if (o.discount > 0) _row(context, '${context.tr('order.coupon')} (${o.couponCode})', '- ${money(o.discount)}'),
                      if (o.appDiscount > 0) _row(context, '${context.tr('app_discount')} (${o.appDiscountPercent.toStringAsFixed(0)}%)', '- ${money(o.appDiscount)}'),
                      _row(context, context.tr('order.total'), money(o.total), bold: true),
                      if (o.totalUsd != null && o.exchangeRate != null)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(context.tr('rate.usd_total', {'usd': usd(o.totalUsd), 'rate': money(o.exchangeRate)}),
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      if (!o.isPickup && o.deliveryFee > 0)
                        _row(context, context.tr('order.delivery_fee'), '+ ${money(o.deliveryFee)}'),
                      if (!o.isPickup && o.deliveryFee > 0) _row(context, context.tr('order.grand_total'), money(o.total + o.deliveryFee), bold: true),
                      const SizedBox(height: 8),
                      InvoiceButton(number: o.number, load: (lang) => context.read<AdminApi>().invoicePdf(o.id, lang)),
                    ]),
                    if (o.status != 'cancelled')
                      FormCard(title: context.tr('pay.title'), children: [
                        for (final p in o.payments)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(children: [
                              const Icon(Icons.payments_outlined, size: 18, color: AlasColors.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  context.tr('staff.received_by', {'v': money(p.amount), 'n': p.byName ?? context.tr('staff.unknown')}),
                                  style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text(formatDateTime(p.createdAt, lang), style: t.textTheme.bodySmall),
                            ]),
                          ),
                        if (o.creditApplied > 0) _row(context, context.tr('ledger.credit_used_admin'), '- ${money(o.creditApplied)}'),
                        _row(context, context.tr('ledger.paid'), money(o.paidAmount)),
                        if (o.remaining == null && o.toCollect != null) _row(context, context.tr('ledger.to_collect_admin'), money(o.toCollect), bold: true),
                        if (o.remaining != null) _row(context, context.tr('ledger.remaining'), money(o.remaining), bold: true),
                        if (o.userId == null)
                          Text(context.tr('pay.no_customer'), style: t.textTheme.bodySmall)
                        else
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            FilledButton.tonalIcon(onPressed: _recordPayment, icon: const Icon(Icons.payments_outlined), label: Text(context.tr('pay.record'))),
                            OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomerStatementScreen(customerId: o.userId!))),
                              icon: const Icon(Icons.account_balance_wallet_outlined),
                              label: Text(context.tr('pay.statement')),
                            ),
                          ]),
                      ]),
                    FormCard(title: context.tr('order.note'), children: [
                      TextField(controller: _note, maxLines: 3, decoration: InputDecoration(hintText: context.tr('order.note_hint'))),
                      Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: _saveNote, child: Text(context.tr('app.save')))),
                    ]),
                    FormCard(title: context.tr('order.history'), children: [
                      for (final e in o.events.reversed)
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.circle, size: 10, color: StatusChip.color(e.status)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(statusLabel(context, e.status, pickup: o.isPickup), style: t.textTheme.titleSmall),
                              Text(
                                [formatDateTime(e.createdAt, lang), if (e.byName != null) context.tr('staff.by', {'n': e.byName})].join(' · '),
                                style: t.textTheme.bodySmall,
                              ),
                              if (e.note.isNotEmpty) Text(e.note, style: t.textTheme.bodySmall),
                            ]),
                          ),
                        ]),
                    ]),
                  ]),
                ),
    );
  }

  /// Syrian local numbers (09…) → 9639… for WhatsApp links.
  static String _waNumber(String phone) {
    var p = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (p.startsWith('00')) p = p.substring(2);
    if (p.startsWith('0')) p = '963${p.substring(1)}';
    return p;
  }

  Widget _row(BuildContext context, String label, String value, {bool bold = false}) => Row(children: [
        Expanded(child: Text(label, style: bold ? Theme.of(context).textTheme.titleSmall : null)),
        Text(value, style: TextStyle(fontFamily: 'packages/alas_shared/Manrope', fontWeight: bold ? FontWeight.w700 : null)),
      ]);
}
