import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/store_api.dart';
import 'product/product_list_screen.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<StoreApi>();
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('nav.categories'))),
      body: AsyncView<List<Category>>(
        load: api.categories,
        builder: (context, cats, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: cats.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final c = cats[i];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ProductListScreen(query: ProductQuery(categoryId: c.id), title: c.name(context.lang)))),
                  child: Row(children: [
                    SizedBox(width: 96, height: 96, child: NetImage(c.image)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.name(context.lang), style: t.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(c.description(context.lang),
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                        if (c.productCount != null) ...[
                          const SizedBox(height: 4),
                          Text(context.tr('products.count', {'n': c.productCount}), style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.primary)),
                        ],
                      ]),
                    ),
                    const Icon(Icons.chevron_right),
                    const SizedBox(width: 8),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
