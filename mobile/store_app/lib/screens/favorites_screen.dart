import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/store_api.dart';
import '../state/favorites.dart';
import '../state/session.dart';
import '../widgets/common.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.watch<Session>().loggedIn;
    // Rebuild the list when favorites change (ids length is a cheap change signal).
    final key = context.select<Favorites, int>((f) => Object.hashAll(f.ids));
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('fav.title'))),
      body: !loggedIn
          ? EmptyView(
              icon: Icons.favorite_border,
              title: context.tr('fav.login'),
              action: context.tr('auth.login'),
              onAction: () => requireLogin(context),
            )
          : AsyncView<List<ProductSummary>>(
              key: ValueKey(key),
              load: context.read<StoreApi>().favorites,
              builder: (context, items, reload) => items.isEmpty
                  ? EmptyView(icon: Icons.favorite_border, title: context.tr('fav.empty'), message: context.tr('fav.empty_hint'))
                  : RefreshIndicator(onRefresh: reload, child: CustomScrollView(slivers: [ProductGrid(products: items)])),
            ),
    );
  }
}
