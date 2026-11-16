import 'dart:async';

import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/store_api.dart';
import '../../widgets/common.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key, this.query = const ProductQuery(), this.title, this.autofocusSearch = false});

  final ProductQuery query;
  final String? title;
  final bool autofocusSearch;

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  late ProductQuery _query = widget.query;
  late final _search = TextEditingController(text: widget.query.q);
  final _scroll = ScrollController();
  final List<ProductSummary> _items = [];
  List<Category> _categories = [];
  int _page = 1, _count = 0;
  bool _hasMore = true, _loading = false;
  Object? _error;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    context.read<StoreApi>().categories().then((c) => mounted ? setState(() => _categories = c) : null).catchError((_) => null);
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    _items.clear();
    _page = 1;
    _hasMore = true;
    _error = null;
    await _loadMore(force: true);
  }

  Future<void> _loadMore({bool force = false}) async {
    if ((_loading && !force) || !_hasMore) return;
    final seq = ++_seq;
    setState(() => _loading = true);
    try {
      final page = await context.read<StoreApi>().products(_query, page: _page);
      if (seq != _seq || !mounted) return;
      setState(() {
        _items.addAll(page.items);
        _count = page.count;
        _hasMore = page.hasMore;
        _page++;
      });
    } catch (e) {
      if (seq == _seq && mounted) setState(() => _error = e);
    } finally {
      if (seq == _seq && mounted) setState(() => _loading = false);
    }
  }

  void _setQuery(ProductQuery q) {
    setState(() => _query = q);
    _reload();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _setQuery(_query.copyWith(q: v)));
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<ProductQuery>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _FilterSheet(query: _query, categories: _categories),
    );
    if (result != null) _setQuery(result);
  }

  Future<void> _openSort() async {
    final sort = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final s in ['newest', 'popular', 'price_asc', 'price_desc', 'name'])
            ListTile(
              title: Text(ctx.tr('sort.$s')),
              trailing: _query.sort == s ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary) : null,
              onTap: () => Navigator.pop(ctx, s),
            ),
        ]),
      ),
    );
    if (sort != null) _setQuery(_query.copyWith(sort: sort));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final catName = _categories.where((c) => c.id == _query.categoryId).firstOrNull?.name(context.lang);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? catName ?? context.tr('products.title'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            autofocus: widget.autofocusSearch,
            textInputAction: TextInputAction.search,
            onChanged: _onSearch,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.tr('home.search_hint'),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        _setQuery(_query.copyWith(q: ''));
                      },
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: Text(_loading && _items.isEmpty ? '' : context.tr('products.count', {'n': _count}),
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ),
            TextButton.icon(onPressed: _openSort, icon: const Icon(Icons.swap_vert, size: 20), label: Text(context.tr('sort.${_query.sort}'))),
            Badge(
              isLabelVisible: _query.hasFilters,
              smallSize: 8,
              child: TextButton.icon(onPressed: _openFilters, icon: const Icon(Icons.tune, size: 20), label: Text(context.tr('filter.title'))),
            ),
          ]),
        ),
        Expanded(child: _body(context)),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    if (_items.isEmpty && _error != null) return ErrorView(error: _error!, onRetry: _reload);
    if (_items.isEmpty && _loading) return const LoadingView();
    if (_items.isEmpty) {
      return EmptyView(
        icon: Icons.search_off_rounded,
        title: context.tr('products.empty'),
        message: context.tr('products.empty_hint'),
        action: _query.hasFilters || _query.q.isNotEmpty ? context.tr('products.clear_filters') : null,
        onAction: () {
          _search.clear();
          _setQuery(const ProductQuery());
        },
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(controller: _scroll, slivers: [
        ProductGrid(products: _items),
        if (_hasMore) const SliverToBoxAdapter(child: LoadingView()),
      ]),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.query, required this.categories});

  final ProductQuery query;
  final List<Category> categories;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late int? _category = widget.query.categoryId;
  late bool _onSale = widget.query.onSale;
  late final _min = TextEditingController(text: widget.query.minPrice?.toStringAsFixed(0) ?? '');
  late final _max = TextEditingController(text: widget.query.maxPrice?.toStringAsFixed(0) ?? '');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('filter.title'), style: t.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text(context.tr('filter.price'), style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _min, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('filter.min'), prefixText: '\$ '))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _max, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('filter.max'), prefixText: '\$ '))),
            ]),
            const SizedBox(height: 16),
            Text(context.tr('filter.category'), style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(label: Text(context.tr('app.all')), selected: _category == null, onSelected: (_) => setState(() => _category = null)),
              for (final c in widget.categories)
                ChoiceChip(label: Text(c.name(context.lang)), selected: _category == c.id, onSelected: (_) => setState(() => _category = c.id)),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('filter.on_sale')),
              value: _onSale,
              onChanged: (v) => setState(() => _onSale = v),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, ProductQuery(q: widget.query.q, sort: widget.query.sort)),
                  child: Text(context.tr('filter.reset')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    widget.query.copyWith(
                      categoryId: () => _category,
                      minPrice: () => double.tryParse(_min.text.trim()),
                      maxPrice: () => double.tryParse(_max.text.trim()),
                      onSale: _onSale,
                    ),
                  ),
                  child: Text(context.tr('filter.apply')),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
