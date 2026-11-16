import 'dart:async';

import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/store_api.dart';
import '../state/session.dart';
import '../widgets/common.dart';
import 'account/notifications_screen.dart';
import 'product/product_detail_screen.dart';
import 'product/product_list_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<StoreApi>();
    final user = context.watch<Session>().user;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: [
          const LeafLogo(size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                user != null && user.fullName.isNotEmpty ? context.tr('home.hello', {'name': user.fullName.split(' ').first}) : context.tr('home.welcome'),
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
              Text(context.tr('brand.full'), style: t.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        actions: [
          if (user != null)
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
            ),
        ],
      ),
      body: AsyncView<HomeData>(
        load: api.home,
        builder: (context, data, reload) => RefreshIndicator(
          onRefresh: reload,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _SearchField()),
            if (data.banners.isNotEmpty) SliverToBoxAdapter(child: _Banners(banners: data.banners)),
            SliverToBoxAdapter(
              child: SectionHeader(
                context.tr('home.categories'),
                action: context.tr('home.see_all'),
                onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProductListScreen())),
              ),
            ),
            SliverToBoxAdapter(child: _CategoryStrip(categories: data.categories)),
            ..._section(context, 'home.offers', data.offers, const ProductQuery(onSale: true)),
            ..._section(context, 'home.featured', data.featured, const ProductQuery(featured: true)),
            ..._section(context, 'home.best', data.bestSellers, const ProductQuery(sort: 'popular')),
            ..._section(context, 'home.newest', data.newest, const ProductQuery()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(context.tr('app.currency_note'),
                    textAlign: TextAlign.center, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _section(BuildContext context, String title, List<ProductSummary> items, ProductQuery query) {
    if (items.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: SectionHeader(
          context.tr(title),
          action: context.tr('home.see_all'),
          onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductListScreen(query: query, title: context.tr(title)))),
        ),
      ),
      SliverToBoxAdapter(child: HorizontalProducts(products: items)),
    ];
  }
}

class _SearchField extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: TextField(
          readOnly: true,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProductListScreen(autofocusSearch: true))),
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: context.tr('home.search_hint')),
        ),
      );
}

class _Banners extends StatefulWidget {
  const _Banners({required this.banners});

  final List<BannerItem> banners;

  @override
  State<_Banners> createState() => _BannersState();
}

class _BannersState extends State<_Banners> {
  final _controller = PageController(viewportFraction: .92);
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    if (widget.banners.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_controller.hasClients) return;
        _controller.animateToPage((_page + 1) % widget.banners.length, duration: const Duration(milliseconds: 450), curve: Curves.easeOut);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _open(BannerItem b) {
    switch (b.linkType) {
      case 'product':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(productKey: b.linkValue)));
      case 'category':
        final id = int.tryParse(b.linkValue);
        if (id != null) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductListScreen(query: ProductQuery(categoryId: id), title: b.title(context.lang))));
        }
      case 'url':
        final uri = Uri.tryParse(b.linkValue);
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lang = context.lang;
    return Column(children: [
      const SizedBox(height: 12),
      AspectRatio(
        aspectRatio: 2.1,
        child: PageView.builder(
          controller: _controller,
          itemCount: widget.banners.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) {
            final b = widget.banners[i];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => _open(b),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(fit: StackFit.expand, children: [
                    NetImage(b.image),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xE6291409), Color(0x00291409)],
                          stops: [0, .8],
                        ),
                      ),
                    ),
                    if (b.title(lang).isNotEmpty)
                      PositionedDirectional(
                        start: 16,
                        end: 16,
                        bottom: 14,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(b.title(lang), style: t.textTheme.titleLarge?.copyWith(color: Colors.white)),
                          if (b.subtitle(lang).isNotEmpty)
                            Text(b.subtitle(lang), style: t.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
                        ]),
                      ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
      if (widget.banners.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < widget.banners.length; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page ? t.colorScheme.primary : t.colorScheme.outline,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
          ]),
        ),
    ]);
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 112,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: categories.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final c = categories[i];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ProductListScreen(query: ProductQuery(categoryId: c.id), title: c.name(context.lang)))),
              child: SizedBox(
                width: 78,
                child: Column(children: [
                  ClipOval(child: SizedBox.square(dimension: 66, child: NetImage(c.image))),
                  const SizedBox(height: 6),
                  Text(c.name(context.lang),
                      maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
                ]),
              ),
            );
          },
        ),
      );
}
