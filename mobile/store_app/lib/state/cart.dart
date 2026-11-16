import 'dart:convert';

import 'package:alas_shared/alas_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/store_api.dart';

class CartLine {
  CartLine({
    required this.variantId,
    required this.productId,
    required this.productSlug,
    required this.nameAr,
    required this.nameEn,
    required this.labelAr,
    required this.labelEn,
    required this.image,
    required this.unitPrice,
    required this.regularPrice,
    required this.quantity,
    required this.minQty,
    required this.stock,
  });

  factory CartLine.fromJson(Map<String, dynamic> j) => CartLine(
        variantId: j['v'] as int,
        productId: j['p'] as int,
        productSlug: j['s'] as String? ?? '',
        nameAr: j['na'] as String? ?? '',
        nameEn: j['ne'] as String? ?? '',
        labelAr: j['la'] as String? ?? '',
        labelEn: j['le'] as String? ?? '',
        image: j['i'] as String?,
        unitPrice: toMoney(j['u']),
        regularPrice: toMoney(j['r']),
        quantity: j['q'] as int,
        minQty: j['m'] as int? ?? 1,
        stock: j['st'] as int? ?? 0,
      );

  final int variantId, productId;
  final String productSlug, nameAr, nameEn, labelAr, labelEn;
  final String? image;
  double unitPrice, regularPrice;
  int quantity, minQty, stock;
  String? problem;

  String name(String lang) => pick(lang, nameAr, nameEn);
  String label(String lang) => pick(lang, labelAr, labelEn);
  double get total => unitPrice * quantity;

  Map<String, dynamic> toJson() => {
        'v': variantId, 'p': productId, 's': productSlug, 'na': nameAr, 'ne': nameEn, 'la': labelAr, 'le': labelEn,
        'i': image, 'u': unitPrice, 'r': regularPrice, 'q': quantity, 'm': minQty, 'st': stock,
      };
}

/// Cart lives on the device (works for guests). Prices shown come from the
/// server quote; the server re-prices everything again when the order is placed.
class Cart extends ChangeNotifier {
  Cart(this._prefs, this._api) {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      try {
        lines.addAll((jsonDecode(raw) as List).map((e) => CartLine.fromJson(e as Map<String, dynamic>)));
      } catch (_) {}
    }
    coupon = _prefs.getString('$_key.coupon');
  }

  static const _key = 'cart.v1';
  final SharedPreferences _prefs;
  final StoreApi _api;
  final List<CartLine> lines = [];
  String? coupon;
  /// Chosen at checkout; the server prices the delivery fee for the area.
  String? deliveryMethod;
  int? deliveryAreaId;
  Quote? quote;
  bool quoting = false;
  Object? quoteError;
  int _quoteSeq = 0;

  int get count => lines.length;
  bool get isEmpty => lines.isEmpty;
  double get localSubtotal => lines.fold(0, (s, l) => s + l.total);

  int quantityOf(int variantId) => lines.where((l) => l.variantId == variantId).firstOrNull?.quantity ?? 0;

  void _persist() {
    _prefs.setString(_key, jsonEncode(lines.map((l) => l.toJson()).toList()));
    if (coupon == null) {
      _prefs.remove('$_key.coupon');
    } else {
      _prefs.setString('$_key.coupon', coupon!);
    }
  }

  void add(ProductDetail p, Variant v, int qty) {
    final existing = lines.where((l) => l.variantId == v.id).firstOrNull;
    if (existing != null) {
      existing.quantity = (existing.quantity + qty).clamp(v.minOrderQty, v.stock < v.minOrderQty ? v.minOrderQty : v.stock);
      existing.unitPrice = v.effectivePrice;
    } else {
      lines.add(CartLine(
        variantId: v.id!,
        productId: p.id,
        productSlug: p.slug,
        nameAr: p.nameAr,
        nameEn: p.nameEn,
        labelAr: v.labelAr,
        labelEn: v.labelEn,
        image: p.images.isNotEmpty ? p.images.first.thumbnail : p.thumbnail,
        unitPrice: v.effectivePrice,
        regularPrice: v.price,
        quantity: qty,
        minQty: v.minOrderQty,
        stock: v.stock,
      ));
    }
    _changed();
  }

  void addFromOrder(OrderItem item, int qty) {
    if (item.variantId == null || item.productId == null) return;
    final existing = lines.where((l) => l.variantId == item.variantId).firstOrNull;
    if (existing != null) {
      existing.quantity += qty;
    } else {
      lines.add(CartLine(
        variantId: item.variantId!,
        productId: item.productId!,
        productSlug: '${item.productId}',
        nameAr: item.productNameAr,
        nameEn: item.productNameEn,
        labelAr: item.variantLabelAr,
        labelEn: item.variantLabelEn,
        image: item.image,
        unitPrice: item.unitPrice,
        regularPrice: item.unitPrice,
        quantity: qty,
        minQty: 1,
        stock: qty,
      ));
    }
    _changed();
  }

  void setQuantity(int variantId, int qty) {
    final line = lines.where((l) => l.variantId == variantId).firstOrNull;
    if (line == null) return;
    line.quantity = qty.clamp(1, 100000);
    _changed();
  }

  void remove(int variantId) {
    lines.removeWhere((l) => l.variantId == variantId);
    _changed();
  }

  void clear() {
    lines.clear();
    coupon = null;
    quote = null;
    _changed(requote: false);
  }

  void setDelivery(String method, int? areaId) {
    if (method == deliveryMethod && areaId == deliveryAreaId) return;
    deliveryMethod = method;
    deliveryAreaId = areaId;
    refreshQuote();
  }

  void setCoupon(String? code) {
    coupon = (code == null || code.trim().isEmpty) ? null : code.trim().toUpperCase();
    _changed();
  }

  List<Map<String, dynamic>> get items => [for (final l in lines) {'variant_id': l.variantId, 'quantity': l.quantity}];

  void _changed({bool requote = true}) {
    _persist();
    notifyListeners();
    if (requote) refreshQuote();
  }

  /// Ask the server for current prices, stock and coupon validity.
  Future<void> refreshQuote() async {
    if (lines.isEmpty) {
      quote = null;
      notifyListeners();
      return;
    }
    final seq = ++_quoteSeq;
    quoting = true;
    notifyListeners();
    try {
      final q = await _api.quote(items, coupon, deliveryMethod: deliveryMethod, areaId: deliveryAreaId);
      if (seq != _quoteSeq) return;
      quote = q;
      quoteError = null;
      for (final l in lines) {
        final ql = q.line(l.variantId);
        if (ql == null) continue;
        l
          ..unitPrice = ql.unitPrice
          ..regularPrice = ql.regularPrice
          ..stock = ql.stock
          ..minQty = ql.minOrderQty
          ..problem = ql.problem;
      }
      _persist();
    } on ApiException catch (e) {
      if (seq != _quoteSeq) return;
      quoteError = e;
      if (e.code == 'item_unavailable' && e.extra['variant_id'] is int) {
        lines.removeWhere((l) => l.variantId == e.extra['variant_id']);
        _persist();
        quoting = false;
        return refreshQuote();
      }
    } finally {
      if (seq == _quoteSeq) {
        quoting = false;
        notifyListeners();
      }
    }
  }
}
