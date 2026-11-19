import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/store_api.dart';
import '../../state/session.dart';
import '../../widgets/pin_field.dart';
import '../../widgets/profile_form.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  Key _key = UniqueKey();

  void _reload() => setState(() => _key = UniqueKey());

  Future<void> _edit([Address? a]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AddressFormScreen(address: a)));
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<StoreApi>();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('addr.title'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: Text(context.tr('addr.add'))),
      body: AsyncView<List<Address>>(
        key: _key,
        load: api.addresses,
        builder: (context, list, reload) => list.isEmpty
            ? EmptyView(icon: Icons.place_outlined, title: context.tr('addr.empty'), action: context.tr('addr.add'), onAction: () => _edit())
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final a = list[i];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      leading: Icon(a.isDefault ? Icons.star_rounded : Icons.place_outlined, color: a.isDefault ? AlasColors.warning : null),
                      title: Text(a.label.isNotEmpty ? a.label : a.recipientName),
                      subtitle: Text('${a.oneLine}\n${a.recipientName} · ${a.phone}'),
                      isThreeLine: true,
                      onTap: () => _edit(a),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'default') {
                            await api.saveAddress(Address(
                              id: a.id, label: a.label, recipientName: a.recipientName, phone: a.phone, city: a.city,
                              deliveryAreaId: a.deliveryAreaId, area: a.area, street: a.street, details: a.details,
                              latitude: a.latitude, longitude: a.longitude, isDefault: true,
                            ));
                          } else if (v == 'delete' && await confirmDialog(context, title: context.tr('addr.delete_confirm'), danger: true)) {
                            await api.deleteAddress(a.id!);
                          } else {
                            return;
                          }
                          _reload();
                        },
                        itemBuilder: (ctx) => [
                          if (!a.isDefault) PopupMenuItem(value: 'default', child: Text(ctx.tr('addr.make_default'))),
                          PopupMenuItem(value: 'delete', child: Text(ctx.tr('app.delete'))),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class AddressFormScreen extends StatefulWidget {
  const AddressFormScreen({super.key, this.address});

  final Address? address;

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Address? a = widget.address;
  late final AppUser? _user = context.read<Session>().user;
  late final _label = TextEditingController(text: a?.label ?? _user?.businessName ?? '');
  late final _recipient = TextEditingController(text: a?.recipientName ?? _user?.fullName ?? '');
  late final _phone = TextEditingController(text: a?.phone ?? _user?.phone ?? '');
  late final _details = TextEditingController(text: a?.details ?? '');
  late AreaChoice? _area = a == null || a!.area.isEmpty ? null : AreaChoice(a!.deliveryAreaId, a!.area);
  late bool _default = a?.isDefault ?? false;
  late LatLng? _pin = a?.pin;
  DeliveryInfo? _info;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.read<StoreApi>().delivery().then((v) => mounted ? setState(() => _info = v) : null).catchError((_) => null);
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? context.tr('app.required') : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<StoreApi>().saveAddress(Address(
        id: a?.id,
        label: _label.text.trim(),
        recipientName: _recipient.text.trim(),
        phone: _phone.text.trim(),
        deliveryAreaId: _area?.id,
        area: _area?.name ?? '',
        street: a?.street ?? '',
        details: _details.text.trim(),
        latitude: _pin?.latitude,
        longitude: _pin?.longitude,
        isDefault: _default,
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr(a == null ? 'addr.add' : 'addr.edit'))),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            TextFormField(controller: _label, decoration: InputDecoration(labelText: context.tr('addr.label'))),
            const SizedBox(height: 12),
            TextFormField(controller: _recipient, decoration: InputDecoration(labelText: context.tr('addr.recipient')), validator: _req),
            const SizedBox(height: 12),
            TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: context.tr('co.phone')), validator: _req),
            const SizedBox(height: 12),
            AreaField(info: _info, initialValue: _area, onChanged: (v) => _area = v, validator: (v) => v == null ? context.tr('app.required') : null),
            const SizedBox(height: 12),
            TextFormField(
              controller: _details,
              maxLines: 2,
              decoration: InputDecoration(labelText: context.tr('profile.address'), hintText: context.tr('profile.address_hint')),
              validator: _req,
            ),
            const SizedBox(height: 12),
            PinField(value: _pin, onChanged: (p) => setState(() => _pin = p)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('addr.default')),
              value: _default,
              onChanged: (v) => setState(() => _default = v),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(context.tr('app.save')),
            ),
          ]),
        ),
      );
}
