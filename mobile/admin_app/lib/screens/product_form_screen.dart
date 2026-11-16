import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/admin_api.dart';
import '../widgets/admin_widgets.dart';

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.productId});

  final int? productId;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _VariantRow {
  _VariantRow([Variant? v])
      : id = v?.id,
        labelAr = TextEditingController(text: v?.labelAr ?? ''),
        labelEn = TextEditingController(text: v?.labelEn ?? ''),
        size = TextEditingController(text: v == null ? '1' : _num(v.unitQuantity)),
        price = TextEditingController(text: v == null ? '' : v.price.toStringAsFixed(2)),
        discount = TextEditingController(text: v?.discountPrice?.toStringAsFixed(2) ?? ''),
        stock = TextEditingController(text: '${v?.stock ?? 0}'),
        moq = TextEditingController(text: '${v?.minOrderQty ?? 1}'),
        sku = TextEditingController(text: v?.sku ?? ''),
        unit = v?.unit ?? 'kg',
        active = v?.isActive ?? true;

  static String _num(double d) => d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toString();

  final int? id;
  final TextEditingController labelAr, labelEn, size, price, discount, stock, moq, sku;
  String unit;
  bool active;

  Map<String, dynamic> toJson(int order) => {
        if (id != null) 'id': id,
        'label_ar': labelAr.text.trim(),
        'label_en': labelEn.text.trim(),
        'unit': unit,
        'unit_quantity': size.text.trim().isEmpty ? '1' : size.text.trim(),
        'sku': sku.text.trim(),
        'price': price.text.trim(),
        'discount_price': discount.text.trim().isEmpty ? null : discount.text.trim(),
        'stock': int.tryParse(stock.text.trim()) ?? 0,
        'min_order_qty': int.tryParse(moq.text.trim()) ?? 1,
        'is_active': active,
        'sort_order': order,
      };
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  final _nameAr = TextEditingController();
  final _nameEn = TextEditingController();
  final _shortAr = TextEditingController();
  final _shortEn = TextEditingController();
  final _descAr = TextEditingController();
  final _descEn = TextEditingController();
  final _keywords = TextEditingController();
  int? _category;
  bool _active = true, _featured = false;
  final _variants = <_VariantRow>[];
  List<ProductImage> _images = [];
  List<Category> _categories = [];
  List<Map<String, dynamic>> _specs = [];
  int? _id;
  bool _loading = true, _busy = false, _uploading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _id = widget.productId;
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AdminApi>();
    try {
      _categories = await api.categories();
      if (_id != null) {
        _fill(await api.product(_id!));
      } else {
        _variants.add(_VariantRow());
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _fill(AdminProduct p) {
    _nameAr.text = p.nameAr;
    _nameEn.text = p.nameEn;
    _shortAr.text = p.shortAr;
    _shortEn.text = p.shortEn;
    _descAr.text = p.descriptionAr;
    _descEn.text = p.descriptionEn;
    _keywords.text = p.keywords;
    _category = p.categoryId;
    _active = p.isActive;
    _featured = p.isFeatured;
    _images = p.images;
    _specs = p.specifications;
    _variants
      ..clear()
      ..addAll(p.variants.map(_VariantRow.new));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_variants.isEmpty) {
      showSnack(context, context.tr('product.need_variant'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await context.read<AdminApi>().saveProduct(_id, {
        'category': _category,
        'name_ar': _nameAr.text.trim(),
        'name_en': _nameEn.text.trim(),
        'short_description_ar': _shortAr.text.trim(),
        'short_description_en': _shortEn.text.trim(),
        'description_ar': _descAr.text.trim(),
        'description_en': _descEn.text.trim(),
        'keywords': _keywords.text.trim(),
        'is_active': _active,
        'is_featured': _featured,
        'specifications': _specs,
        'variants': [for (var i = 0; i < _variants.length; i++) _variants[i].toJson(i)],
      });
      if (!mounted) return;
      setState(() {
        _id = saved.id;
        _fill(saved);
      });
      showSnack(context, context.tr('product.saved'));
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addImages() async {
    final files = await ImagePicker().pickMultiImage(maxWidth: 2000, imageQuality: 90, limit: 10 - _images.length);
    if (files.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    final api = context.read<AdminApi>();
    try {
      await api.uploadProductImages(_id!, files.map((f) => f.path).toList());
      final p = await api.product(_id!);
      if (mounted) setState(() => _images = p.images);
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteImage(ProductImage img) async {
    if (!await confirmDialog(context, title: context.tr('app.delete'), danger: true) || !mounted) return;
    try {
      await context.read<AdminApi>().deleteProductImage(_id!, img.id);
      setState(() => _images = _images.where((i) => i.id != img.id).toList());
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    }
  }

  Future<void> _makeMain(ProductImage img) async {
    final ids = [img.id, ..._images.where((i) => i.id != img.id).map((i) => i.id)];
    await context.read<AdminApi>().reorderImages(_id!, ids);
    setState(() => _images = [img, ..._images.where((i) => i.id != img.id)]);
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, title: context.tr('product.delete_confirm'), danger: true) || !mounted) return;
    try {
      await context.read<AdminApi>().deleteProduct(_id!);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showSnack(context, context.trError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(_id == null ? 'product.new' : 'product.edit')),
        actions: [if (_id != null) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete)],
      ),
      bottomNavigationBar: _loading ? null : SaveButton(busy: _busy, onPressed: _save),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : _loading
              ? const LoadingView()
              : Form(
                  key: _form,
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                    FormCard(title: context.tr('product.images'), children: [
                      if (_id == null)
                        Text(context.tr('product.images_after_save'))
                      else
                        SizedBox(
                          height: 110,
                          child: ListView(scrollDirection: Axis.horizontal, children: [
                            for (final (i, img) in _images.indexed)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(end: 8),
                                child: Stack(children: [
                                  GestureDetector(
                                    onTap: i == 0 ? null : () => _makeMain(img),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(color: i == 0 ? AlasColors.primary : Colors.transparent, width: 2),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: SizedBox.square(dimension: 104, child: NetImage(img.thumbnail, radius: 8)),
                                    ),
                                  ),
                                  PositionedDirectional(
                                    top: 2,
                                    end: 2,
                                    child: IconButton.filledTonal(
                                      iconSize: 18,
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _deleteImage(img),
                                      icon: const Icon(Icons.close),
                                    ),
                                  ),
                                ]),
                              ),
                            if (_images.length < 10)
                              InkWell(
                                onTap: _uploading ? null : _addImages,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: 104,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: _uploading
                                      ? const Center(child: CircularProgressIndicator())
                                      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                          const Icon(Icons.add_photo_alternate_outlined),
                                          Text(context.tr('product.add_images'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                                        ]),
                                ),
                              ),
                          ]),
                        ),
                    ]),
                    FormCard(title: context.tr('product.category'), children: [
                      DropdownButtonFormField<int>(
                        initialValue: _category,
                        items: [for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.name(lang)))],
                        onChanged: (v) => _category = v,
                        validator: (v) => v == null ? context.tr('app.required') : null,
                      ),
                      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.tr('product.visible')), value: _active, onChanged: (v) => setState(() => _active = v)),
                      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.tr('product.featured')), value: _featured, onChanged: (v) => setState(() => _featured = v)),
                    ]),
                    FormCard(title: context.tr('product.name_ar'), children: [
                      TextFormField(controller: _nameAr, decoration: InputDecoration(labelText: context.tr('product.name_ar')), validator: (v) => requiredField(context, v)),
                      TextFormField(controller: _nameEn, decoration: InputDecoration(labelText: context.tr('product.name_en')), validator: (v) => requiredField(context, v)),
                      TextFormField(controller: _shortAr, maxLines: 2, decoration: InputDecoration(labelText: context.tr('product.short_ar'))),
                      TextFormField(controller: _shortEn, maxLines: 2, decoration: InputDecoration(labelText: context.tr('product.short_en'))),
                      TextFormField(controller: _descAr, maxLines: 5, decoration: InputDecoration(labelText: context.tr('product.desc_ar'))),
                      TextFormField(controller: _descEn, maxLines: 5, decoration: InputDecoration(labelText: context.tr('product.desc_en'))),
                      TextFormField(controller: _keywords, decoration: InputDecoration(labelText: context.tr('product.keywords'))),
                    ]),
                    FormCard(
                      title: context.tr('product.variants'),
                      trailing: TextButton.icon(
                        onPressed: () => setState(() => _variants.add(_VariantRow())),
                        icon: const Icon(Icons.add),
                        label: Text(context.tr('product.add_variant')),
                      ),
                      children: [
                        for (final (i, v) in _variants.indexed)
                          _VariantEditor(key: ObjectKey(v), row: v, index: i, onRemove: () => setState(() => _variants.remove(v))),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ]),
                ),
    );
  }
}

class _VariantEditor extends StatefulWidget {
  const _VariantEditor({super.key, required this.row, required this.index, required this.onRemove});

  final _VariantRow row;
  final int index;
  final VoidCallback onRemove;

  @override
  State<_VariantEditor> createState() => _VariantEditorState();
}

class _VariantEditorState extends State<_VariantEditor> {
  @override
  Widget build(BuildContext context) {
    final v = widget.row;
    Widget num(TextEditingController c, String label, {bool optional = false, bool integer = false}) => Expanded(
          child: TextFormField(
            controller: c,
            keyboardType: TextInputType.numberWithOptions(decimal: !integer),
            decoration: InputDecoration(labelText: label, isDense: true),
            validator: (s) => integer ? (int.tryParse(s ?? '') == null ? context.tr('err.invalid') : null) : moneyField(context, s, optional: optional),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outline), borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Row(children: [
          Text('${context.tr('variant.title')} ${widget.index + 1}', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          Switch(value: v.active, onChanged: (x) => setState(() => v.active = x)),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: widget.onRemove),
        ]),
        TextFormField(controller: v.labelAr, decoration: InputDecoration(labelText: context.tr('variant.label_ar'), isDense: true), validator: (s) => requiredField(context, s)),
        const SizedBox(height: 8),
        TextFormField(controller: v.labelEn, decoration: InputDecoration(labelText: context.tr('variant.label_en'), isDense: true), validator: (s) => requiredField(context, s)),
        const SizedBox(height: 8),
        Row(children: [
          num(v.size, context.tr('variant.size')),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: v.unit,
              isDense: true,
              decoration: InputDecoration(labelText: context.tr('variant.unit'), isDense: true),
              items: [for (final u in ['kg', 'g', 'l', 'ml', 'piece', 'carton']) DropdownMenuItem(value: u, child: Text(context.tr('unit.$u')))],
              onChanged: (u) => v.unit = u ?? 'kg',
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          num(v.price, context.tr('variant.price')),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: v.discount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: context.tr('variant.discount'), isDense: true),
              validator: (s) {
                if (s == null || s.trim().isEmpty) return null;
                final d = double.tryParse(s.trim()), p = double.tryParse(v.price.text.trim());
                if (d == null) return context.tr('err.invalid');
                if (p != null && d >= p) return context.tr('variant.discount_invalid');
                return null;
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          num(v.stock, context.tr('variant.stock'), integer: true),
          const SizedBox(width: 8),
          num(v.moq, context.tr('variant.moq'), integer: true),
        ]),
        const SizedBox(height: 8),
        TextFormField(controller: v.sku, decoration: InputDecoration(labelText: context.tr('variant.sku'), isDense: true)),
      ]),
    );
  }
}
