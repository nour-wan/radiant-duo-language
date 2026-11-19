import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/admin_api.dart';
import '../widgets/admin_widgets.dart';
import 'orders_screen.dart';

/// Owner only: each employee signs in with their own phone and password, so every
/// status change and payment shows who did it.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  List<Map<String, dynamic>>? _staff;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await context.read<AdminApi>().staff();
      if (mounted) setState(() => _staff = s);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      showSnack(context, context.tr('app.saved'));
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      final errors = e.extra['errors'];
      showSnack(
        context,
        errors is Map ? errors.values.expand((v) => v is List ? v : [v]).map((m) => L10n.error(context.lang, ApiException('invalid', '$m'))).join('\n') : context.trError(e),
        error: true,
      );
    }
  }

  /// Name, phone and password for a new employee, or name / new password for an existing one.
  Future<Map<String, dynamic>?> _form({Map<String, dynamic>? who}) {
    final name = TextEditingController(text: who?['full_name'] as String? ?? '');
    final phone = TextEditingController(text: who?['phone'] as String? ?? '');
    final password = TextEditingController();
    final code = TextEditingController(text: who?['distributor_code'] as String? ?? '');
    final isNew = who == null;
    var distributor = who?['is_distributor'] == true;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
        title: Text(ctx.tr(isNew ? 'staff.add' : 'app.edit')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Employee: the store's team. Distributor: a partner who sees only their own customers.
            if (isNew) ...[
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(ctx.tr('staff.role_employee')), icon: const Icon(Icons.badge_outlined)),
                  ButtonSegment(value: true, label: Text(ctx.tr('staff.role_distributor')), icon: const Icon(Icons.handshake_outlined)),
                ],
                selected: {distributor},
                onSelectionChanged: (s) => setState(() => distributor = s.first),
              ),
              if (distributor)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(ctx.tr('dist.explain'), style: Theme.of(ctx).textTheme.bodySmall),
                ),
              const SizedBox(height: 8),
            ],
            TextField(controller: name, decoration: InputDecoration(labelText: ctx.tr('staff.name'))),
            const SizedBox(height: 8),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: ctx.tr('staff.phone'), hintText: '09xxxxxxxx'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: password,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: ctx.tr(isNew ? 'staff.password' : 'staff.new_password'),
                helperText: ctx.tr('staff.password_hint'),
                helperMaxLines: 2,
              ),
            ),
            if (distributor) ...[
              const SizedBox(height: 8),
              TextField(
                controller: code,
                textCapitalization: TextCapitalization.characters,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: ctx.tr('dist.code'), helperText: ctx.tr('dist.code_auto'), helperMaxLines: 2),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('app.cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, {
              'full_name': name.text.trim(),
              'phone': phone.text.trim(),
              if (password.text.isNotEmpty) 'password': password.text,
              if (isNew) 'is_distributor': distributor,
              if (distributor && code.text.trim().isNotEmpty) 'distributor_code': code.text.trim().toUpperCase(),
            }),
            child: Text(ctx.tr('app.save')),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _add() async {
    final data = await _form();
    if (data == null || !mounted) return;
    await _run(() => context.read<AdminApi>().addStaff(data));
  }

  Future<void> _edit(Map<String, dynamic> who) async {
    final data = await _form(who: who);
    if (data == null || !mounted) return;
    await _run(() => context.read<AdminApi>().updateStaff(who['id'] as int, data));
  }

  Future<void> _toggle(Map<String, dynamic> who) async {
    final active = who['is_active'] == true;
    if (active &&
        !await confirmDialog(context,
            title: context.tr('staff.disable'), message: context.tr('staff.disable_confirm', {'n': who['full_name'] ?? ''}))) {
      return;
    }
    if (!mounted) return;
    await _run(() => context.read<AdminApi>().updateStaff(who['id'] as int, {'is_active': !active}));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lang = context.lang;
    final staff = _staff;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('staff.title'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.person_add_alt), label: Text(context.tr('staff.add'))),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : staff == null
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
                    for (final w in staff)
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: w['is_active'] == true ? t.colorScheme.primaryContainer : t.colorScheme.surfaceContainerHighest,
                            child: Icon(w['is_owner'] == true
                                ? Icons.workspace_premium_outlined
                                : (w['is_distributor'] == true
                                    ? Icons.handshake_outlined
                                    : (w['is_driver'] == true ? Icons.local_shipping_outlined : Icons.badge_outlined))),
                          ),
                          title: Text(
                            [
                              (w['full_name'] as String?)?.isNotEmpty == true ? w['full_name'] : (w['email'] ?? w['phone'] ?? ''),
                              if (w['is_owner'] == true) '(${context.tr('staff.owner')})',
                              if (w['is_active'] != true) '(${context.tr('staff.disabled')})',
                            ].join(' '),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: w['is_active'] == true ? null : t.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          subtitle: Text([
                            if (w['is_distributor'] == true)
                              context.tr('dist.summary', {
                                'c': w['distributor_code'] ?? '',
                                'n': w['customer_count'] ?? 0,
                                's': money(toMoney(w['month_sales'])),
                              }),
                            if ((w['phone'] as String?)?.isNotEmpty == true) '‎${w['phone']}',
                            w['last_login'] == null
                                ? context.tr('staff.never')
                                : context.tr('staff.last_login', {'d': formatDateTime(toDate(w['last_login']), lang)}),
                          ].join(' · ')),
                          onTap: () => _edit(w),
                          trailing: w['is_owner'] == true
                              ? null
                              : IconButton(
                                  tooltip: context.tr(w['is_active'] == true ? 'staff.disable' : 'staff.enable'),
                                  icon: Icon(w['is_active'] == true ? Icons.block : Icons.check_circle_outline,
                                      color: w['is_active'] == true ? AlasColors.destructive : AlasColors.primary),
                                  onPressed: () => _toggle(w),
                                ),
                        ),
                      ),
                    if (staff.length <= 1)
                      Padding(padding: const EdgeInsets.all(24), child: Text(context.tr('staff.empty'), textAlign: TextAlign.center)),
                  ]),
                ),
    );
  }
}

/// Owner only: how much cash each staff member recorded as received in a period.
class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  String _range = 'today';
  late DateTimeRange _dates = _today();
  Map<String, dynamic>? _data;
  Object? _error;

  static DateTimeRange _today() {
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day);
    return DateTimeRange(start: d, end: d);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final d = await context.read<AdminApi>().collections(_dates.start, _dates.end);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pick(String range) async {
    final today = _today().start;
    DateTimeRange? r;
    switch (range) {
      case 'today':
        r = _today();
      case 'week':
        r = DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
      case 'month':
        r = DateTimeRange(start: DateTime(today.year, today.month), end: today);
      default:
        r = await showDateRangePicker(context: context, firstDate: DateTime(2025), lastDate: today, initialDateRange: _dates);
    }
    if (r == null) return;
    setState(() {
      _range = range;
      _dates = r!;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lang = context.lang;
    final d = _data;
    final staff = (d?['staff'] as List? ?? []).cast<Map>();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('collect.title'))),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            for (final r in ['today', 'week', 'month', 'custom'])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(label: Text(context.tr('collect.$r')), selected: _range == r, onSelected: (_) => _pick(r)),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('${formatDate(_dates.start, lang)} — ${formatDate(_dates.end, lang)}', style: t.textTheme.bodySmall),
          ),
        ),
        Expanded(
          child: _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : d == null
                  ? const LoadingView()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.all(12), children: [
                        Card(
                          color: t.colorScheme.primaryContainer,
                          child: ListTile(
                            title: Text(context.tr('collect.total')),
                            trailing: Text(money(toMoney(d['total'])),
                                style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontFamily: 'packages/alas_shared/Manrope')),
                          ),
                        ),
                        if (staff.isEmpty)
                          Padding(padding: const EdgeInsets.all(32), child: Text(context.tr('collect.empty'), textAlign: TextAlign.center)),
                        for (final s in staff)
                          Card(
                            child: ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
                              title: Text(s['name'] as String? ?? context.tr('collect.old_account')),
                              subtitle: Text(context.tr('collect.count', {'n': s['count']})),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(money(toMoney(s['total'])),
                                    style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontFamily: 'packages/alas_shared/Manrope')),
                                const Icon(Icons.chevron_right),
                              ]),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => _CollectionDetailScreen(
                                  staffId: s['id'] as int? ?? 0,
                                  name: s['name'] as String? ?? context.tr('collect.old_account'),
                                  dates: _dates,
                                ),
                              )),
                            ),
                          ),
                      ]),
                    ),
        ),
      ]),
    );
  }
}

class _CollectionDetailScreen extends StatelessWidget {
  const _CollectionDetailScreen({required this.staffId, required this.name, required this.dates});

  final int staffId;
  final String name;
  final DateTimeRange dates;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: AsyncView<Map<String, dynamic>>(
        load: () => context.read<AdminApi>().collections(dates.start, dates.end, staffId: staffId),
        builder: (context, d, reload) {
          final entries = (d['entries'] as List? ?? []).cast<Map>();
          final total = entries.fold<double>(0, (sum, e) => sum + toMoney(e['amount']));
          return ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              color: t.colorScheme.primaryContainer,
              child: ListTile(
                title: Text('${formatDate(dates.start, lang)} — ${formatDate(dates.end, lang)}'),
                subtitle: Text(context.tr('collect.count', {'n': entries.length})),
                trailing: Text(money(total), style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontFamily: 'packages/alas_shared/Manrope')),
              ),
            ),
            for (final e in entries)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.payments_outlined, color: AlasColors.primary),
                  title: Text(e['customer'] as String? ?? '—'),
                  subtitle: Text([
                    formatDateTime(toDate(e['created_at']), lang),
                    if (e['order_number'] != null) e['order_number'],
                    if ((e['note'] as String?)?.isNotEmpty == true) e['note'],
                  ].join(' · ')),
                  trailing: Text(money(toMoney(e['amount'])), style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'packages/alas_shared/Manrope')),
                  onTap: e['order_id'] == null
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminOrderScreen(orderId: e['order_id'] as int))),
                ),
              ),
          ]);
        },
      ),
    );
  }
}


/// Owner only: everything done in the admin app, newest first, by everyone or one person.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  List<Map<String, dynamic>> _staff = [];
  int? _staffId;

  @override
  void initState() {
    super.initState();
    context.read<AdminApi>().staff().then((s) => mounted ? setState(() => _staff = s) : null).catchError((_) => null);
  }

  Future<void> _download() async {
    try {
      final bytes = await context.read<AdminApi>().auditCsv(staffId: _staffId);
      if (mounted) await shareCsv(context, bytes, 'alas-activity-log-${isoDate(DateTime.now())}.csv');
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    }
  }

  static String _details(Map d) => d.entries
      .where((e) => e.value != null && '${e.value}'.isNotEmpty)
      .map((e) => '${e.key}: ${e.value is Map || e.value is List ? '…' : e.value}')
      .join(' · ');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('audit.title')),
        actions: [IconButton(tooltip: context.tr('audit.download'), onPressed: _download, icon: const Icon(Icons.download))],
      ),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(label: Text(context.tr('audit.all')), selected: _staffId == null, onSelected: (_) => setState(() => _staffId = null)),
            ),
            for (final s in _staff)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text((s['full_name'] as String?)?.isNotEmpty == true ? s['full_name'] as String : '${s['email'] ?? s['phone']}'),
                  selected: _staffId == s['id'],
                  onSelected: (_) => setState(() => _staffId = s['id'] as int),
                ),
              ),
          ]),
        ),
        Expanded(
          child: PagedList<Map<String, dynamic>>(
            key: ValueKey(_staffId),
            load: (page) => context.read<AdminApi>().auditLog(page: page, staffId: _staffId),
            empty: EmptyView(icon: Icons.history, title: context.tr('audit.empty')),
            itemBuilder: (context, e, reload) {
              final details = e['details'] is Map ? _details(e['details'] as Map) : '';
              final failed = (e['action_en'] as String? ?? '').startsWith('Failed');
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: failed ? t.colorScheme.errorContainer : t.colorScheme.primaryContainer,
                    child: Icon(failed ? Icons.warning_amber : Icons.person_outline, size: 20),
                  ),
                  title: Text('${(e['actor_name'] as String?)?.isNotEmpty == true ? e['actor_name'] : context.tr('audit.unknown')} — '
                      '${lang == 'ar' ? e['action_ar'] : e['action_en']}'),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if ((e['target'] as String?)?.isNotEmpty == true) Text(e['target'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (details.isNotEmpty) Text(details, style: t.textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
                    Text(formatDateTime(toDate(e['created_at']), lang),
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
