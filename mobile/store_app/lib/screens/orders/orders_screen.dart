import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/store_api.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<StoreApi>();
    final t = Theme.of(context);
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('orders.title'))),
      body: AsyncView<PageResult<OrderSummary>>(
        load: () => api.orders(),
        builder: (context, page, reload) => page.items.isEmpty
            ? EmptyView(icon: Icons.receipt_long_outlined, title: context.tr('orders.empty'), message: context.tr('orders.empty_hint'))
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: page.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final o = page.items[i];
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: o.id)));
                          reload();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(context.tr('orders.number', {'n': o.number}), style: t.textTheme.titleSmall),
                                const SizedBox(height: 4),
                                Text('${formatDate(o.createdAt, lang)} · ${context.tr('orders.items', {'n': o.itemCount})}',
                                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                                const SizedBox(height: 8),
                                StatusChip(o.status, pickup: o.isPickup),
                              ]),
                            ),
                            Text(money(o.total), style: t.textTheme.titleMedium?.copyWith(fontFamily: 'packages/alas_shared/Manrope')),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
