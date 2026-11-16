import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/admin_api.dart';
import '../widgets/admin_widgets.dart';
import 'orders_screen.dart';

/// Bell icon with the unread count; opens the inbox.
class InboxButton extends StatefulWidget {
  const InboxButton({super.key});

  @override
  State<InboxButton> createState() => _InboxButtonState();
}

class _InboxButtonState extends State<InboxButton> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final r = await context.read<AdminApi>().inbox();
      if (mounted) setState(() => _unread = r.unread);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: context.tr('inbox.title'),
        icon: Badge(
          isLabelVisible: _unread > 0,
          label: Text('$_unread'),
          child: const Icon(Icons.notifications_outlined),
        ),
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InboxScreen()));
          _refresh();
        },
      );
}

/// Alerts the admin app received (new orders, cancellations), so a dismissed push can still be found.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  // Ids that were unread when the screen opened, shown highlighted
  final _unreadIds = <int>{};
  bool _markedSeen = false;

  Future<PageResult<AppNotification>> _load(int page) async {
    final api = context.read<AdminApi>();
    final r = await api.inbox(page: page);
    if (page == 1 && !_markedSeen) {
      _markedSeen = true;
      _unreadIds.addAll(r.page.items.take(r.unread).map((n) => n.id));
      api.markInboxSeen().catchError((_) {});
    }
    return r.page;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('inbox.title'))),
      body: PagedList<AppNotification>(
        load: _load,
        empty: EmptyView(icon: Icons.notifications_none_rounded, title: context.tr('inbox.empty'), message: context.tr('inbox.empty_hint')),
        itemBuilder: (context, n, reload) {
          final orderId = int.tryParse('${n.data['order_id'] ?? ''}');
          final link = n.data['whatsapp_link'] is String ? n.data['whatsapp_link'] as String : null;
          final unread = _unreadIds.contains(n.id);
          return Card(
            color: unread ? t.colorScheme.primaryContainer.withValues(alpha: .5) : null,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: t.colorScheme.primaryContainer,
                child: Icon(
                    link != null
                        ? Icons.key_outlined
                        : n.titleEn.startsWith('Customer cancelled')
                            ? Icons.cancel_outlined
                            : Icons.shopping_cart_outlined,
                    color: t.colorScheme.primary),
              ),
              title: Text(n.title(lang), style: unread ? const TextStyle(fontWeight: FontWeight.w700) : null),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (n.body(lang).isNotEmpty) Text(n.body(lang)),
                const SizedBox(height: 2),
                Text(formatDateTime(n.createdAt, lang), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ]),
              trailing: link != null
                  ? const Icon(Icons.send_outlined, color: Color(0xFF25D366))
                  : orderId == null
                      ? null
                      : const Icon(Icons.chevron_right),
              onTap: link != null
                  ? () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication)
                  : orderId == null
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminOrderScreen(orderId: orderId))),
            ),
          );
        },
      ),
    );
  }
}
