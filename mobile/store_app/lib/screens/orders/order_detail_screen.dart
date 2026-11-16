import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/store_api.dart';
import '../../state/cart.dart';
import '../../widgets/common.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Key _key = UniqueKey();

  Future<void> _cancel(OrderDetail o) async {
    if (!await confirmDialog(context, title: context.tr('orders.cancel_confirm'), danger: true) || !mounted) return;
    try {
      await context.read<StoreApi>().cancelOrder(o.id);
      if (!mounted) return;
      showSnack(context, context.tr('orders.cancelled'));
      setState(() => _key = UniqueKey());
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    }
  }

  void _reorder(OrderDetail o) {
    final cart = context.read<Cart>();
    for (final item in o.items) {
      cart.addFromOrder(item, item.quantity);
    }
    showSnack(context, context.tr('orders.reordered'));
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<StoreApi>();
    final t = Theme.of(context);
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('orders.tracking'))),
      body: AsyncView<OrderDetail>(
        key: _key,
        load: () => api.order(widget.orderId),
        builder: (context, o, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: Text(context.tr('orders.number', {'n': o.number}), style: t.textTheme.titleLarge)),
              StatusChip(o.status, pickup: o.isPickup),
            ]),
            Text(formatDateTime(o.createdAt, lang), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            _Timeline(order: o),
            const SizedBox(height: 16),
            _card(context, context.tr('orders.items_title'), [
              for (final i in o.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    SizedBox.square(dimension: 52, child: NetImage(i.image, radius: 8)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(i.productName(lang), style: t.textTheme.titleSmall),
                        Text('${i.variantLabel(lang)} · ${money(i.unitPrice)} × ${i.quantity}',
                            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                      ]),
                    ),
                    Text(money(i.lineTotal), style: t.textTheme.bodyMedium?.copyWith(fontFamily: 'packages/alas_shared/Manrope')),
                  ]),
                ),
              const Divider(height: 20),
              SummaryRow(context.tr('cart.subtotal'), money(o.subtotal)),
              if (o.discount > 0) SummaryRow('${context.tr('cart.discount')} (${o.couponCode})', '- ${money(o.discount)}', color: AlasColors.sale),
              if (o.appDiscount > 0)
                SummaryRow('${context.tr('app_discount')} (${o.appDiscountPercent.toStringAsFixed(0)}%)', '- ${money(o.appDiscount)}', color: AlasColors.primary),
              SummaryRow(context.tr('cart.total'), money(o.total), bold: true),
              if (!o.isPickup && o.deliveryFee > 0) SummaryRow(context.tr('co.delivery_fee'), '+ ${o.deliveryFee.toStringAsFixed(0)} ${o.deliveryCurrency}'),
              if (o.creditApplied > 0) ...[
                const Divider(height: 20),
                SummaryRow(context.tr('ledger.credit_used'), '- ${money(o.creditApplied)}', color: AlasColors.primary),
                if (o.remaining == null && o.toCollect != null) SummaryRow(context.tr('ledger.to_collect'), money(o.toCollect), bold: true),
              ],
              if (o.paidAmount > 0 || o.remaining != null) ...[
                const Divider(height: 20),
                SummaryRow(context.tr('ledger.paid'), money(o.paidAmount), color: AlasColors.primary),
                if (o.remaining != null)
                  SummaryRow(context.tr('ledger.remaining'), money(o.remaining), bold: true,
                      color: o.remaining! > 0 ? AlasColors.destructive : AlasColors.primary),
              ],
              const SizedBox(height: 12),
              InvoiceButton(number: o.number, load: (lang) => api.invoicePdf(o.id, lang)),
            ]),
            const SizedBox(height: 12),
            _card(context, context.tr('orders.delivery'), [
              Text(o.isPickup ? context.tr('delivery.pickup') : context.tr('delivery.delivery'), style: t.textTheme.titleSmall),
              if (o.businessName.isNotEmpty) Text(o.businessName),
              Text('${o.customerName} · ${o.customerPhone}'),
              if (!o.isPickup && o.address.isNotEmpty) Text(o.address),
              const SizedBox(height: 6),
              Text('${context.tr('orders.payment')}: ${context.tr('co.cod')}', style: t.textTheme.bodySmall),
              if (o.notes.isNotEmpty) ...[const SizedBox(height: 6), Text('${context.tr('orders.notes')}: ${o.notes}', style: t.textTheme.bodySmall)],
            ]),
            const SizedBox(height: 16),
            if (o.canCancel)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AlasColors.destructive),
                onPressed: () => _cancel(o),
                icon: const Icon(Icons.cancel_outlined),
                label: Text(context.tr('orders.cancel')),
              ),
            if (o.status == 'delivered' || o.status == 'cancelled')
              FilledButton.icon(onPressed: () => _reorder(o), icon: const Icon(Icons.replay), label: Text(context.tr('orders.reorder'))),
          ]),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );
}

/// Pending → confirmed → shipped → delivered, with dates from the order history.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lang = context.lang;
    if (order.status == 'cancelled') {
      final event = order.events.where((e) => e.status == 'cancelled').lastOrNull;
      return Card(
        color: AlasColors.destructive.withValues(alpha: .08),
        child: ListTile(
          leading: const Icon(Icons.cancel, color: AlasColors.destructive),
          title: Text(context.tr('status.cancelled')),
          subtitle: event == null
              ? null
              : Text([formatDateTime(event.createdAt, lang), if (event.note.isNotEmpty) event.note].join('\n')),
        ),
      );
    }
    const steps = ['pending', 'confirmed', 'shipped', 'delivered'];
    final current = steps.indexOf(order.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          for (var i = 0; i < steps.length; i++)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 56,
                child: Column(children: [
                  Icon(i <= current ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: i <= current ? t.colorScheme.primary : t.colorScheme.outline),
                  if (i < steps.length - 1) Container(width: 2, height: 26, color: i < current ? t.colorScheme.primary : t.colorScheme.outline),
                ]),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      statusLabel(context, steps[i], pickup: order.isPickup),
                      style: t.textTheme.titleSmall?.copyWith(color: i <= current ? null : t.colorScheme.onSurfaceVariant),
                    ),
                    if (order.events.where((e) => e.status == steps[i]).lastOrNull case final e?) ...[
                      Text(formatDateTime(e.createdAt, lang), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                      // The admin's message to the customer for this step
                      if (e.note.isNotEmpty) _StepNote(e.note),
                    ],
                  ]),
                ),
              ),
            ]),
        ]),
      ),
    );
  }
}

class _StepNote extends StatelessWidget {
  const _StepNote(this.note);

  final String note;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 6, right: 12, left: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.colorScheme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.chat_bubble_outline, size: 16, color: t.colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(child: Text(note, style: t.textTheme.bodyMedium)),
      ]),
    );
  }
}
