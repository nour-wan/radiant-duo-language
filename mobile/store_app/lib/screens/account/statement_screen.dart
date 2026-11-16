import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/store_api.dart';
import '../orders/order_detail_screen.dart';

/// The customer's account with the store: what is owed, payments and delivered orders.
class StatementScreen extends StatelessWidget {
  const StatementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<StoreApi>();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('ledger.title'))),
      body: AsyncView<Statement>(
        load: api.statement,
        builder: (context, data, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              BalanceCard(summary: data.summary),
              const SizedBox(height: 12),
              if (data.entries.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(context.tr('ledger.empty'), textAlign: TextAlign.center),
                )
              else
                Card(
                  child: Column(children: [
                    for (final e in data.entries.items)
                      LedgerEntryTile(
                        entry: e,
                        onOpenOrder: (id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: id))),
                      ),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
