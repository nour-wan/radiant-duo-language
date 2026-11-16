import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/store_api.dart';
import '../../state/cart.dart';
import '../../widgets/common.dart';
import '../cart_screen.dart';

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.productKey, this.preview});

  final String productKey;
  final ProductSummary? preview;

  @override
  Widget build(BuildContext context) {
    final api = context.read<StoreApi>();
    return Scaffold(
      appBar: AppBar(title: Text(preview?.name(context.lang) ?? '', overflow: TextOverflow.ellipsis)),
      body: AsyncView<ProductDetail>(
        load: () => api.product(productKey),
        builder: (context, p, reload) => _ProductBody(product: p),
      ),
    );
  }
}

class _ProductBody extends StatefulWidget {
  const _ProductBody({required this.product});

  final ProductDetail product;

  @override
  State<_ProductBody> createState() => _ProductBodyState();
}

class _ProductBodyState extends State<_ProductBody> {
  late Variant? _variant = widget.product.variants.where((v) => v.inStock).firstOrNull ?? widget.product.variants.firstOrNull;
  late int _qty = _variant?.minOrderQty ?? 1;
  int _image = 0;

  void _selectVariant(Variant v) => setState(() {
        _variant = v;
        _qty = v.minOrderQty;
      });

  void _add() {
    final v = _variant;
    if (v == null || !v.inStock) return;
    context.read<Cart>().add(widget.product, v, _qty);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr('product.added')),
        // A SnackBar with an action stays until tapped by default; it covers the add button.
        duration: const Duration(seconds: 2),
        persist: false,
        action: SnackBarAction(
          label: context.tr('product.view_cart'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartScreen(standalone: true))),
        ),
      ));
  }

  Future<void> _whatsapp() async {
    final settings = await context.read<StoreApi>().settings().catchError((_) => StoreInfo.fromJson({'whatsapp': '+963965747889'}));
    final number = settings.whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
    if (!mounted) return;
    final text = Uri.encodeComponent('${widget.product.name(context.lang)} — ${_variant?.label(context.lang) ?? ''}');
    await launchUrl(Uri.parse('https://wa.me/$number?text=$text'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final t = Theme.of(context);
    final lang = context.lang;
    final v = _variant;
    final images = p.images.isEmpty ? [null] : p.images.map((e) => e.url).toList();
    return Column(children: [
      Expanded(
        child: ListView(padding: EdgeInsets.zero, children: [
          Stack(children: [
            AspectRatio(
              aspectRatio: 1.1,
              child: PageView.builder(
                itemCount: images.length,
                onPageChanged: (i) => setState(() => _image = i),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: images[i] == null ? null : () => _openGallery(context, images.cast<String>(), i),
                  child: NetImage(images[i]),
                ),
              ),
            ),
            PositionedDirectional(top: 12, end: 12, child: FavoriteButton(productId: p.id)),
            if (images.length > 1)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < images.length; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: i == _image ? Colors.white : Colors.white54),
                    ),
                ]),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (p.category != null)
                Text(p.category!.name(lang), style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.primary)),
              const SizedBox(height: 4),
              Text(p.name(lang), style: t.textTheme.headlineSmall),
              const SizedBox(height: 8),
              if (v != null) PriceText(price: v.price, discountPrice: v.discountPrice, large: true),
              const SizedBox(height: 6),
              if (v != null) _StockLabel(variant: v),
              const SizedBox(height: 20),
              Text(context.tr('product.package'), style: t.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final option in p.variants)
                  ChoiceChip(
                    label: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(option.label(lang)),
                      Text(money(option.effectivePrice), style: t.textTheme.labelSmall?.copyWith(fontFamily: 'packages/alas_shared/Manrope')),
                    ]),
                    selected: option.id == v?.id,
                    onSelected: (_) => _selectVariant(option),
                  ),
              ]),
              if (v != null && v.inStock) ...[
                const SizedBox(height: 20),
                Row(children: [
                  Text(context.tr('product.quantity'), style: t.textTheme.titleSmall),
                  const Spacer(),
                  QuantityStepper(value: _qty, min: v.minOrderQty, max: v.stock, onChanged: (q) => setState(() => _qty = q)),
                ]),
                if (v.minOrderQty > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(context.tr('product.min_qty', {'n': v.minOrderQty}),
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ),
              ],
              const SizedBox(height: 24),
              Text(context.tr('product.description'), style: t.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(p.description(lang), style: t.textTheme.bodyMedium),
              if (p.specs.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(context.tr('product.specs'), style: t.textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(children: [
                    for (var i = 0; i < p.specs.length; i++) ...[
                      if (i > 0) const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(width: 120, child: Text(p.specs[i].label(lang), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant))),
                          Expanded(child: Text(p.specs[i].value(lang), style: t.textTheme.bodyMedium)),
                        ]),
                      ),
                    ],
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: _whatsapp, icon: const Icon(Icons.chat_outlined), label: Text(context.tr('product.share_whatsapp'))),
              const SizedBox(height: 24),
            ]),
          ),
        ]),
      ),
      SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(color: t.colorScheme.surface, border: Border(top: BorderSide(color: t.colorScheme.outline))),
          child: Row(children: [
            if (v != null && v.inStock)
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(context.tr('product.total'), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  Text(money(v.effectivePrice * _qty), style: t.textTheme.titleLarge?.copyWith(fontFamily: 'packages/alas_shared/Manrope', color: t.colorScheme.primary)),
                ]),
              ),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: v != null && v.inStock ? _add : null,
                icon: const Icon(Icons.add_shopping_cart),
                label: Text(v != null && v.inStock ? context.tr('product.add_to_cart') : context.tr('product.out_of_stock')),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  void _openGallery(BuildContext context, List<String> urls, int start) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: PageView.builder(
          controller: PageController(initialPage: start),
          itemCount: urls.length,
          itemBuilder: (_, i) => InteractiveViewer(child: Center(child: NetImage(urls[i], fit: BoxFit.contain))),
        ),
      ),
    ));
  }
}

class _StockLabel extends StatelessWidget {
  const _StockLabel({required this.variant});

  final Variant variant;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (!variant.inStock) {
      return Text(context.tr('product.out_of_stock'), style: t.labelLarge?.copyWith(color: AlasColors.destructive));
    }
    if (variant.stock <= 10) {
      return Text(context.tr('product.only_left', {'n': variant.stock}), style: t.labelLarge?.copyWith(color: AlasColors.warning));
    }
    return Row(children: [
      const Icon(Icons.check_circle, size: 16, color: AlasColors.primary),
      const SizedBox(width: 4),
      Text(context.tr('product.in_stock'), style: t.labelLarge?.copyWith(color: AlasColors.primary)),
    ]);
  }
}
