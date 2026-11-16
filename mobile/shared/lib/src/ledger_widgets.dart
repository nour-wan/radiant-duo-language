import 'package:flutter/material.dart';

import 'format.dart';
import 'l10n.dart';
import 'models.dart';
import 'theme.dart';

const _numbers = 'packages/alas_shared/Manrope';

/// Big balance card at the top of an account statement (customer and admin wording differ).
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.summary, this.admin = false, this.actions = const []});

  final AccountSummary summary;
  final bool admin;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = summary.balance;
    final suffix = admin ? '_admin' : '';
    final (label, color) = b > 0
        ? (context.tr('ledger.balance_owed$suffix'), AlasColors.destructive)
        : b < 0
            ? (context.tr('ledger.balance_credit$suffix'), t.colorScheme.primary)
            : (context.tr('ledger.settled'), t.colorScheme.primary);
    final limit = summary.creditLimit;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(money(b.abs()), style: t.textTheme.headlineMedium?.copyWith(color: color, fontFamily: _numbers, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (summary.creditEnabled) ...[
            _row(context, context.tr('ledger.credit_limit'), limit == null ? context.tr('ledger.no_limit') : money(limit)),
            if (summary.openOrders > 0) _row(context, context.tr('ledger.open_orders'), money(summary.openOrders)),
            if (summary.available != null) _row(context, context.tr('ledger.available'), money(summary.available)),
          ] else if (admin)
            _row(context, context.tr('ledger.credit_limit'), context.tr('ledger.credit_off')),
          const SizedBox(height: 6),
          Text(context.tr('ledger.note_usd'), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          if (actions.isNotEmpty) ...[const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: actions)],
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: t.bodyMedium)),
        Text(value, style: t.bodyMedium?.copyWith(fontFamily: _numbers)),
      ]),
    );
  }
}

/// One statement line: what happened, signed amount and the balance after it.
class LedgerEntryTile extends StatelessWidget {
  const LedgerEntryTile({super.key, required this.entry, this.onOpenOrder, this.showAuthor = false});

  final LedgerEntry entry;
  final void Function(int orderId)? onOpenOrder;
  final bool showAuthor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lang = context.lang;
    final e = entry;
    final debit = e.amount > 0;
    final icon = switch (e.kind) {
      'order' => Icons.local_shipping_outlined,
      'payment' => Icons.payments_outlined,
      _ => Icons.edit_note,
    };
    final details = [
      formatDateTime(e.createdAt, lang),
      if (e.orderNumber != null) e.orderNumber!,
      if (e.note.isNotEmpty) e.note,
      if (showAuthor && e.createdBy != null) e.createdBy!,
    ];
    return ListTile(
      onTap: e.orderId != null && onOpenOrder != null ? () => onOpenOrder!(e.orderId!) : null,
      leading: CircleAvatar(
        backgroundColor: (debit ? AlasColors.destructive : t.colorScheme.primary).withValues(alpha: .1),
        child: Icon(icon, color: debit ? AlasColors.destructive : t.colorScheme.primary),
      ),
      title: Text(context.tr('ledger.kind.${e.kind}')),
      subtitle: Text(details.join(' · ')),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${debit ? '+' : '−'}${money(e.amount.abs())}',
            style: t.textTheme.titleSmall?.copyWith(color: debit ? AlasColors.destructive : t.colorScheme.primary, fontFamily: _numbers)),
        Text('${context.tr('ledger.balance_after')}: ${money(e.balanceAfter)}',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, fontFamily: _numbers)),
      ]),
    );
  }
}
