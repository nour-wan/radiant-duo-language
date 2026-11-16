import 'dart:io' as io;

import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/admin_api.dart';
import '../widgets/admin_widgets.dart';

// ───────────────────────────── Categories ─────────────────────────────

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  Key _key = UniqueKey();

  Future<void> _edit([Category? c]) async {
    if (await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _CategoryForm(category: c))) == true) {
      setState(() => _key = UniqueKey());
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminApi>();
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('more.categories'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: Text(context.tr('cat.new'))),
      body: AsyncView<List<Category>>(
        key: _key,
        load: api.categories,
        builder: (context, cats, reload) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: cats.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final c = cats[i];
            return Card(
              child: ListTile(
                leading: SizedBox.square(dimension: 50, child: NetImage(c.image, radius: 8)),
                title: Text(c.name(lang)),
                subtitle: Text(context.tr('cat.products', {'n': c.productCount ?? 0})),
                trailing: c.isActive ? null : const Icon(Icons.visibility_off_outlined),
                onTap: () => _edit(c),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CategoryForm extends StatefulWidget {
  const _CategoryForm({this.category});

  final Category? category;

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  final _form = GlobalKey<FormState>();
  late final c = widget.category;
  late final _nameAr = TextEditingController(text: c?.nameAr);
  late final _nameEn = TextEditingController(text: c?.nameEn);
  late final _descAr = TextEditingController(text: c?.descriptionAr);
  late final _descEn = TextEditingController(text: c?.descriptionEn);
  late final _order = TextEditingController(text: '${c?.sortOrder ?? 0}');
  late bool _active = c?.isActive ?? true;
  String? _imagePath;
  bool _busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final api = context.read<AdminApi>();
    try {
      final saved = await api.saveCategory(c?.id, {
        'name_ar': _nameAr.text.trim(),
        'name_en': _nameEn.text.trim(),
        'description_ar': _descAr.text.trim(),
        'description_en': _descEn.text.trim(),
        'sort_order': int.tryParse(_order.text) ?? 0,
        'is_active': _active,
      });
      if (_imagePath != null) await api.uploadCategoryImage(saved.id, _imagePath!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, title: context.tr('cat.delete_confirm'), danger: true) || !mounted) return;
    try {
      await context.read<AdminApi>().deleteCategory(c!.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(context.tr(c == null ? 'cat.new' : 'cat.edit')),
          actions: [if (c != null) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete)],
        ),
        bottomNavigationBar: SaveButton(busy: _busy, onPressed: _save),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            _ImagePickerTile(
              label: context.tr('cat.image'),
              url: c?.image,
              path: _imagePath,
              onPicked: (p) => setState(() => _imagePath = p),
              aspectRatio: 1.6,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _nameAr, decoration: InputDecoration(labelText: context.tr('cat.name_ar')), validator: (v) => requiredField(context, v)),
            const SizedBox(height: 12),
            TextFormField(controller: _nameEn, decoration: InputDecoration(labelText: context.tr('cat.name_en')), validator: (v) => requiredField(context, v)),
            const SizedBox(height: 12),
            TextFormField(controller: _descAr, maxLines: 2, decoration: InputDecoration(labelText: context.tr('cat.desc_ar'))),
            const SizedBox(height: 12),
            TextFormField(controller: _descEn, maxLines: 2, decoration: InputDecoration(labelText: context.tr('cat.desc_en'))),
            const SizedBox(height: 12),
            TextFormField(controller: _order, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('cat.order'))),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.tr('cat.active')), value: _active, onChanged: (v) => setState(() => _active = v)),
          ]),
        ),
      );
}

class _ImagePickerTile extends StatelessWidget {
  const _ImagePickerTile({required this.label, required this.url, required this.path, required this.onPicked, this.aspectRatio = 2.1});

  final String label;
  final String? url, path;
  final ValueChanged<String> onPicked;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 90);
        if (f != null) onPicked(f.path);
      },
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: scheme.outline), borderRadius: BorderRadius.circular(10)),
          clipBehavior: Clip.antiAlias,
          child: Stack(fit: StackFit.expand, children: [
            if (path != null)
              Image.file(io.File(path!), fit: BoxFit.cover)
            else if (url != null && url!.isNotEmpty)
              NetImage(url)
            else
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.add_photo_alternate_outlined, size: 36),
                Text(label),
              ]),
            const PositionedDirectional(bottom: 8, end: 8, child: CircleAvatar(radius: 18, child: Icon(Icons.edit, size: 18))),
          ]),
        ),
      ),
    );
  }
}

// ───────────────────────────── Coupons ─────────────────────────────

class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});

  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  Key _key = UniqueKey();

  Future<void> _edit([Coupon? c]) async {
    if (await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _CouponForm(coupon: c))) == true) {
      setState(() => _key = UniqueKey());
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminApi>();
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('more.coupons'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: Text(context.tr('coupon.new'))),
      body: PagedList<Coupon>(
        key: _key,
        load: (page) => api.coupons(page: page),
        empty: EmptyView(icon: Icons.local_offer_outlined, title: context.tr('app.empty')),
        itemBuilder: (context, c, reload) {
          final active = c.isActive && !c.expired;
          return Card(
            child: ListTile(
              leading: Icon(Icons.local_offer, color: active ? AlasColors.primary : Colors.grey),
              title: Text(c.code, style: const TextStyle(fontFamily: 'packages/alas_shared/Manrope', fontWeight: FontWeight.w700, letterSpacing: 1)),
              subtitle: Text([
                c.kind == 'percent' ? '${c.value.toStringAsFixed(0)}%' : money(c.value),
                context.tr('coupon.used', {'n': c.usedCount}),
                if (c.expiresAt != null) formatDate(c.expiresAt!, lang),
              ].join(' · ')),
              trailing: Text(context.tr(active ? 'coupon.active' : 'coupon.expired'),
                  style: TextStyle(color: active ? AlasColors.primary : AlasColors.destructive, fontWeight: FontWeight.w700)),
              onTap: () => _edit(c),
            ),
          );
        },
      ),
    );
  }
}

class _CouponForm extends StatefulWidget {
  const _CouponForm({this.coupon});

  final Coupon? coupon;

  @override
  State<_CouponForm> createState() => _CouponFormState();
}

class _CouponFormState extends State<_CouponForm> {
  final _form = GlobalKey<FormState>();
  late final c = widget.coupon;
  late final _code = TextEditingController(text: c?.code);
  late final _value = TextEditingController(text: c?.value.toStringAsFixed(2));
  late final _min = TextEditingController(text: c?.minOrderTotal.toStringAsFixed(2) ?? '0');
  late final _maxDiscount = TextEditingController(text: c?.maxDiscount?.toStringAsFixed(2));
  late final _maxUses = TextEditingController(text: c?.maxUses?.toString());
  late final _perUser = TextEditingController(text: '${c?.maxUsesPerUser ?? 1}');
  late String _kind = c?.kind ?? 'percent';
  late DateTime? _expires = c?.expiresAt;
  late bool _active = c?.isActive ?? true;
  bool _busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<AdminApi>().saveCoupon(c?.id, {
        'code': _code.text.trim().toUpperCase(),
        'kind': _kind,
        'value': _value.text.trim(),
        'min_order_total': _min.text.trim().isEmpty ? '0' : _min.text.trim(),
        'max_discount': _maxDiscount.text.trim().isEmpty ? null : _maxDiscount.text.trim(),
        'max_uses': int.tryParse(_maxUses.text.trim()),
        'max_uses_per_user': int.tryParse(_perUser.text.trim()),
        'expires_at': _expires == null ? null : DateTime(_expires!.year, _expires!.month, _expires!.day, 23, 59).toUtc().toIso8601String(),
        'is_active': _active,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      final errors = e.extra['errors'];
      showSnack(context, errors is Map ? errors.values.expand((v) => v is List ? v : [v]).join('\n') : context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, title: context.tr('coupon.delete_confirm'), danger: true) || !mounted) return;
    await context.read<AdminApi>().deleteCoupon(c!.id!);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(context.tr(c == null ? 'coupon.new' : 'coupon.edit')),
          actions: [if (c != null) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete)],
        ),
        bottomNavigationBar: SaveButton(busy: _busy, onPressed: _save),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            TextFormField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: context.tr('coupon.code')),
              validator: (v) => requiredField(context, v),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'percent', label: Text(context.tr('coupon.percent'))),
                ButtonSegment(value: 'fixed', label: Text(context.tr('coupon.fixed'))),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: context.tr('coupon.value'), suffixText: _kind == 'percent' ? '%' : '\$'),
              validator: (v) => moneyField(context, v),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _min, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('coupon.min_total'))),
            const SizedBox(height: 12),
            TextFormField(controller: _maxDiscount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('coupon.max_discount'))),
            const SizedBox(height: 12),
            TextFormField(controller: _maxUses, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('coupon.max_uses'))),
            const SizedBox(height: 12),
            TextFormField(controller: _perUser, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('coupon.per_user'))),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(context.tr('coupon.expires')),
              subtitle: Text(_expires == null ? context.tr('coupon.no_expiry') : formatDate(_expires!, context.lang)),
              trailing: _expires == null ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _expires = null)),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _expires ?? DateTime.now().add(const Duration(days: 30)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                );
                if (d != null) setState(() => _expires = d);
              },
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.tr('coupon.active')), value: _active, onChanged: (v) => setState(() => _active = v)),
          ]),
        ),
      );
}

// ───────────────────────────── Banners ─────────────────────────────

class BannersScreen extends StatefulWidget {
  const BannersScreen({super.key});

  @override
  State<BannersScreen> createState() => _BannersScreenState();
}

class _BannersScreenState extends State<BannersScreen> {
  Key _key = UniqueKey();

  Future<void> _edit([BannerItem? b]) async {
    if (await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _BannerForm(banner: b))) == true) {
      setState(() => _key = UniqueKey());
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminApi>();
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('more.banners'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: Text(context.tr('banner.new'))),
      body: AsyncView<List<BannerItem>>(
        key: _key,
        load: api.banners,
        builder: (context, list, reload) => list.isEmpty
            ? EmptyView(icon: Icons.view_carousel_outlined, title: context.tr('app.empty'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final b = list[i];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _edit(b),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Opacity(opacity: b.isActive ? 1 : .4, child: NetImage(b.image, aspectRatio: 2.1)),
                        ListTile(
                          title: Text(b.title(lang).isEmpty ? '—' : b.title(lang)),
                          subtitle: Text(b.subtitle(lang)),
                          trailing: b.isActive ? null : const Icon(Icons.visibility_off_outlined),
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _BannerForm extends StatefulWidget {
  const _BannerForm({this.banner});

  final BannerItem? banner;

  @override
  State<_BannerForm> createState() => _BannerFormState();
}

class _BannerFormState extends State<_BannerForm> {
  late final b = widget.banner;
  late final _titleAr = TextEditingController(text: b?.titleAr);
  late final _titleEn = TextEditingController(text: b?.titleEn);
  late final _subAr = TextEditingController(text: b?.subtitleAr);
  late final _subEn = TextEditingController(text: b?.subtitleEn);
  late final _linkValue = TextEditingController(text: b?.linkValue);
  late final _order = TextEditingController(text: '${b?.sortOrder ?? 0}');
  late String _linkType = b?.linkType ?? 'none';
  late bool _active = b?.isActive ?? true;
  String? _imagePath;
  int? _categoryId;
  List<Category> _categories = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_linkType == 'category') _categoryId = int.tryParse(b?.linkValue ?? '');
    context.read<AdminApi>().categories().then((c) => mounted ? setState(() => _categories = c) : null).catchError((_) => null);
  }

  Future<void> _save() async {
    if (b == null && _imagePath == null) {
      showSnack(context, context.tr('err.image_required'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AdminApi>().saveBanner(b?.id, {
        'title_ar': _titleAr.text.trim(),
        'title_en': _titleEn.text.trim(),
        'subtitle_ar': _subAr.text.trim(),
        'subtitle_en': _subEn.text.trim(),
        'link_type': _linkType,
        'link_value': _linkType == 'category' ? '${_categoryId ?? ''}' : (_linkType == 'none' ? '' : _linkValue.text.trim()),
        'sort_order': int.tryParse(_order.text) ?? 0,
        'is_active': _active,
      }, imagePath: _imagePath);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, title: context.tr('banner.delete_confirm'), danger: true) || !mounted) return;
    await context.read<AdminApi>().deleteBanner(b!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(context.tr(b == null ? 'banner.new' : 'banner.edit')),
          actions: [if (b != null) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete)],
        ),
        bottomNavigationBar: SaveButton(busy: _busy, onPressed: _save),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          _ImagePickerTile(label: context.tr('banner.image'), url: b?.image, path: _imagePath, onPicked: (p) => setState(() => _imagePath = p)),
          const SizedBox(height: 12),
          TextField(controller: _titleAr, decoration: InputDecoration(labelText: context.tr('banner.title_ar'))),
          const SizedBox(height: 12),
          TextField(controller: _subAr, decoration: InputDecoration(labelText: context.tr('banner.sub_ar'))),
          const SizedBox(height: 12),
          TextField(controller: _titleEn, decoration: InputDecoration(labelText: context.tr('banner.title_en'))),
          const SizedBox(height: 12),
          TextField(controller: _subEn, decoration: InputDecoration(labelText: context.tr('banner.sub_en'))),
          const SizedBox(height: 16),
          Text(context.tr('banner.link'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              for (final k in ['none', 'category', 'product', 'url']) ButtonSegment(value: k, label: Text(context.tr('banner.link_$k'))),
            ],
            selected: {_linkType},
            onSelectionChanged: (s) => setState(() => _linkType = s.first),
          ),
          const SizedBox(height: 12),
          if (_linkType == 'category')
            DropdownButtonFormField<int>(
              initialValue: _categoryId,
              items: [for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.name(context.lang)))],
              onChanged: (v) => _categoryId = v,
            )
          else if (_linkType != 'none')
            TextField(
              controller: _linkValue,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: context.tr(_linkType == 'url' ? 'banner.link_value_url' : 'banner.link_value_product')),
            ),
          const SizedBox(height: 12),
          TextField(controller: _order, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('cat.order'))),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.tr('cat.active')), value: _active, onChanged: (v) => setState(() => _active = v)),
        ]),
      );
}

// ───────────────────────────── Delivery zones ─────────────────────────────

class ZonesScreen extends StatefulWidget {
  const ZonesScreen({super.key});

  @override
  State<ZonesScreen> createState() => _ZonesScreenState();
}

class _ZonesScreenState extends State<ZonesScreen> {
  Key _key = UniqueKey();

  Future<void> _edit([DeliveryZone? z]) async {
    if (await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _ZoneForm(zone: z))) == true) {
      setState(() => _key = UniqueKey());
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminApi>();
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('more.zones'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: Text(context.tr('zone.new'))),
      body: AsyncView<List<DeliveryZone>>(
        key: _key,
        load: api.zones,
        builder: (context, zones, reload) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: zones.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final z = zones[i];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text(z.name(lang)),
                subtitle: Text(z.areas.map((a) => a.name(lang)).join('، '), maxLines: 3, overflow: TextOverflow.ellipsis),
                trailing: Text(z.fee.toStringAsFixed(0), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AlasColors.primary)),
                onTap: () => _edit(z),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ZoneForm extends StatefulWidget {
  const _ZoneForm({this.zone});

  final DeliveryZone? zone;

  @override
  State<_ZoneForm> createState() => _ZoneFormState();
}

class _ZoneFormState extends State<_ZoneForm> {
  final _form = GlobalKey<FormState>();
  late final z = widget.zone;
  late final _nameAr = TextEditingController(text: z?.nameAr);
  late final _nameEn = TextEditingController(text: z?.nameEn);
  late final _fee = TextEditingController(text: z?.fee.toStringAsFixed(0) ?? '');
  late bool _unlisted = z?.isDefaultForUnlisted ?? false;
  late bool _active = z?.isActive ?? true;
  late final List<(int?, TextEditingController, TextEditingController)> _areas = [
    for (final a in z?.areas ?? <DeliveryArea>[]) (a.id, TextEditingController(text: a.nameAr), TextEditingController(text: a.nameEn)),
  ];
  bool _busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<AdminApi>().saveZone(z?.id, {
        'name_ar': _nameAr.text.trim(),
        'name_en': _nameEn.text.trim(),
        'fee': _fee.text.trim(),
        'is_default_for_unlisted': _unlisted,
        'is_active': _active,
        'areas': [
          for (final (i, (id, ar, en)) in _areas.indexed)
            if (ar.text.trim().isNotEmpty) {if (id != null) 'id': id, 'name_ar': ar.text.trim(), 'name_en': en.text.trim(), 'sort_order': i},
        ],
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, title: context.tr('zone.delete_confirm'), danger: true) || !mounted) return;
    await context.read<AdminApi>().deleteZone(z!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(context.tr(z == null ? 'zone.new' : 'zone.edit')),
          actions: [if (z != null) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete)],
        ),
        bottomNavigationBar: SaveButton(busy: _busy, onPressed: _save),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            TextFormField(controller: _nameAr, decoration: InputDecoration(labelText: context.tr('zone.name_ar')), validator: (v) => requiredField(context, v)),
            const SizedBox(height: 12),
            TextFormField(controller: _nameEn, decoration: InputDecoration(labelText: context.tr('zone.name_en')), validator: (v) => requiredField(context, v)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fee,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: context.tr('zone.fee')),
              validator: (v) => moneyField(context, v),
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.tr('zone.unlisted')), value: _unlisted, onChanged: (v) => setState(() => _unlisted = v)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.tr('cat.active')), value: _active, onChanged: (v) => setState(() => _active = v)),
            const Divider(),
            Row(children: [
              Expanded(child: Text(context.tr('zone.areas', {'n': _areas.length}), style: Theme.of(context).textTheme.titleSmall)),
              TextButton.icon(
                onPressed: () => setState(() => _areas.add((null, TextEditingController(), TextEditingController()))),
                icon: const Icon(Icons.add),
                label: Text(context.tr('zone.add_area')),
              ),
            ]),
            for (final entry in _areas)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(flex: 3, child: TextField(controller: entry.$2, decoration: InputDecoration(labelText: context.tr('zone.area_ar'), isDense: true))),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: TextField(controller: entry.$3, decoration: InputDecoration(labelText: context.tr('zone.area_en'), isDense: true))),
                  IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setState(() => _areas.remove(entry))),
                ]),
              ),
          ]),
        ),
      );
}
