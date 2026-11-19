import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/admin_api.dart';
import '../state/admin_session.dart';

/// Delivery accounts. A distributor adds and manages their own drivers; the owner sees every driver
/// and chooses whether a new one works for the store or for a distributor.
class DriversScreen extends StatefulWidget {
  const DriversScreen({super.key});

  @override
  State<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends State<DriversScreen> {
  List<Map<String, dynamic>>? _drivers;
  List<Map<String, dynamic>> _distributors = [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AdminApi>();
    final owner = context.read<AdminSession>().isOwner;
    try {
      final d = await api.drivers();
      final dist = owner ? (await api.staff()).where((w) => w['is_distributor'] == true && w['is_active'] == true).toList() : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _drivers = d;
          _distributors = dist;
          _error = null;
        });
      }
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

  Future<void> _form({Map<String, dynamic>? who}) async {
    final owner = context.read<AdminSession>().isOwner;
    final name = TextEditingController(text: who?['full_name'] as String? ?? '');
    final phone = TextEditingController(text: who?['phone'] as String? ?? '');
    final password = TextEditingController();
    final isNew = who == null;
    int? worksFor = who?['works_for'] as int?;
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(ctx.tr(isNew ? 'drv.add' : 'app.edit')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(ctx.tr('drv.explain'), style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 8),
              TextField(controller: name, decoration: InputDecoration(labelText: ctx.tr('staff.name'))),
              const SizedBox(height: 8),
              if (isNew)
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
              if (owner && isNew) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  initialValue: worksFor,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: ctx.tr('drv.works_for')),
                  items: [
                    DropdownMenuItem<int?>(value: null, child: Text(ctx.tr('drv.for_store'))),
                    for (final d in _distributors) DropdownMenuItem<int?>(value: d['id'] as int, child: Text('${d['full_name']}')),
                  ],
                  onChanged: (v) => setDialog(() => worksFor = v),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('app.cancel'))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                'full_name': name.text.trim(),
                if (isNew) 'phone': phone.text.trim(),
                if (password.text.isNotEmpty) 'password': password.text,
                if (owner && isNew) 'works_for': worksFor,
              }),
              child: Text(ctx.tr('app.save')),
            ),
          ],
        ),
      ),
    );
    if (data == null || !mounted) return;
    final api = context.read<AdminApi>();
    await _run(() => isNew ? api.addDriver(data) : api.updateDriver(who['id'] as int, data));
  }

  Future<void> _toggle(Map<String, dynamic> who) async {
    final active = who['is_active'] == true;
    if (active &&
        !await confirmDialog(context, title: context.tr('staff.disable'), message: context.tr('staff.disable_confirm', {'n': who['full_name'] ?? ''}))) {
      return;
    }
    if (!mounted) return;
    await _run(() => context.read<AdminApi>().updateDriver(who['id'] as int, {'is_active': !active}));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final owner = context.watch<AdminSession>().isOwner;
    final list = _drivers;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('drv.title'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _form(), icon: const Icon(Icons.person_add_alt), label: Text(context.tr('drv.add'))),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : list == null
              ? const LoadingView()
              : list.isEmpty
                  ? EmptyView(icon: Icons.local_shipping_outlined, title: context.tr('drv.empty'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
                        for (final d in list)
                          Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: d['is_active'] == true ? t.colorScheme.primaryContainer : t.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.local_shipping_outlined),
                              ),
                              title: Text('${d['full_name'] ?? ''}${d['is_active'] == true ? '' : ' (${context.tr('staff.disabled')})'}'),
                              subtitle: Text([
                                if ((d['phone'] as String?)?.isNotEmpty == true) '‎${d['phone']}',
                                if (owner) d['works_for_name'] == null ? context.tr('drv.for_store') : context.tr('dist.via', {'n': d['works_for_name']}),
                                context.tr('drv.active', {'n': d['active_deliveries'] ?? 0}),
                              ].join(' · ')),
                              onTap: () => _form(who: d),
                              trailing: IconButton(
                                tooltip: context.tr(d['is_active'] == true ? 'staff.disable' : 'staff.enable'),
                                icon: Icon(d['is_active'] == true ? Icons.block : Icons.check_circle_outline,
                                    color: d['is_active'] == true ? AlasColors.destructive : AlasColors.primary),
                                onPressed: () => _toggle(d),
                              ),
                            ),
                          ),
                      ]),
                    ),
    );
  }
}
