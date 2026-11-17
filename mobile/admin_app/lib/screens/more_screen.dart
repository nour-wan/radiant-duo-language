import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'statement_screen.dart';

import '../services/admin_api.dart';
import '../state/admin_session.dart';
import '../widgets/admin_widgets.dart';
import 'manage_screens.dart';
import 'notify_screen.dart';
import 'reports_screen.dart';
import 'staff_screens.dart';
import 'exchange_rate_screen.dart';
import 'whatsapp_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final session = context.watch<AdminSession>();
    final owner = session.isOwner;
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    Widget tile(IconData i, String key, Widget page) =>
        ListTile(leading: Icon(i), title: Text(context.tr(key)), trailing: const Icon(Icons.chevron_right), onTap: () => open(page));
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('nav.more'))),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(child: Icon(owner ? Icons.workspace_premium_outlined : Icons.badge_outlined)),
            title: Text(session.user?.displayName ?? ''),
            subtitle: Text(context.tr(owner ? 'staff.role_owner' : 'staff.role_employee')),
          ),
        ),
        const SizedBox(height: 12),
        if (owner) ...[
          Card(
            child: Column(children: [
              tile(Icons.groups_outlined, 'staff.title', const StaffScreen()),
              tile(Icons.price_check, 'collect.title', const CollectionsScreen()),
              tile(Icons.history, 'audit.title', const AuditLogScreen()),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          child: Column(children: [
            tile(Icons.category_outlined, 'more.categories', const CategoriesScreen()),
            tile(Icons.local_offer_outlined, 'more.coupons', const CouponsScreen()),
            tile(Icons.view_carousel_outlined, 'more.banners', const BannersScreen()),
            tile(Icons.local_shipping_outlined, 'more.zones', const ZonesScreen()),
            tile(Icons.campaign_outlined, 'more.notify', const NotifyScreen()),
            tile(Icons.bar_chart, 'more.reports', const ReportsScreen()),
            tile(Icons.account_balance_wallet_outlined, 'more.receivables', const ReceivablesScreen()),
          ]),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            tile(Icons.currency_exchange, 'rate.title', const ExchangeRateScreen()),
            if (owner) tile(Icons.storefront_outlined, 'more.settings', const StoreSettingsScreen()),
            tile(Icons.gavel_outlined, 'more.legal', const LegalPagesScreen()),
          ]),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(context.tr('app.language')),
              trailing: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 'ar', label: Text('ع')), ButtonSegment(value: 'en', label: Text('EN'))],
                selected: {settings.lang},
                onSelectionChanged: (s) => settings.setLang(s.first),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: Text(context.tr('app.appearance')),
              trailing: DropdownButton<ThemeMode>(
                value: settings.themeMode,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(value: ThemeMode.system, child: Text(context.tr('app.theme_system'))),
                  DropdownMenuItem(value: ThemeMode.light, child: Text(context.tr('app.theme_light'))),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text(context.tr('app.theme_dark'))),
                ],
                onChanged: (m) => m == null ? null : settings.setThemeMode(m),
              ),
            ),
            ListTile(leading: const Icon(Icons.lock_reset), title: Text(context.tr('auth.change_password')), onTap: () => _changePassword(context)),
            ListTile(
              leading: const Icon(Icons.logout, color: AlasColors.destructive),
              title: Text(context.tr('app.logout'), style: const TextStyle(color: AlasColors.destructive)),
              onTap: () async {
                if (await confirmDialog(context, title: context.tr('app.logout')) && context.mounted) {
                  await context.read<AdminSession>().logout(deviceToken: context.read<PushService>().token);
                }
              },
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final current = TextEditingController(), next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('auth.change_password')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: current, obscureText: true, decoration: InputDecoration(labelText: ctx.tr('auth.current_password'))),
          const SizedBox(height: 12),
          TextField(controller: next, obscureText: true, decoration: InputDecoration(labelText: ctx.tr('auth.new_password'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('app.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('app.save'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<AdminSession>().changePassword(current.text, next.text);
      if (context.mounted) showSnack(context, context.tr('app.saved'));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      final errors = e.extra['errors'];
      showSnack(context, errors is Map && errors['new_password'] != null ? (errors['new_password'] as List).join('\n') : context.trError(e), error: true);
    }
  }
}

class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  static const _text = [
    'name_ar', 'name_en', 'about_ar', 'about_en', 'phone', 'mobile', 'whatsapp', 'email', 'website', 'address_ar', 'address_en',
    'working_hours_ar', 'working_hours_en', 'facebook', 'instagram', 'telegram', 'min_order_total', 'low_stock_threshold',
    'app_discount_percent', 'default_credit_limit', 'pickup_address_ar', 'pickup_address_en', 'delivery_currency_ar', 'delivery_currency_en',
  ];
  static const _labels = {
    'working_hours_ar': 'hours_ar', 'working_hours_en': 'hours_en', 'min_order_total': 'min_total', 'low_stock_threshold': 'low_stock',
    'pickup_address_ar': 'pickup_ar', 'pickup_address_en': 'pickup_en', 'delivery_currency_ar': 'currency_ar', 'delivery_currency_en': 'currency_en',
    'default_credit_limit': 'credit_limit',
  };
  final _c = {for (final k in _text) k: TextEditingController()};
  final _flags = <String, bool>{};
  bool _loading = true, _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await context.read<AdminApi>().settings();
      for (final k in _text) {
        _c[k]!.text = '${s.raw[k] ?? ''}';
      }
      for (final k in ['orders_enabled', 'app_discount_enabled', 'pickup_enabled', 'delivery_enabled']) {
        _flags[k] = s.raw[k] as bool? ?? true;
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final data = <String, dynamic>{for (final k in _text) k: _c[k]!.text.trim(), ..._flags};
      if (data['default_credit_limit'] == '') data['default_credit_limit'] = null; // no limit
      await context.read<AdminApi>().saveSettings(data);
      if (mounted) showSnack(context, context.tr('app.saved'));
    } on ApiException catch (e) {
      if (!mounted) return;
      final errors = e.extra['errors'];
      showSnack(context, errors is Map ? errors.entries.map((x) => '${x.key}: ${(x.value as List).join(' ')}').join('\n') : context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String k, {int lines = 1, TextInputType? type}) => TextField(
        controller: _c[k],
        maxLines: lines,
        keyboardType: type,
        decoration: InputDecoration(labelText: context.tr('settings.${_labels[k] ?? k}')),
      );

  Widget _switch(String k, String label) =>
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.tr(label)), value: _flags[k] ?? true, onChanged: (v) => setState(() => _flags[k] = v));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr('more.settings'))),
        bottomNavigationBar: _loading ? null : SaveButton(busy: _busy, onPressed: _save),
        body: _error != null
            ? ErrorView(error: _error!, onRetry: _load)
            : _loading
                ? const LoadingView()
                : ListView(padding: const EdgeInsets.all(12), children: [
                    FormCard(title: context.tr('settings.orders'), children: [
                      _switch('orders_enabled', 'settings.orders_enabled'),
                      _field('min_order_total', type: TextInputType.number),
                      _field('low_stock_threshold', type: TextInputType.number),
                    ]),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.chat_outlined, color: Color(0xFF25D366)),
                        title: Text(context.tr('wa.title')),
                        subtitle: Text(context.tr('wa.subtitle')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WhatsAppSettingsScreen())),
                      ),
                    ),
                    FormCard(title: context.tr('settings.credit'), children: [
                      _field('default_credit_limit', type: const TextInputType.numberWithOptions(decimal: true)),
                      Text(context.tr('settings.credit_limit_hint'), style: Theme.of(context).textTheme.bodySmall),
                    ]),
                    FormCard(title: context.tr('settings.discount'), children: [
                      _switch('app_discount_enabled', 'settings.app_discount_on'),
                      _field('app_discount_percent', type: const TextInputType.numberWithOptions(decimal: true)),
                    ]),
                    FormCard(title: context.tr('settings.delivery'), children: [
                      _switch('pickup_enabled', 'settings.pickup_on'),
                      _field('pickup_address_ar'),
                      _field('pickup_address_en'),
                      _switch('delivery_enabled', 'settings.delivery_on'),
                      _field('delivery_currency_ar'),
                      _field('delivery_currency_en'),
                    ]),
                    FormCard(title: context.tr('settings.contact'), children: [
                      _field('mobile', type: TextInputType.phone),
                      _field('whatsapp', type: TextInputType.phone),
                      _field('phone', type: TextInputType.phone),
                      _field('email', type: TextInputType.emailAddress),
                      _field('website', type: TextInputType.url),
                      _field('address_ar'),
                      _field('address_en'),
                      _field('working_hours_ar'),
                      _field('working_hours_en'),
                      _field('facebook', type: TextInputType.url),
                      _field('instagram', type: TextInputType.url),
                      _field('telegram', type: TextInputType.url),
                    ]),
                    FormCard(title: context.tr('settings.store'), children: [
                      _field('name_ar'),
                      _field('name_en'),
                      _field('about_ar', lines: 5),
                      _field('about_en', lines: 5),
                    ]),
                  ]),
      );
}

class LegalPagesScreen extends StatelessWidget {
  const LegalPagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminApi>();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('more.legal'))),
      body: AsyncView<List<LegalPage>>(
        load: api.legalPages,
        builder: (context, pages, reload) => ListView(padding: const EdgeInsets.all(12), children: [
          for (final p in pages)
            Card(
              child: ListTile(
                title: Text(p.title(context.lang)),
                subtitle: Text('$apiBaseUrl/legal/${p.slug}/', textDirection: TextDirection.ltr),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _LegalEditor(page: p)));
                  reload();
                },
              ),
            ),
        ]),
      ),
    );
  }
}

class _LegalEditor extends StatefulWidget {
  const _LegalEditor({required this.page});

  final LegalPage page;

  @override
  State<_LegalEditor> createState() => _LegalEditorState();
}

class _LegalEditorState extends State<_LegalEditor> {
  late final _titleAr = TextEditingController(text: widget.page.titleAr);
  late final _titleEn = TextEditingController(text: widget.page.titleEn);
  late final _bodyAr = TextEditingController(text: widget.page.bodyAr);
  late final _bodyEn = TextEditingController(text: widget.page.bodyEn);
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await context.read<AdminApi>().saveLegal(widget.page.slug, {
        'title_ar': _titleAr.text.trim(),
        'title_en': _titleEn.text.trim(),
        'body_ar': _bodyAr.text,
        'body_en': _bodyEn.text,
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.page.title(context.lang))),
        bottomNavigationBar: SaveButton(busy: _busy, onPressed: _save),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Text(context.tr('legal.edit_hint'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(controller: _titleAr, decoration: InputDecoration(labelText: context.tr('legal.title_ar'))),
          const SizedBox(height: 12),
          TextField(controller: _bodyAr, maxLines: 18, minLines: 8, decoration: InputDecoration(labelText: context.tr('legal.body_ar'), alignLabelWithHint: true)),
          const SizedBox(height: 12),
          TextField(controller: _titleEn, decoration: InputDecoration(labelText: context.tr('legal.title_en'))),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyEn,
            maxLines: 18,
            minLines: 8,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: context.tr('legal.body_en'), alignLabelWithHint: true),
          ),
        ]),
      );
}
