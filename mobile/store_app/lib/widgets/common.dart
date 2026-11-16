import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/product/product_detail_screen.dart';
import '../state/favorites.dart';
import '../state/session.dart';

/// Opens the login screen if needed, then asks for the business profile if it
/// is incomplete (e.g. after Google sign-in). Returns true when both are done.
Future<bool> requireLogin(BuildContext context) async {
  final session = context.read<Session>();
  if (!session.loggedIn) {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginScreen()));
    if (ok != true || !context.mounted) return false;
  }
  if (session.user?.profileComplete ?? false) return true;
  final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CompleteProfileScreen()));
  return done == true;
}

class FavoriteButton extends StatelessWidget {
  const FavoriteButton({super.key, required this.productId, this.small = false});

  final int productId;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final fav = context.watch<Favorites>().contains(productId);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: .92),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () async {
          if (!await requireLogin(context) || !context.mounted) return;
          try {
            final added = await context.read<Favorites>().toggle(productId);
            if (context.mounted) showSnack(context, context.tr(added ? 'product.fav_added' : 'product.fav_removed'));
          } catch (e) {
            if (context.mounted) showSnack(context, context.trError(e), error: true);
          }
        },
        child: Padding(
          padding: EdgeInsets.all(small ? 6 : 8),
          child: Icon(fav ? Icons.favorite : Icons.favorite_border, size: small ? 18 : 22, color: fav ? AlasColors.sale : scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, this.width});

  final ProductSummary product;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lang = context.lang;
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(productKey: product.slug, preview: product))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Stack(children: [
              NetImage(product.thumbnail, aspectRatio: 1),
              if (product.onSale)
                PositionedDirectional(
                  top: 8,
                  start: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AlasColors.sale, borderRadius: BorderRadius.circular(6)),
                    child: Text(context.tr('product.sale', {'n': product.discountPercent}),
                        style: t.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              PositionedDirectional(top: 6, end: 6, child: FavoriteButton(productId: product.id, small: true)),
              if (!product.inStock)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: .35),
                    alignment: Alignment.center,
                    child: Text(context.tr('product.out_of_stock'),
                        style: t.textTheme.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(product.name(lang), maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall?.copyWith(height: 1.35)),
                const SizedBox(height: 4),
                PriceText(price: product.price, discountPrice: product.discountPrice, prefix: context.tr('product.from')),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Responsive product grid as a sliver.
class ProductGrid extends StatelessWidget {
  const ProductGrid({super.key, required this.products});

  final List<ProductSummary> products;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: .62,
          ),
          delegate: SliverChildBuilderDelegate((_, i) => ProductCard(product: products[i]), childCount: products.length),
        ),
      );
}

class HorizontalProducts extends StatelessWidget {
  const HorizontalProducts({super.key, required this.products});

  final List<ProductSummary> products;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 270,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: products.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => ProductCard(product: products[i], width: 160),
        ),
      );
}

class QuantityStepper extends StatelessWidget {
  const QuantityStepper({super.key, required this.value, required this.onChanged, this.min = 1, this.max = 100000, this.compact = false});

  final int value, min, max;
  final ValueChanged<int> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = compact ? 34.0 : 44.0;
    Widget btn(IconData icon, VoidCallback? onTap) => SizedBox.square(
          dimension: size,
          child: IconButton(
            padding: EdgeInsets.zero,
            onPressed: onTap,
            icon: Icon(icon, size: compact ? 18 : 22),
          ),
        );
    return Container(
      decoration: BoxDecoration(border: Border.all(color: scheme.outline), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove, value > min ? () => onChanged(value - 1) : null),
        InkWell(
          onTap: () async {
            final v = await _askNumber(context, value);
            if (v != null) onChanged(v.clamp(min, max));
          },
          child: SizedBox(
            width: compact ? 40 : 52,
            child: Text('$value', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
        btn(Icons.add, value < max ? () => onChanged(value + 1) : null),
      ]),
    );
  }

  Future<int?> _askNumber(BuildContext context, int current) {
    final c = TextEditingController(text: '$current');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('product.quantity')),
        content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('app.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())), child: Text(ctx.tr('app.confirm'))),
        ],
      ),
    );
  }
}

class SummaryRow extends StatelessWidget {
  const SummaryRow(this.label, this.value, {super.key, this.bold = false, this.color});

  final String label, value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final style = (bold ? t.titleMedium : t.bodyMedium)?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style?.copyWith(fontFamily: 'packages/alas_shared/Manrope', fontWeight: bold ? FontWeight.w700 : null)),
      ]),
    );
  }
}
