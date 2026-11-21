/// Data models shared by the store and admin apps. Money is kept as [double]
/// for display only — every real calculation happens on the server.
library;

import 'package:latlong2/latlong.dart';

import 'api/api_client.dart' show PageResult;

double toMoney(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
double? toMoneyOrNull(dynamic v) => v == null ? null : toMoney(v);
DateTime toDate(dynamic v) => DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);

/// Bilingual text picked by language code.
String pick(String lang, String? ar, String? en) {
  final a = ar ?? '', e = en ?? '';
  if (lang == 'en') return e.isNotEmpty ? e : a;
  return a.isNotEmpty ? a : e;
}

class Category {
  Category.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        slug = j['slug'] as String? ?? '',
        nameAr = j['name_ar'] as String? ?? '',
        nameEn = j['name_en'] as String? ?? '',
        descriptionAr = j['description_ar'] as String? ?? '',
        descriptionEn = j['description_en'] as String? ?? '',
        image = j['image'] as String?,
        sortOrder = j['sort_order'] as int? ?? 0,
        isActive = j['is_active'] as bool? ?? true,
        productCount = j['product_count'] as int?;

  final int id;
  final String slug, nameAr, nameEn, descriptionAr, descriptionEn;
  final String? image;
  final int sortOrder;
  final bool isActive;
  final int? productCount;

  String name(String lang) => pick(lang, nameAr, nameEn);
  String description(String lang) => pick(lang, descriptionAr, descriptionEn);
}

class ProductSummary {
  ProductSummary.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        slug = j['slug'] as String? ?? '',
        nameAr = j['name_ar'] as String? ?? '',
        nameEn = j['name_en'] as String? ?? '',
        shortAr = j['short_description_ar'] as String? ?? '',
        shortEn = j['short_description_en'] as String? ?? '',
        categoryId = j['category_id'] as int?,
        thumbnail = j['thumbnail'] as String?,
        price = toMoneyOrNull(j['price']),
        discountPrice = toMoneyOrNull(j['discount_price']),
        inStock = j['in_stock'] as bool? ?? false,
        isFeatured = j['is_featured'] as bool? ?? false;

  final int id;
  final String slug, nameAr, nameEn, shortAr, shortEn;
  final int? categoryId;
  final String? thumbnail;
  final double? price, discountPrice;
  final bool inStock, isFeatured;

  String name(String lang) => pick(lang, nameAr, nameEn);
  String short(String lang) => pick(lang, shortAr, shortEn);
  bool get onSale => discountPrice != null && price != null && discountPrice! < price!;
  double? get effectivePrice => onSale ? discountPrice : price;
  int get discountPercent => onSale ? (((price! - discountPrice!) / price!) * 100).round() : 0;
}

class Variant {
  Variant.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int?,
        labelAr = j['label_ar'] as String? ?? '',
        labelEn = j['label_en'] as String? ?? '',
        unit = j['unit'] as String? ?? 'kg',
        unitQuantity = toMoney(j['unit_quantity'] ?? 1),
        sku = j['sku'] as String? ?? '',
        price = toMoney(j['price']),
        discountPrice = toMoneyOrNull(j['discount_price']),
        priceSyp = toMoneyOrNull(j['price_syp']),
        discountPriceSyp = toMoneyOrNull(j['discount_price_syp']),
        stock = j['stock'] as int? ?? 0,
        minOrderQty = j['min_order_qty'] as int? ?? 1,
        isActive = j['is_active'] as bool? ?? true,
        sortOrder = j['sort_order'] as int? ?? 0;

  Variant({
    this.id,
    required this.labelAr,
    required this.labelEn,
    this.unit = 'kg',
    this.unitQuantity = 1,
    this.sku = '',
    required this.price,
    this.discountPrice,
    this.priceSyp,
    this.discountPriceSyp,
    this.stock = 0,
    this.minOrderQty = 1,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final int? id;
  final String labelAr, labelEn, unit, sku;
  final double unitQuantity, price;
  final double? discountPrice;
  /// Admin app only: what customers pay now in Syrian pounds (price is USD there).
  final double? priceSyp, discountPriceSyp;
  final int stock, minOrderQty, sortOrder;
  final bool isActive;

  String label(String lang) => pick(lang, labelAr, labelEn);
  bool get onSale => discountPrice != null && discountPrice! < price;
  double get effectivePrice => onSale ? discountPrice! : price;
  bool get inStock => stock >= minOrderQty;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'label_ar': labelAr,
        'label_en': labelEn,
        'unit': unit,
        'unit_quantity': unitQuantity.toStringAsFixed(3),
        'sku': sku,
        'price': price.toStringAsFixed(2),
        'discount_price': discountPrice?.toStringAsFixed(2),
        'stock': stock,
        'min_order_qty': minOrderQty,
        'is_active': isActive,
        'sort_order': sortOrder,
      };
}

class ProductImage {
  ProductImage.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        url = j['url'] as String? ?? '',
        thumbnail = j['thumbnail'] as String? ?? j['url'] as String? ?? '';

  final int id;
  final String url, thumbnail;
}

class Spec {
  Spec.fromJson(Map<String, dynamic> j)
      : labelAr = j['label_ar'] as String? ?? '',
        labelEn = j['label_en'] as String? ?? '',
        valueAr = j['value_ar'] as String? ?? '',
        valueEn = j['value_en'] as String? ?? '';

  final String labelAr, labelEn, valueAr, valueEn;
  String label(String lang) => pick(lang, labelAr, labelEn);
  String value(String lang) => pick(lang, valueAr, valueEn);
}

class ProductDetail extends ProductSummary {
  ProductDetail.fromJson(super.j)
      : descriptionAr = j['description_ar'] as String? ?? '',
        descriptionEn = j['description_en'] as String? ?? '',
        images = (j['images'] as List? ?? []).map((e) => ProductImage.fromJson(e as Map<String, dynamic>)).toList(),
        variants = (j['variants'] as List? ?? []).map((e) => Variant.fromJson(e as Map<String, dynamic>)).toList(),
        specs = (j['specifications'] as List? ?? []).map((e) => Spec.fromJson(e as Map<String, dynamic>)).toList(),
        category = j['category'] is Map ? Category.fromJson(j['category'] as Map<String, dynamic>) : null,
        super.fromJson();

  final String descriptionAr, descriptionEn;
  final List<ProductImage> images;
  final List<Variant> variants;
  final List<Spec> specs;
  final Category? category;

  String description(String lang) => pick(lang, descriptionAr, descriptionEn);
}

class BannerItem {
  BannerItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        image = j['image'] as String? ?? '',
        titleAr = j['title_ar'] as String? ?? '',
        titleEn = j['title_en'] as String? ?? '',
        subtitleAr = j['subtitle_ar'] as String? ?? '',
        subtitleEn = j['subtitle_en'] as String? ?? '',
        linkType = j['link_type'] as String? ?? 'none',
        linkValue = j['link_value'] as String? ?? '',
        sortOrder = j['sort_order'] as int? ?? 0,
        isActive = j['is_active'] as bool? ?? true,
        startsAt = j['starts_at'] == null ? null : toDate(j['starts_at']),
        endsAt = j['ends_at'] == null ? null : toDate(j['ends_at']);

  final int id;
  final String image, titleAr, titleEn, subtitleAr, subtitleEn, linkType, linkValue;
  final int sortOrder;
  final bool isActive;
  final DateTime? startsAt, endsAt;

  String title(String lang) => pick(lang, titleAr, titleEn);
  String subtitle(String lang) => pick(lang, subtitleAr, subtitleEn);
}

class AppUser {
  AppUser.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        email = j['email'] as String? ?? '',
        fullName = j['full_name'] as String? ?? '',
        phone = j['phone'] as String? ?? '',
        businessName = j['business_name'] as String? ?? '',
        businessType = j['business_type'] as String? ?? '',
        deliveryAreaId = j['delivery_area'] as int?,
        areaName = j['area_name'] as String? ?? '',
        address = j['address'] as String? ?? '',
        interests = (j['interests'] as List? ?? []).whereType<int>().toList(),
        language = j['language'] as String? ?? 'ar',
        isStaff = j['is_staff'] as bool? ?? false,
        hasPassword = j['has_password'] as bool? ?? true,
        profileComplete = j['profile_complete'] as bool? ?? true,
        phoneVerified = j['phone_verified'] as bool? ?? false,
        creditEnabled = j['credit_enabled'] as bool? ?? false,
        showStatement = j['show_statement'] as bool? ?? true,
        isOwner = j['is_owner'] as bool? ?? false,
        isDistributor = j['is_distributor'] as bool? ?? false,
        isDriver = j['is_driver'] as bool? ?? false,
        distributorName = j['distributor_name'] as String?,
        ownDistributorCode = j['own_distributor_code'] as String?;

  final int id;

  /// Partner account in the admin app: sees only its own customers. [ownDistributorCode] is the code it
  /// gives customers. For a customer, [distributorName] is the distributor they buy through.
  final bool isDistributor;
  final String? distributorName, ownDistributorCode;

  /// Delivery account in the admin app: sees only the orders handed to it.
  final bool isDriver;
  final String email, fullName, phone, businessName, businessType, areaName, address, language;
  final int? deliveryAreaId;
  final List<int> interests;
  final bool isStaff, hasPassword, profileComplete, phoneVerified, creditEnabled;

  /// The account statement is hidden until the store enables credit (or something is owed).
  final bool showStatement;

  /// Store owner in the admin app (employees, settings, corrections, cash report).
  final bool isOwner;

  /// Name shown to staff on orders and payments.
  String get displayName => fullName.isNotEmpty ? fullName : (phone.isNotEmpty ? phone : email);
}

/// Business types customers choose at sign-up (labels in l10n: 'biz.<code>').
const businessTypes = ['cafe', 'restaurant', 'cafeteria', 'bakery', 'sweets', 'factory', 'ice_cream', 'hotel', 'market', 'other'];

class DeliveryArea {
  DeliveryArea.fromJson(Map<String, dynamic> j, [this.zone])
      : id = j['id'] as int?,
        nameAr = j['name_ar'] as String? ?? '',
        nameEn = j['name_en'] as String? ?? '',
        sortOrder = j['sort_order'] as int? ?? 0,
        isActive = j['is_active'] as bool? ?? true;

  DeliveryArea({this.id, required this.nameAr, this.nameEn = '', this.sortOrder = 0, this.isActive = true, this.zone});

  final int? id;
  final String nameAr, nameEn;
  final int sortOrder;
  final bool isActive;
  final DeliveryZone? zone;

  String name(String lang) => pick(lang, nameAr, nameEn);
  Map<String, dynamic> toJson() => {if (id != null) 'id': id, 'name_ar': nameAr, 'name_en': nameEn, 'sort_order': sortOrder, 'is_active': isActive};
}

class DeliveryZone {
  DeliveryZone.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        nameAr = j['name_ar'] as String? ?? '',
        nameEn = j['name_en'] as String? ?? '',
        fee = toMoney(j['fee']),
        isDefaultForUnlisted = j['is_default_for_unlisted'] as bool? ?? false,
        sortOrder = j['sort_order'] as int? ?? 0,
        isActive = j['is_active'] as bool? ?? true {
    areas = (j['areas'] as List? ?? []).map((e) => DeliveryArea.fromJson(e as Map<String, dynamic>, this)).toList();
  }

  final int id;
  final String nameAr, nameEn;
  final double fee;
  final bool isDefaultForUnlisted, isActive;
  final int sortOrder;
  late final List<DeliveryArea> areas;

  String name(String lang) => pick(lang, nameAr, nameEn);
}

class DeliveryInfo {
  DeliveryInfo.fromJson(Map<String, dynamic> j)
      : pickupEnabled = j['pickup_enabled'] as bool? ?? true,
        pickupAddressAr = j['pickup_address_ar'] as String? ?? '',
        pickupAddressEn = j['pickup_address_en'] as String? ?? '',
        deliveryEnabled = j['delivery_enabled'] as bool? ?? true,
        currencyAr = j['currency_ar'] as String? ?? 'ل.س',
        currencyEn = j['currency_en'] as String? ?? 'SYP',
        appDiscountPercent = toMoney(j['app_discount_percent']),
        zones = (j['zones'] as List? ?? []).map((e) => DeliveryZone.fromJson(e as Map<String, dynamic>)).toList();

  final bool pickupEnabled, deliveryEnabled;
  final String pickupAddressAr, pickupAddressEn, currencyAr, currencyEn;
  final double appDiscountPercent;
  final List<DeliveryZone> zones;

  List<DeliveryArea> get areas => [for (final z in zones) ...z.areas];
  DeliveryArea? area(int? id) => id == null ? null : areas.where((a) => a.id == id).firstOrNull;
  String currency(String lang) => pick(lang, currencyAr, currencyEn);
  String pickupAddress(String lang) => pick(lang, pickupAddressAr, pickupAddressEn);

  DeliveryZone? get unlistedZone {
    final marked = zones.where((z) => z.isDefaultForUnlisted).firstOrNull;
    if (marked != null || zones.isEmpty) return marked;
    return (zones.toList()..sort((a, b) => b.fee.compareTo(a.fee))).first;
  }
}

class Address {
  Address.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int?,
        label = j['label'] as String? ?? '',
        recipientName = j['recipient_name'] as String? ?? '',
        phone = j['phone'] as String? ?? '',
        city = j['city'] as String? ?? '',
        deliveryAreaId = j['delivery_area'] as int?,
        area = j['area'] as String? ?? '',
        street = j['street'] as String? ?? '',
        details = j['details'] as String? ?? '',
        latitude = toMoneyOrNull(j['latitude']),
        longitude = toMoneyOrNull(j['longitude']),
        isDefault = j['is_default'] as bool? ?? false;

  Address({
    this.id,
    this.label = '',
    required this.recipientName,
    required this.phone,
    this.city = 'دمشق',
    this.deliveryAreaId,
    this.area = '',
    this.street = '',
    this.details = '',
    this.latitude,
    this.longitude,
    this.isDefault = false,
  });

  final int? id, deliveryAreaId;
  final String label, recipientName, phone, city, area, street, details;
  final bool isDefault;

  /// Map pin (both set or both null).
  final double? latitude, longitude;

  LatLng? get pin => latitude != null && longitude != null ? LatLng(latitude!, longitude!) : null;

  String get oneLine => [area, street, details].where((s) => s.trim().isNotEmpty).join('، ');

  Map<String, dynamic> toJson() => {
        'label': label,
        'recipient_name': recipientName,
        'phone': phone,
        'city': city,
        'delivery_area': deliveryAreaId,
        'area': area,
        'street': street,
        'details': details,
        'latitude': latitude?.toStringAsFixed(6),
        'longitude': longitude?.toStringAsFixed(6),
        'is_default': isDefault,
      };
}

class OrderItem {
  OrderItem.fromJson(Map<String, dynamic> j)
      : productId = j['product_id'] as int?,
        variantId = j['variant_id'] as int?,
        productNameAr = j['product_name_ar'] as String? ?? '',
        productNameEn = j['product_name_en'] as String? ?? '',
        variantLabelAr = j['variant_label_ar'] as String? ?? '',
        variantLabelEn = j['variant_label_en'] as String? ?? '',
        image = j['image'] as String? ?? '',
        unitPrice = toMoney(j['unit_price']),
        quantity = j['quantity'] as int? ?? 0,
        lineTotal = toMoney(j['line_total']);

  final int? productId, variantId;
  final String productNameAr, productNameEn, variantLabelAr, variantLabelEn, image;
  final double unitPrice, lineTotal;
  final int quantity;

  String productName(String lang) => pick(lang, productNameAr, productNameEn);
  String variantLabel(String lang) => pick(lang, variantLabelAr, variantLabelEn);
}

class OrderEvent {
  OrderEvent.fromJson(Map<String, dynamic> j)
      : status = j['status'] as String? ?? '',
        note = j['note'] as String? ?? '',
        byName = j['by_name'] as String?,
        createdAt = toDate(j['created_at']);

  final String status, note;

  /// Staff member who made the change (admin app only).
  final String? byName;
  final DateTime createdAt;
}

/// Cash received for an order and the staff member who took it (admin app only).
class OrderPayment {
  OrderPayment.fromJson(Map<String, dynamic> j)
      : amount = toMoney(j['amount']),
        byName = j['by_name'] as String?,
        note = j['note'] as String? ?? '',
        createdAt = toDate(j['created_at']);

  final double amount;
  final String? byName;
  final String note;
  final DateTime createdAt;
}

const orderStatuses = ['pending', 'confirmed', 'shipped', 'delivered', 'cancelled'];

class OrderSummary {
  OrderSummary.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        number = j['number'] as String? ?? '',
        status = j['status'] as String? ?? 'pending',
        deliveryMethod = j['delivery_method'] as String? ?? 'delivery',
        total = toMoney(j['total']),
        totalUsd = toMoneyOrNull(j['total_usd']),
        itemCount = j['item_count'] as int? ?? 0,
        customerName = j['customer_name'] as String? ?? '',
        businessName = j['business_name'] as String? ?? '',
        customerPhone = j['customer_phone'] as String? ?? '',
        city = j['city'] as String? ?? '',
        distributorName = j['distributor_name'] as String?,
        createdAt = toDate(j['created_at']);

  final int id;

  /// Admin app: the distributor whose customer placed it (null = the store's own customer).
  final String? distributorName;
  final String number, status, deliveryMethod, customerName, businessName, customerPhone, city;
  final double total;
  /// Admin app only (never sent to customers).
  final double? totalUsd;
  final int itemCount;
  final DateTime createdAt;

  bool get isPickup => deliveryMethod == 'pickup';
}

/// The driver's position while an order is out for delivery.
class Tracking {
  Tracking.fromJson(Map<String, dynamic> j)
      : position = toPoint(j['latitude'], j['longitude'])!,
        updatedAt = toDate(j['updated_at']),
        distanceKm = toMoneyOrNull(j['distance_km']),
        etaMinutes = j['eta_minutes'] as int?;

  final LatLng position;
  final DateTime? updatedAt;
  final double? distanceKm;
  final int? etaMinutes;
}

LatLng? toPoint(Object? lat, Object? lng) {
  final a = toMoneyOrNull(lat), b = toMoneyOrNull(lng);
  return a == null || b == null ? null : LatLng(a, b);
}

class OrderDetail {
  OrderDetail.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        number = j['number'] as String? ?? '',
        status = j['status'] as String? ?? 'pending',
        customerName = j['customer_name'] as String? ?? '',
        customerPhone = j['customer_phone'] as String? ?? '',
        customerEmail = j['customer_email'] as String? ?? '',
        businessName = j['business_name'] as String? ?? '',
        city = j['city'] as String? ?? '',
        area = j['area'] as String? ?? '',
        street = j['street'] as String? ?? '',
        addressDetails = j['address_details'] as String? ?? '',
        notes = j['notes'] as String? ?? '',
        adminNote = j['admin_note'] as String? ?? '',
        couponCode = j['coupon_code'] as String? ?? '',
        deliveryMethod = j['delivery_method'] as String? ?? 'delivery',
        deliveryZone = j['delivery_zone'] as String? ?? '',
        deliveryFee = toMoney(j['delivery_fee']),
        deliveryCurrency = j['delivery_currency'] as String? ?? '',
        appDiscountPercent = toMoney(j['app_discount_percent']),
        appDiscount = toMoney(j['app_discount']),
        subtotal = toMoney(j['subtotal']),
        discount = toMoney(j['discount']),
        total = toMoney(j['total']),
        totalUsd = toMoneyOrNull(j['total_usd']),
        exchangeRate = toMoneyOrNull(j['exchange_rate']),
        items = (j['items'] as List? ?? []).map((e) => OrderItem.fromJson(e as Map<String, dynamic>)).toList(),
        events = (j['events'] as List? ?? []).map((e) => OrderEvent.fromJson(e as Map<String, dynamic>)).toList(),
        payments = (j['payments'] as List? ?? []).map((e) => OrderPayment.fromJson(e as Map<String, dynamic>)).toList(),
        canCancel = j['can_cancel'] as bool? ?? false,
        paidAmount = toMoney(j['paid_amount']),
        remaining = j['remaining'] == null ? null : toMoney(j['remaining']),
        creditApplied = toMoney(j['credit_applied']),
        toCollect = j['to_collect'] == null ? null : toMoney(j['to_collect']),
        userId = j['user_id'] as int?,
        customerDeleted = j['customer_deleted'] as bool? ?? false,
        allowedStatuses = (j['allowed_statuses'] as List? ?? []).cast<String>(),
        pin = toPoint(j['latitude'], j['longitude']),
        tracking = j['tracking'] == null ? null : Tracking.fromJson(j['tracking'] as Map<String, dynamic>),
        driverId = j['driver_id'] as int?,
        driverName = j['driver_name'] as String?,
        distributorName = j['distributor_name'] as String?,
        route = [
          for (final p in (j['route'] as List? ?? []))
            if (p is List && p.length == 2) ?toPoint(p[0], p[1]),
        ],
        lastSeenAt = j['last_seen_at'] == null ? null : toDate(j['last_seen_at']),
        createdAt = toDate(j['created_at']);

  final int id;

  /// The customer's map pin, the driver's live position (while shipped) and who is delivering (admin only).
  final LatLng? pin;
  final Tracking? tracking;
  final int? driverId;
  final String? driverName, distributorName;

  /// Admin app: the road the driver took (kept after delivery) and when their phone last reported.
  final List<LatLng> route;
  final DateTime? lastSeenAt;
  final String number, status, customerName, customerPhone, customerEmail, businessName;
  final String city, area, street, addressDetails, notes, adminNote, couponCode;
  final String deliveryMethod, deliveryZone, deliveryCurrency;
  final double subtotal, discount, total, deliveryFee, appDiscount, appDiscountPercent;

  /// Admin app only: the dollar rate the order was priced with and its total in USD.
  final double? totalUsd, exchangeRate;

  /// Payments recorded against this order; [remaining] is set once the order is delivered.
  final double paidAmount;
  final double? remaining;

  /// Paid from the customer's credit with the store (estimate until delivered).
  final double creditApplied;

  /// Cash to take on delivery (still owed once delivered); null when cancelled.
  final double? toCollect;
  bool get isPickup => deliveryMethod == 'pickup';
  final List<OrderItem> items;
  final List<OrderEvent> events;
  final List<OrderPayment> payments;
  final bool canCancel, customerDeleted;
  final int? userId;
  final List<String> allowedStatuses;
  final DateTime createdAt;

  String get address => [area, street, addressDetails].where((s) => s.trim().isNotEmpty).join('، ');
}

class AppNotification {
  AppNotification.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        kind = j['kind'] as String? ?? 'general',
        titleAr = j['title_ar'] as String? ?? '',
        titleEn = j['title_en'] as String? ?? '',
        bodyAr = j['body_ar'] as String? ?? '',
        bodyEn = j['body_en'] as String? ?? '',
        data = Map<String, dynamic>.from(j['data'] as Map? ?? {}),
        audience = Map<String, dynamic>.from(j['audience'] as Map? ?? {}),
        sentCount = j['sent_count'] as int? ?? 0,
        createdAt = toDate(j['created_at']);

  final int id, sentCount;
  final String kind, titleAr, titleEn, bodyAr, bodyEn;
  final Map<String, dynamic> data, audience;
  final DateTime createdAt;

  String title(String lang) => pick(lang, titleAr, titleEn);
  String body(String lang) => pick(lang, bodyAr, bodyEn);
}

class StoreInfo {
  StoreInfo.fromJson(Map<String, dynamic> j)
      : raw = j,
        nameAr = j['name_ar'] as String? ?? '',
        nameEn = j['name_en'] as String? ?? '',
        aboutAr = j['about_ar'] as String? ?? '',
        aboutEn = j['about_en'] as String? ?? '',
        phone = j['phone'] as String? ?? '',
        mobile = j['mobile'] as String? ?? '',
        whatsapp = j['whatsapp'] as String? ?? '',
        email = j['email'] as String? ?? '',
        website = j['website'] as String? ?? '',
        addressAr = j['address_ar'] as String? ?? '',
        addressEn = j['address_en'] as String? ?? '',
        hoursAr = j['working_hours_ar'] as String? ?? '',
        hoursEn = j['working_hours_en'] as String? ?? '',
        facebook = j['facebook'] as String? ?? '',
        instagram = j['instagram'] as String? ?? '',
        telegram = j['telegram'] as String? ?? '',
        ordersEnabled = j['orders_enabled'] as bool? ?? true,
        minOrderTotal = toMoney(j['min_order_total']),
        lowStockThreshold = j['low_stock_threshold'] as int? ?? 10;

  final Map<String, dynamic> raw;
  final String nameAr, nameEn, aboutAr, aboutEn, phone, mobile, whatsapp, email, website;
  final String addressAr, addressEn, hoursAr, hoursEn, facebook, instagram, telegram;
  final bool ordersEnabled;
  final double minOrderTotal;
  final int lowStockThreshold;

  String name(String lang) => pick(lang, nameAr, nameEn);
  String about(String lang) => pick(lang, aboutAr, aboutEn);
  String address(String lang) => pick(lang, addressAr, addressEn);
  String hours(String lang) => pick(lang, hoursAr, hoursEn);
}

class LegalPage {
  LegalPage.fromJson(Map<String, dynamic> j)
      : slug = j['slug'] as String? ?? '',
        titleAr = j['title_ar'] as String? ?? '',
        titleEn = j['title_en'] as String? ?? '',
        bodyAr = j['body_ar'] as String? ?? '',
        bodyEn = j['body_en'] as String? ?? '',
        url = j['url'] as String?,
        updatedAt = toDate(j['updated_at']);

  final String slug, titleAr, titleEn, bodyAr, bodyEn;
  final String? url;
  final DateTime updatedAt;

  String title(String lang) => pick(lang, titleAr, titleEn);
  String body(String lang) => pick(lang, bodyAr, bodyEn);
}

/// One line of the customer's account statement (USD). Positive = added to the debt.
class LedgerEntry {
  LedgerEntry.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        kind = j['kind'] as String? ?? 'adjustment',
        amount = toMoney(j['amount']),
        balanceAfter = toMoney(j['balance_after']),
        note = j['note'] as String? ?? '',
        orderId = j['order_id'] as int?,
        orderNumber = j['order_number'] as String?,
        createdBy = j['created_by'] as String?,
        createdAt = toDate(j['created_at']);

  final int id;
  final String kind, note;
  final double amount, balanceAfter;
  final int? orderId;
  final String? orderNumber, createdBy;
  final DateTime createdAt;
}

class AccountSummary {
  AccountSummary.fromJson(Map<String, dynamic> j)
      : balance = toMoney(j['balance']),
        openOrders = toMoney(j['open_orders']),
        creditLimit = j['credit_limit'] == null ? null : toMoney(j['credit_limit']),
        available = j['available'] == null ? null : toMoney(j['available']),
        creditEnabled = j['credit_enabled'] as bool? ?? true;

  /// Positive = the customer owes the store; negative = the customer has credit.
  final double balance, openOrders;
  final double? creditLimit, available;

  /// Buying on credit is off until the store turns it on for this customer.
  final bool creditEnabled;
}

class Statement {
  Statement.fromJson(Map<String, dynamic> j)
      : summary = AccountSummary.fromJson(j['summary'] as Map<String, dynamic>? ?? const {}),
        entries = PageResult.fromJson(j, LedgerEntry.fromJson);

  final AccountSummary summary;
  final PageResult<LedgerEntry> entries;
}
