import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/cart.dart';
import '../widgets/common.dart';
import 'checkout_screen.dart';
import 'product/product_detail_screen.dart';
import 'shell.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key, this.standalone = false});

  /// True when pushed from a product page (not the bottom tab).
  final bool standalone;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _coupon = TextEditingController();

  @override
  void initState() {
    super.initState();
    final cart = context.read<Cart>();
    _coupon.text = cart.coupon ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => cart.refreshQuote());
  }

  @override
  void dispose() {
    _coupon.dispose();
    super.dispose();
  }

  Future<void> _checkout() async {
    if (!await requireLogin(context) || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckoutScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final t = Theme.of(context);
    final lang = context.lang;
    final q = cart.quote;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('cart.title')),
        actions: [
          if (!cart.isEmpty)
            IconButton(
              tooltip: context.tr('cart.clear'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                if (await confirmDialog(context, title: context.tr('cart.clear_confirm'), danger: true)) cart.clear();
              },
            ),
        ],
      ),
      body: cart.isEmpty
          ? EmptyView(
              icon: Icons.shopping_bag_outlined,
              title: context.tr('cart.empty'),
              message: context.tr('cart.empty_hint'),
              action: context.tr('cart.browse'),
              onAction: () {
                if (widget.standalone) Navigator.of(context).popUntil((r) => r.isFirst);
                ShellController.of(context)?.select(1);
              },
            )
          : Column(children: [
              if (cart.quoting) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: cart.refreshQuote,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    for (final line in cart.lines) ...[
                      _CartLineTile(line: line),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 8),
                    _couponBox(context, cart),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(children: [
                          SummaryRow(context.tr('cart.subtotal'), money(q?.subtotal ?? cart.localSubtotal)),
                          if ((q?.discount ?? 0) > 0) SummaryRow(context.tr('cart.discount'), '- ${money(q!.discount)}', color: AlasColors.sale),
                          if ((q?.appDiscount ?? 0) > 0)
                            SummaryRow('${context.tr('app_discount')} (${q!.appDiscountPercent.toStringAsFixed(0)}%)', '- ${money(q.appDiscount)}',
                                color: AlasColors.primary),
                          const Divider(height: 18),
                          SummaryRow(context.tr('cart.total'), money(q?.total ?? cart.localSubtotal), bold: true),
                        ]),
                      ),
                    ),
                    if (q?.orderProblem != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          q!.orderProblem == 'below_min_order_total'
                              ? context.tr('cart.min_order_total', {'v': money(q.minOrderTotal)})
                              : L10n.get(lang, 'err.${q.orderProblem}'),
                          style: t.textTheme.bodyMedium?.copyWith(color: AlasColors.destructive),
                        ),
                      ),
                  ]),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: q != null && q.ok && !cart.quoting ? _checkout : null,
                      child: Text('${context.tr('cart.checkout')} · ${money(q?.total ?? cart.localSubtotal)}'),
                    ),
                  ),
                ),
              ),
            ]),
    );
  }

  Widget _couponBox(BuildContext context, Cart cart) {
    final q = cart.quote;
    final applied = q?.couponCode;
    final problem = q?.couponProblem;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _coupon,
            textCapitalization: TextCapitalization.characters,
            enabled: applied == null,
            decoration: InputDecoration(labelText: context.tr('cart.coupon'), prefixIcon: const Icon(Icons.local_offer_outlined)),
          ),
        ),
        const SizedBox(width: 8),
        applied == null
            ? FilledButton.tonal(onPressed: () => cart.setCoupon(_coupon.text), child: Text(context.tr('cart.apply')))
            : TextButton(
                onPressed: () {
                  _coupon.clear();
                  cart.setCoupon(null);
                },
                child: Text(context.tr('cart.remove_coupon')),
              ),
      ]),
      if (applied != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(context.tr('cart.coupon_applied', {'code': applied}), style: const TextStyle(color: AlasColors.primary)),
        )
      else if (problem != null && cart.coupon != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(L10n.get(context.lang, 'err.$problem'), style: const TextStyle(color: AlasColors.destructive)),
        ),
    ]);
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lang = context.lang;
    final cart = context.read<Cart>();
    final problem = line.problem;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(productKey: line.productSlug))),
            child: SizedBox.square(dimension: 78, child: NetImage(line.image, radius: 8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(line.name(lang), style: t.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                InkWell(onTap: () => cart.remove(line.variantId), child: Icon(Icons.close, size: 20, color: t.colorScheme.onSurfaceVariant)),
              ]),
              Text(line.label(lang), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              PriceText(price: line.regularPrice, discountPrice: line.unitPrice < line.regularPrice ? line.unitPrice : null),
              const SizedBox(height: 6),
              Row(children: [
                QuantityStepper(
                  compact: true,
                  value: line.quantity,
                  min: line.minQty,
                  max: line.stock < line.minQty ? line.minQty : line.stock,
                  onChanged: (v) => cart.setQuantity(line.variantId, v),
                ),
                const Spacer(),
                Text(money(line.total), style: t.textTheme.titleSmall?.copyWith(fontFamily: 'packages/alas_shared/Manrope')),
              ]),
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    problem == 'insufficient_stock'
                        ? context.tr('product.only_left', {'n': line.stock})
                        : problem == 'below_min_qty'
                            ? context.tr('product.min_qty', {'n': line.minQty})
                            : L10n.get(lang, 'err.$problem'),
                    style: t.textTheme.bodySmall?.copyWith(color: AlasColors.destructive),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
