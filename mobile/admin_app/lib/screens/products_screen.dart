import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/admin_api.dart';
import '../state/admin_session.dart';
import '../widgets/admin_widgets.dart';
import 'product_form_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _q = '';
  int? _category;
  bool _lowStock = false;
  List<Category> _categories = [];
  final _listKey = GlobalKey<PagedListState<AdminProduct>>();

  @override
  void initState() {
    super.initState();
    context.read<AdminApi>().categories().then((c) => mounted ? setState(() => _categories = c) : null).catchError((_) => null);
  }

  Future<void> _open([int? id]) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductFormScreen(productId: id)));
    _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminApi>();
    final t = Theme.of(context);
    final lang = context.lang;
    // Distributors see products, prices and stock but can't change them
    final readOnly = context.watch<AdminSession>().isDistributor;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('nav.products'))),
      floatingActionButton: readOnly
          ? null
          : FloatingActionButton.extended(onPressed: () => _open(), icon: const Icon(Icons.add), label: Text(context.tr('products.add'))),
      body: PagedList<AdminProduct>(
        key: ValueKey('$_q|$_category|$_lowStock'),
        load: (page) => api.products(page: page, q: _q, category: _category, lowStock: _lowStock),
        header: Column(children: [
          SearchBox(hint: context.tr('products.search'), onChanged: (v) => setState(() => _q = v.trim())),
          SizedBox(
            height: 48,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
              FilterChip(
                avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                label: Text(context.tr('products.low_only')),
                selected: _lowStock,
                onSelected: (v) => setState(() => _lowStock = v),
              ),
              const SizedBox(width: 6),
              ChoiceChip(label: Text(context.tr('app.all')), selected: _category == null, onSelected: (_) => setState(() => _category = null)),
              for (final c in _categories) ...[
                const SizedBox(width: 6),
                ChoiceChip(label: Text(c.name(lang)), selected: _category == c.id, onSelected: (_) => setState(() => _category = c.id)),
              ],
            ]),
          ),
        ]),
        empty: EmptyView(icon: Icons.inventory_2_outlined, title: context.tr('products.empty')),
        itemBuilder: (context, p, reload) {
          final cheapest = p.variants.isEmpty ? null : (p.variants.toList()..sort((a, b) => a.effectivePrice.compareTo(b.effectivePrice))).first;
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
              leading: SizedBox.square(dimension: 54, child: NetImage(p.thumbnail, radius: 8)),
              title: Text(p.name(lang), maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.categoryName(lang), style: t.textTheme.bodySmall),
                Wrap(spacing: 6, children: [
                  Text(context.tr('products.stock', {'n': p.totalStock}),
                      style: TextStyle(color: p.totalStock == 0 ? AlasColors.destructive : null, fontWeight: FontWeight.w700, fontSize: 12)),
                  if (!p.isActive) _Badge(context.tr('products.hidden'), AlasColors.destructive),
                  if (p.isFeatured) _Badge(context.tr('products.featured'), AlasColors.warning),
                ]),
              ]),
              trailing: cheapest == null
                  ? null
                  : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      if (!readOnly)
                        Text(usd(cheapest.effectivePrice), style: const TextStyle(fontFamily: 'packages/alas_shared/Manrope', fontWeight: FontWeight.w700)),
                      Text(money(cheapest.onSale ? cheapest.discountPriceSyp : cheapest.priceSyp), style: t.textTheme.bodySmall),
                    ]),
              onTap: readOnly ? null : () => _open(p.id),
            ),
          );
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}
