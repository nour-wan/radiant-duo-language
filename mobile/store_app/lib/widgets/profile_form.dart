import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/store_api.dart';

/// Area picked from the delivery list (id set) or typed by the customer (id null).
class AreaChoice {
  const AreaChoice(this.id, this.name);

  final int? id;
  final String name;
}

/// Bottom sheet with a searchable list of delivery areas grouped by zone.
Future<AreaChoice?> pickArea(BuildContext context, DeliveryInfo info) => showModalBottomSheet<AreaChoice>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _AreaSheet(info: info),
    );

class _AreaSheet extends StatefulWidget {
  const _AreaSheet({required this.info});

  final DeliveryInfo info;

  @override
  State<_AreaSheet> createState() => _AreaSheetState();
}

class _AreaSheetState extends State<_AreaSheet> {
  String _q = '';
  bool _other = false;
  final _otherName = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lang = context.lang;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: context.tr('area.search')),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          Expanded(
            child: ListView(children: [
              for (final z in widget.info.zones) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('${z.name(lang)} · ${money(z.fee)}',
                      style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary)),
                ),
                for (final a in z.areas.where((a) => _q.isEmpty || a.nameAr.contains(_q) || a.nameEn.toLowerCase().contains(_q.toLowerCase())))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined),
                    title: Text(a.name(lang)),
                    onTap: () => Navigator.pop(context, AreaChoice(a.id, a.nameAr)),
                  ),
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.edit_location_alt_outlined),
                title: Text(context.tr('area.other')),
                onTap: () => setState(() => _other = true),
              ),
              if (_other)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(children: [
                    Expanded(child: TextField(controller: _otherName, autofocus: true, decoration: InputDecoration(labelText: context.tr('area.other_name')))),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final name = _otherName.text.trim();
                        if (name.isNotEmpty) Navigator.pop(context, AreaChoice(null, name));
                      },
                      child: Text(context.tr('app.confirm')),
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Form field that opens the area picker.
class AreaField extends FormField<AreaChoice> {
  AreaField({super.key, required DeliveryInfo? info, super.initialValue, ValueChanged<AreaChoice>? onChanged, super.validator})
      : super(builder: (state) {
          final context = state.context;
          return InkWell(
            onTap: info == null
                ? null
                : () async {
                    final choice = await pickArea(context, info);
                    if (choice != null) {
                      state.didChange(choice);
                      onChanged?.call(choice);
                    }
                  },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: context.tr('area.label'),
                prefixIcon: const Icon(Icons.place_outlined),
                suffixIcon: const Icon(Icons.expand_more),
                errorText: state.errorText,
              ),
              isEmpty: state.value == null,
              child: Text(state.value == null
                  ? ''
                  : (state.value!.id != null ? info?.area(state.value!.id)?.name(context.lang) ?? state.value!.name : state.value!.name)),
            ),
          );
        });
}

/// Values collected by [BusinessProfileFields].
class BusinessProfile {
  BusinessProfile.from(AppUser? u)
      : name = TextEditingController(text: u?.fullName ?? ''),
        business = TextEditingController(text: u?.businessName ?? ''),
        address = TextEditingController(text: u?.address ?? ''),
        type = (u?.businessType.isNotEmpty ?? false) ? u!.businessType : null,
        area = (u != null && u.areaName.isNotEmpty) ? AreaChoice(u.deliveryAreaId, u.areaName) : null,
        interests = {...?u?.interests};

  final TextEditingController name, business, address;
  String? type;
  AreaChoice? area;
  Set<int> interests;

  Map<String, dynamic> toJson() => {
        'full_name': name.text.trim(),
        'business_name': business.text.trim(),
        'business_type': type,
        'delivery_area': area?.id,
        'area_name': area?.name ?? '',
        'address': address.text.trim(),
        'interests': interests.toList(),
      };

  void dispose() {
    for (final c in [name, business, address]) {
      c.dispose();
    }
  }
}

/// The business fields asked at sign-up: name, business name & type, area,
/// detailed address and the categories the customer orders most.
class BusinessProfileFields extends StatefulWidget {
  const BusinessProfileFields({super.key, required this.profile});

  final BusinessProfile profile;

  @override
  State<BusinessProfileFields> createState() => _BusinessProfileFieldsState();
}

class _BusinessProfileFieldsState extends State<BusinessProfileFields> {
  DeliveryInfo? _info;
  List<Category> _categories = [];

  @override
  void initState() {
    super.initState();
    final api = context.read<StoreApi>();
    api.delivery().then((v) => mounted ? setState(() => _info = v) : null).catchError((_) => null);
    api.categories().then((v) => mounted ? setState(() => _categories = v) : null).catchError((_) => null);
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? context.tr('app.required') : null;

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextFormField(controller: p.name, decoration: InputDecoration(labelText: context.tr('auth.full_name')), validator: _req),
      const SizedBox(height: 12),
      TextFormField(
        controller: p.business,
        decoration: InputDecoration(labelText: context.tr('profile.business_name'), hintText: context.tr('profile.business_hint')),
        validator: _req,
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: p.type,
        decoration: InputDecoration(labelText: context.tr('profile.business_type')),
        items: [for (final b in businessTypes) DropdownMenuItem(value: b, child: Text(context.tr('biz.$b')))],
        onChanged: (v) => setState(() => p.type = v),
        validator: (v) => v == null ? context.tr('app.required') : null,
      ),
      const SizedBox(height: 12),
      AreaField(
        info: _info,
        initialValue: p.area,
        onChanged: (a) => p.area = a,
        validator: (v) => v == null ? context.tr('app.required') : null,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: p.address,
        decoration: InputDecoration(labelText: context.tr('profile.address'), hintText: context.tr('profile.address_hint')),
        maxLines: 2,
        validator: _req,
      ),
      const SizedBox(height: 18),
      Text(context.tr('profile.interests'), style: t.textTheme.titleSmall),
      Text(context.tr('profile.interests_hint'), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 8),
      FormField<Set<int>>(
        initialValue: p.interests,
        validator: (_) => p.interests.isEmpty ? context.tr('profile.interests_required') : null,
        builder: (state) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_categories.isEmpty) const LinearProgressIndicator(),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in _categories)
              FilterChip(
                label: Text(c.name(context.lang)),
                selected: p.interests.contains(c.id),
                onSelected: (on) {
                  setState(() => on ? p.interests.add(c.id) : p.interests.remove(c.id));
                  state.didChange(p.interests);
                },
              ),
          ]),
          if (state.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(state.errorText!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.error)),
            ),
        ]),
      ),
    ]);
  }
}
