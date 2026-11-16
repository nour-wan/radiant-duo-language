import 'dart:async';

import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/admin_api.dart';
import '../widgets/admin_widgets.dart';

/// Send a push + inbox notification to all customers or a targeted group
/// (interested categories, business type, delivery zone).
class NotifyScreen extends StatefulWidget {
  const NotifyScreen({super.key});

  @override
  State<NotifyScreen> createState() => _NotifyScreenState();
}

class _NotifyScreenState extends State<NotifyScreen> {
  final _form = GlobalKey<FormState>();
  final _titleAr = TextEditingController();
  final _titleEn = TextEditingController();
  final _bodyAr = TextEditingController();
  final _bodyEn = TextEditingController();
  final _interests = <int>{};
  final _types = <String>{};
  final _zones = <int>{};
  bool _targeted = false, _busy = false;
  int? _audience, _openCategory;
  List<Category> _categories = [];
  List<DeliveryZone> _zoneList = [];
  Timer? _countDebounce;
  Key _historyKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    final api = context.read<AdminApi>();
    api.categories().then((c) => mounted ? setState(() => _categories = c) : null).catchError((_) => null);
    api.zones().then((z) => mounted ? setState(() => _zoneList = z) : null).catchError((_) => null);
  }

  Map<String, dynamic> get _target => _targeted
      ? {'target_interests': _interests.toList(), 'target_business_types': _types.toList(), 'target_zones': _zones.toList()}
      : {};

  void _recount() {
    _countDebounce?.cancel();
    if (!_targeted) {
      setState(() => _audience = null);
      return;
    }
    _countDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final n = await context.read<AdminApi>().audienceCount(_target);
        if (mounted) setState(() => _audience = n);
      } catch (_) {}
    });
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    if (!await confirmDialog(context, title: context.tr('notify.confirm'), message: _audience == null ? null : context.tr('notify.count', {'n': _audience})) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AdminApi>().broadcast({
        'title_ar': _titleAr.text.trim(),
        'title_en': _titleEn.text.trim().isEmpty ? _titleAr.text.trim() : _titleEn.text.trim(),
        'body_ar': _bodyAr.text.trim(),
        'body_en': _bodyEn.text.trim().isEmpty ? _bodyAr.text.trim() : _bodyEn.text.trim(),
        'kind': 'offer',
        if (_openCategory != null) 'category_id': _openCategory,
        ..._target,
      });
      if (!mounted) return;
      showSnack(context, context.tr('notify.sent'));
      for (final c in [_titleAr, _titleEn, _bodyAr, _bodyEn]) {
        c.clear();
      }
      setState(() => _historyKey = UniqueKey());
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _chips<T>(String title, Iterable<(T, String)> options, Set<T> selected) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (value, label) in options)
            FilterChip(
              label: Text(label),
              selected: selected.contains(value),
              onSelected: (on) {
                setState(() => on ? selected.add(value) : selected.remove(value));
                _recount();
              },
            ),
        ]),
      ]);

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminApi>();
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('more.notify'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          FormCard(title: context.tr('more.notify'), children: [
            TextFormField(controller: _titleAr, decoration: InputDecoration(labelText: context.tr('notify.title_ar')), validator: (v) => requiredField(context, v)),
            TextFormField(controller: _bodyAr, maxLines: 3, decoration: InputDecoration(labelText: context.tr('notify.body_ar'))),
            TextFormField(controller: _titleEn, decoration: InputDecoration(labelText: context.tr('notify.title_en'))),
            TextFormField(controller: _bodyEn, maxLines: 3, decoration: InputDecoration(labelText: context.tr('notify.body_en'))),
            DropdownButtonFormField<int?>(
              initialValue: _openCategory,
              decoration: InputDecoration(labelText: context.tr('notify.open')),
              items: [
                DropdownMenuItem(value: null, child: Text(context.tr('banner.link_none'))),
                for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.name(lang))),
              ],
              onChanged: (v) => _openCategory = v,
            ),
          ]),
          FormCard(title: context.tr('notify.audience'), children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(context.tr('notify.all'))),
                ButtonSegment(value: true, label: Text(context.tr('notify.by_interest'))),
              ],
              selected: {_targeted},
              onSelectionChanged: (s) {
                setState(() => _targeted = s.first);
                _recount();
              },
            ),
            if (_targeted) ...[
              _chips(context.tr('notify.by_interest'), _categories.map((c) => (c.id, c.name(lang))), _interests),
              _chips(context.tr('notify.by_type'), businessTypes.map((b) => (b, context.tr('biz.$b'))), _types),
              _chips(context.tr('notify.by_zone'), _zoneList.map((z) => (z.id, z.name(lang))), _zones),
              if (_audience != null)
                Text(context.tr('notify.count', {'n': _audience}), style: const TextStyle(fontWeight: FontWeight.w700, color: AlasColors.primary)),
            ],
          ]),
          FilledButton.icon(onPressed: _busy ? null : _send, icon: const Icon(Icons.send), label: Text(context.tr('notify.send'))),
          const SizedBox(height: 20),
          Text(context.tr('notify.history'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          AsyncView<PageResult<AppNotification>>(
            key: _historyKey,
            load: () => api.campaigns(),
            builder: (context, page, reload) => Column(children: [
              for (final n in page.items)
                Card(
                  child: ListTile(
                    title: Text(n.title(lang)),
                    subtitle: Text([
                      formatDateTime(n.createdAt, lang),
                      if (n.audience.isNotEmpty)
                        context.tr('notify.targeted', {'n': n.audience['customer_count'] ?? '?'})
                      else
                        context.tr('notify.all'),
                      context.tr('notify.delivered', {'n': n.sentCount}),
                    ].join(' · ')),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
