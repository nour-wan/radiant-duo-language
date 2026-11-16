import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show openFromNotification;
import '../../services/store_api.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<StoreApi>().markNotificationsSeen().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<StoreApi>();
    final t = Theme.of(context);
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('notif.title'))),
      body: AsyncView<PageResult<AppNotification>>(
        load: () => api.notifications(),
        builder: (context, page, reload) => page.items.isEmpty
            ? EmptyView(icon: Icons.notifications_none_rounded, title: context.tr('notif.empty'), message: context.tr('notif.empty_hint'))
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView.separated(
                  itemCount: page.items.length,
                  separatorBuilder: (_, _) => const Divider(indent: 72),
                  itemBuilder: (_, i) {
                    final n = page.items[i];
                    final icon = switch (n.kind) {
                      'order' => Icons.receipt_long_outlined,
                      'account' => Icons.account_balance_wallet_outlined,
                      'offer' => Icons.local_offer_outlined,
                      _ => Icons.campaign_outlined,
                    };
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: CircleAvatar(backgroundColor: t.colorScheme.primaryContainer, child: Icon(icon, color: t.colorScheme.primary)),
                      title: Text(n.title(lang)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (n.body(lang).isNotEmpty) Text(n.body(lang)),
                        const SizedBox(height: 2),
                        Text(formatDateTime(n.createdAt, lang), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                      ]),
                      onTap: n.data.isEmpty ? null : () => openFromNotification(n.data),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
