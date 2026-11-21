import 'package:alas_shared/alas_shared.dart';
import 'package:dio/dio.dart';

/// Admin product (all fields editable, including hidden products and variants).
class AdminProduct {
  AdminProduct.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int?,
        categoryId = j['category'] as int?,
        categoryNameAr = j['category_name_ar'] as String? ?? '',
        categoryNameEn = j['category_name_en'] as String? ?? '',
        nameAr = j['name_ar'] as String? ?? '',
        nameEn = j['name_en'] as String? ?? '',
        shortAr = j['short_description_ar'] as String? ?? '',
        shortEn = j['short_description_en'] as String? ?? '',
        descriptionAr = j['description_ar'] as String? ?? '',
        descriptionEn = j['description_en'] as String? ?? '',
        keywords = j['keywords'] as String? ?? '',
        isFeatured = j['is_featured'] as bool? ?? false,
        isActive = j['is_active'] as bool? ?? true,
        soldCount = j['sold_count'] as int? ?? 0,
        totalStock = j['total_stock'] as int? ?? 0,
        variants = (j['variants'] as List? ?? []).map((e) => Variant.fromJson(e as Map<String, dynamic>)).toList(),
        images = (j['images'] as List? ?? []).map((e) => ProductImage.fromJson(e as Map<String, dynamic>)).toList(),
        specifications = (j['specifications'] as List? ?? []).cast<Map<String, dynamic>>();

  final int? id, categoryId;
  final String categoryNameAr, categoryNameEn, nameAr, nameEn, shortAr, shortEn, descriptionAr, descriptionEn, keywords;
  final bool isFeatured, isActive;
  final int soldCount, totalStock;
  final List<Variant> variants;
  final List<ProductImage> images;
  final List<Map<String, dynamic>> specifications;

  String name(String lang) => pick(lang, nameAr, nameEn);
  String categoryName(String lang) => pick(lang, categoryNameAr, categoryNameEn);
  String? get thumbnail => images.isEmpty ? null : images.first.thumbnail;
}

class AdminCustomer {
  AdminCustomer.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        email = j['email'] as String? ?? '',
        fullName = j['full_name'] as String? ?? '',
        phone = j['phone'] as String? ?? '',
        businessName = j['business_name'] as String? ?? '',
        businessType = j['business_type'] as String? ?? '',
        areaName = j['area_name'] as String? ?? '',
        address = j['address'] as String? ?? '',
        interests = (j['interests'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        isActive = j['is_active'] as bool? ?? true,
        orderCount = j['order_count'] as int? ?? 0,
        totalSpent = toMoney(j['total_spent']),
        balance = toMoney(j['balance']),
        creditLimit = j['credit_limit'] == null ? null : toMoney(j['credit_limit']),
        creditEnabled = j['credit_enabled'] as bool? ?? false,
        phoneVerified = j['phone_verified'] as bool? ?? false,
        distributorId = j['distributor'] as int?,
        distributorName = j['distributor_name'] as String?,
        dateJoined = toDate(j['date_joined']),
        lastOrderAt = j['last_order_at'] == null ? null : toDate(j['last_order_at']);

  final int id, orderCount;

  /// The distributor this customer buys through (null = the store's own customer).
  final int? distributorId;
  final String? distributorName;
  final String email, fullName, phone, businessName, businessType, areaName, address;
  final List<Map<String, dynamic>> interests;
  final bool isActive, phoneVerified;
  final double totalSpent;

  /// Buying on credit (and seeing the debt / limit in the app) is off until an admin turns it on.
  final bool creditEnabled;

  /// What the customer owes (negative = credit) and their own credit limit (null = store default).
  final double balance;
  final double? creditLimit;
  final DateTime dateJoined;
  final DateTime? lastOrderAt;
}

class Coupon {
  Coupon.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int?,
        code = j['code'] as String? ?? '',
        kind = j['kind'] as String? ?? 'percent',
        value = toMoney(j['value']),
        minOrderTotal = toMoney(j['min_order_total']),
        maxDiscount = toMoneyOrNull(j['max_discount']),
        maxUses = j['max_uses'] as int?,
        maxUsesPerUser = j['max_uses_per_user'] as int?,
        usedCount = j['used_count'] as int? ?? 0,
        startsAt = j['starts_at'] == null ? null : toDate(j['starts_at']),
        expiresAt = j['expires_at'] == null ? null : toDate(j['expires_at']),
        isActive = j['is_active'] as bool? ?? true;

  final int? id, maxUses, maxUsesPerUser;
  final String code, kind;
  final double value, minOrderTotal;
  final double? maxDiscount;
  final int usedCount;
  final DateTime? startsAt, expiresAt;
  final bool isActive;

  bool get expired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
}

/// The dollar rate used to turn USD product prices into the Syrian-pound prices customers see.
class RateStatus {
  RateStatus.fromJson(Map<String, dynamic> j)
      : rate = toMoneyOrNull(j['rate']),
        mode = j['mode'] as String? ?? 'auto',
        side = j['side'] as String? ?? 'sell',
        manual = toMoneyOrNull(j['manual']),
        rounding = j['rounding'] as int? ?? 10,
        autoBuy = toMoneyOrNull(j['auto_buy']),
        autoSell = toMoneyOrNull(j['auto_sell']),
        fetchedAt = j['fetched_at'] == null ? null : DateTime.tryParse(j['fetched_at'] as String)?.toLocal(),
        stale = j['stale'] as bool? ?? false,
        error = j['error'] as String? ?? '',
        held = j['held'] == null ? null : Map<String, dynamic>.from(j['held'] as Map);

  final double? rate, manual, autoBuy, autoSell;
  final String mode, side, error;
  final int rounding;
  final DateTime? fetchedAt;
  final bool stale;
  final Map<String, dynamic>? held;

  /// Last status seen anywhere in the app (the product form uses it for its live preview).
  static RateStatus? last;

  /// Customer price in Syrian pounds for a dollar price, the same way the server rounds it.
  double? toSyp(double? usdPrice) {
    if (usdPrice == null || rate == null) return null;
    final step = rounding < 1 ? 1 : rounding;
    return ((usdPrice * rate!) / step).round() * step.toDouble();
  }
}

class Dashboard {
  Dashboard.fromJson(Map<String, dynamic> j)
      : todaySales = toMoney(j['today']['sales']),
        todaySalesUsd = toMoney(j['today']['sales_usd']),
        monthSalesUsd = toMoney(j['month']['sales_usd']),
        rate = j['exchange_rate'] == null ? null : RateStatus.fromJson(Map<String, dynamic>.from(j['exchange_rate'] as Map)),
        todayOrders = j['today']['orders'] as int,
        monthSales = toMoney(j['month']['sales']),
        monthOrders = j['month']['orders'] as int,
        pendingOrders = j['pending_orders'] as int,
        customers = j['customers'] as int,
        products = j['products'] as int,
        chart = (j['chart'] as List).map((e) => (date: DateTime.parse(e['date'] as String), sales: toMoney(e['sales']), orders: e['orders'] as int)).toList(),
        bestSellers = (j['best_sellers'] as List).cast<Map<String, dynamic>>(),
        lowStock = (j['low_stock'] as List).cast<Map<String, dynamic>>(),
        lowStockThreshold = j['low_stock_threshold'] as int? ?? 10,
        receivablesTotal = toMoney(j['receivables_total']),
        unreadInbox = j['unread_inbox'] as int? ?? 0;

  final double todaySales, monthSales, receivablesTotal, todaySalesUsd, monthSalesUsd;
  final RateStatus? rate;
  final int todayOrders, monthOrders, pendingOrders, customers, products, lowStockThreshold, unreadInbox;
  final List<({DateTime date, double sales, int orders})> chart;
  final List<Map<String, dynamic>> bestSellers, lowStock;
}

class Report {
  Report.fromJson(Map<String, dynamic> j)
      : period = j['period'] as String,
        from = DateTime.parse(j['from'] as String),
        to = DateTime.parse(j['to'] as String),
        series = (j['series'] as List)
            .map((e) => (period: DateTime.parse(e['period'] as String), sales: toMoney(e['sales']), discount: toMoney(e['discount']), orders: e['orders'] as int))
            .toList(),
        totalSales = toMoney(j['totals']['sales']),
        totalSalesUsd = toMoney(j['totals']['sales_usd']),
        totalOrders = j['totals']['orders'] as int,
        totalDiscount = toMoney(j['totals']['discount']),
        averageOrder = toMoney(j['totals']['average_order']),
        topProducts = (j['top_products'] as List).cast<Map<String, dynamic>>();

  final String period;
  final DateTime from, to;
  final List<({DateTime period, double sales, double discount, int orders})> series;
  final double totalSales, totalSalesUsd, totalDiscount, averageOrder;
  final int totalOrders;
  final List<Map<String, dynamic>> topProducts;
}

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) => (v as List? ?? []).map((e) => f(e as Map<String, dynamic>)).toList();

/// All admin endpoints (/api/v1/admin/...). The server rejects every call from non-staff accounts.
class AdminApi {
  AdminApi(this.client);

  final ApiClient client;

  Future<Dashboard> dashboard() async {
    final d = Dashboard.fromJson(await client.get('/admin/dashboard/'));
    if (d.rate != null) RateStatus.last = d.rate;
    return d;
  }

  // Orders
  Future<PageResult<OrderSummary>> orders({int page = 1, String? status, String? q, int? customer}) async => PageResult.fromJson(
        await client.get('/admin/orders/', query: {
          'page': page,
          if (status != null) 'status': status,
          if (q != null && q.isNotEmpty) 'q': q,
          if (customer != null) 'customer': customer,
        }),
        OrderSummary.fromJson,
      );
  Future<OrderDetail> order(int id) async => OrderDetail.fromJson(await client.get('/admin/orders/$id/'));
  Future<List<int>> invoicePdf(int id, String lang) => client.getBytes('/admin/orders/$id/invoice/', query: {'lang': lang});
  Future<OrderDetail> setStatus(int id, String status, {String note = '', double? paidAmount, int? driverId}) async => OrderDetail.fromJson(
      await client.post('/admin/orders/$id/status/', data: {
        'status': status,
        'note': note,
        if (paidAmount != null) 'paid_amount': paidAmount.toStringAsFixed(2),
        if (driverId != null) 'driver_id': driverId,
      }));

  /// Orders out for delivery right now with each driver's last position (this account's side only).
  Future<List<Map<String, dynamic>>> liveDeliveries() async =>
      ((await client.get('/admin/orders/live/')) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  /// Who an order can be handed to for delivery: [{id, name, is_driver, is_me}].
  Future<List<Map<String, dynamic>>> orderDrivers(int id) async =>
      ((await client.get('/admin/orders/$id/drivers/')) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  /// Hand an order that is out for delivery to another driver.
  Future<OrderDetail> assignDriver(int id, int driverId) async =>
      OrderDetail.fromJson(await client.post('/admin/orders/$id/assign-driver/', data: {'driver_id': driverId}));

  /// Delivery accounts (owner: all; distributor: their own).
  Future<List<Map<String, dynamic>>> drivers() async =>
      ((await client.get('/admin/drivers/')) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Future<void> addDriver(Map<String, dynamic> data) => client.post('/admin/drivers/', data: data);
  Future<void> updateDriver(int id, Map<String, dynamic> data) => client.patch('/admin/drivers/$id/', data: data);
  Future<OrderDetail> recordOrderPayment(int id, double amount, String note) async => OrderDetail.fromJson(
      await client.post('/admin/orders/$id/payment/', data: {'amount': amount.toStringAsFixed(2), 'note': note}));
  /// This employee delivers the order from now on.
  Future<OrderDetail> takeDelivery(int id) async => OrderDetail.fromJson(await client.post('/admin/orders/$id/take-delivery/'));

  /// Sends the driver's position; false means stop (delivered, cancelled or taken over).
  /// Sends the driver's recorded points ({latitude, longitude, at}); false means stop.
  Future<bool> reportLocation(int id, List<Map<String, dynamic>> points) async {
    final r = await client.post<Map<String, dynamic>>('/admin/orders/$id/location/',
        data: {'points': points, 'sent_at': DateTime.now().toUtc().toIso8601String()});
    return r['tracking'] == true;
  }

  Future<OrderDetail> setNote(int id, String note) async => OrderDetail.fromJson(await client.patch('/admin/orders/$id/note/', data: {'admin_note': note}));
  Future<List<int>> exportOrders({String? status}) => client.getBytes('/admin/orders/export/', query: {'format': 'xlsx', 'lang': moneyLang, if (status != null) 'status': status});

  // Products
  Future<PageResult<AdminProduct>> products({int page = 1, String? q, int? category, bool lowStock = false, bool? active}) async => PageResult.fromJson(
        await client.get('/admin/products/', query: {
          'page': page,
          if (q != null && q.isNotEmpty) 'q': q,
          if (category != null) 'category': category,
          if (lowStock) 'low_stock': 1,
          if (active != null) 'active': active ? 1 : 0,
        }),
        AdminProduct.fromJson,
      );
  Future<AdminProduct> product(int id) async => AdminProduct.fromJson(await client.get('/admin/products/$id/'));
  Future<AdminProduct> saveProduct(int? id, Map<String, dynamic> data) async => AdminProduct.fromJson(
      id == null ? await client.post('/admin/products/', data: data) : await client.patch('/admin/products/$id/', data: data));
  Future<void> deleteProduct(int id) => client.delete('/admin/products/$id/');
  Future<void> uploadProductImages(int id, List<String> paths) async {
    final form = FormData.fromMap({'images': [for (final p in paths) await MultipartFile.fromFile(p)]});
    await client.post('/admin/products/$id/images/', data: form);
  }
  Future<void> deleteProductImage(int productId, int imageId) => client.delete('/admin/products/$productId/images/$imageId/');
  Future<void> reorderImages(int productId, List<int> ids) => client.post('/admin/products/$productId/images/reorder/', data: {'ids': ids});

  // Categories
  Future<List<Category>> categories() async => _list(await client.get('/admin/categories/'), Category.fromJson);
  Future<Category> saveCategory(int? id, Map<String, dynamic> data) async =>
      Category.fromJson(id == null ? await client.post('/admin/categories/', data: data) : await client.patch('/admin/categories/$id/', data: data));
  Future<void> deleteCategory(int id) => client.delete('/admin/categories/$id/');
  Future<void> uploadCategoryImage(int id, String path) =>
      client.post('/admin/categories/$id/image/', data: FormData.fromMap({'image': MultipartFile.fromFileSync(path)}));

  // Customers
  Future<PageResult<AdminCustomer>> customers({int page = 1, String? q, String? businessType, int? interest}) async => PageResult.fromJson(
        await client.get('/admin/customers/', query: {
          'page': page,
          if (q != null && q.isNotEmpty) 'q': q,
          if (businessType != null) 'business_type': businessType,
          if (interest != null) 'interest': interest,
        }),
        AdminCustomer.fromJson,
      );
  Future<AdminCustomer> customer(int id) async => AdminCustomer.fromJson(await client.get('/admin/customers/$id/'));
  /// Adds a customer (a distributor's new customers are always their own). They sign in later with
  /// "Forgot password" in the store app.
  Future<AdminCustomer> addCustomer(Map<String, dynamic> data) async => AdminCustomer.fromJson(await client.post('/admin/customers/', data: data));

  /// Owner only: move a customer to a distributor, or back to the store (null).
  Future<void> setCustomerDistributor(int id, int? distributorId) => client.patch('/admin/customers/$id/', data: {'distributor': distributorId});
  Future<void> setCustomerActive(int id, bool active) => client.patch('/admin/customers/$id/', data: {'is_active': active});
  Future<void> setCreditEnabled(int id, bool on) => client.patch('/admin/customers/$id/', data: {'credit_enabled': on});
  Future<void> setCreditLimit(int id, double? limit) => client.patch('/admin/customers/$id/', data: {'credit_limit': limit?.toStringAsFixed(2)});

  // Customer accounts (receivables)
  Future<Statement> statement(int customerId) async =>
      Statement.fromJson(await client.get('/admin/customers/$customerId/statement/', query: {'page_size': 100}));
  Future<List<int>> statementCsv(int customerId) => client.getBytes('/admin/customers/$customerId/statement/', query: {'format': 'xlsx', 'lang': moneyLang});
  Future<void> recordPayment(int customerId, double amount, String note) =>
      client.post('/admin/customers/$customerId/payments/', data: {'amount': amount.toStringAsFixed(2), 'note': note});
  Future<void> recordAdjustment(int customerId, double amount, String note) =>
      client.post('/admin/customers/$customerId/adjustments/', data: {'amount': amount.toStringAsFixed(2), 'note': note});
  Future<({double total, List<Map<String, dynamic>> rows})> receivables() async {
    final j = await client.get<Map>('/admin/receivables/');
    return (total: toMoney(j['total']), rows: (j['results'] as List).cast<Map<String, dynamic>>());
  }
  Future<List<int>> receivablesCsv() => client.getBytes('/admin/receivables/', query: {'format': 'xlsx', 'lang': moneyLang});

  // Coupons
  Future<PageResult<Coupon>> coupons({int page = 1}) async => PageResult.fromJson(await client.get('/admin/coupons/', query: {'page': page}), Coupon.fromJson);
  Future<void> saveCoupon(int? id, Map<String, dynamic> data) =>
      id == null ? client.post('/admin/coupons/', data: data) : client.patch('/admin/coupons/$id/', data: data);
  Future<void> deleteCoupon(int id) => client.delete('/admin/coupons/$id/');

  // Banners
  Future<List<BannerItem>> banners() async => _list(await client.get('/admin/banners/'), BannerItem.fromJson);
  Future<BannerItem> saveBanner(int? id, Map<String, dynamic> data, {String? imagePath}) async {
    final Map<String, dynamic> json;
    if (id == null) {
      // A banner needs its image on creation: send everything as multipart.
      json = await client.post('/admin/banners/', data: FormData.fromMap({...data, if (imagePath != null) 'image': await MultipartFile.fromFile(imagePath)}));
      return BannerItem.fromJson(json);
    }
    var b = BannerItem.fromJson(await client.patch('/admin/banners/$id/', data: data));
    if (imagePath != null) b = BannerItem.fromJson(await client.post('/admin/banners/$id/image/', data: FormData.fromMap({'image': await MultipartFile.fromFile(imagePath)})));
    return b;
  }
  Future<void> deleteBanner(int id) => client.delete('/admin/banners/$id/');

  // Delivery zones
  Future<List<DeliveryZone>> zones() async => _list(await client.get('/admin/zones/'), DeliveryZone.fromJson);
  Future<void> saveZone(int? id, Map<String, dynamic> data) => id == null ? client.post('/admin/zones/', data: data) : client.patch('/admin/zones/$id/', data: data);
  Future<void> deleteZone(int id) => client.delete('/admin/zones/$id/');

  // Notifications
  Future<PageResult<AppNotification>> campaigns({int page = 1}) async =>
      PageResult.fromJson(await client.get('/admin/notifications/', query: {'page': page}), AppNotification.fromJson);
  Future<int> audienceCount(Map<String, dynamic> target) async => (await client.post<Map>('/admin/notifications/audience/', data: target))['count'] as int;
  Future<void> broadcast(Map<String, dynamic> data) => client.post('/admin/notifications/', data: data);

  // Inbox: alerts pushed to the admin app (new orders, cancellations)
  Future<({PageResult<AppNotification> page, int unread})> inbox({int page = 1}) async {
    final j = await client.get<Map<String, dynamic>>('/admin/inbox/', query: {'page': page});
    return (page: PageResult.fromJson(j, AppNotification.fromJson), unread: j['unread'] as int? ?? 0);
  }

  Future<void> markInboxSeen() => client.post('/admin/inbox/seen/');

  // Settings & policies
  Future<RateStatus> exchangeRate() async =>
      RateStatus.last = RateStatus.fromJson(Map<String, dynamic>.from(await client.get('/admin/exchange-rate/') as Map));
  Future<RateStatus> exchangeRateAction(String action, {int? id}) async => RateStatus.last = RateStatus.fromJson(
      Map<String, dynamic>.from(await client.post('/admin/exchange-rate/', data: {'action': action, if (id != null) 'id': id}) as Map));
  Future<void> saveRateSettings(Map<String, dynamic> data) => client.patch('/admin/settings/', data: data);
  Future<StoreInfo> settings() async => StoreInfo.fromJson(await client.get('/admin/settings/'));
  Future<StoreInfo> saveSettings(Map<String, dynamic> data) async => StoreInfo.fromJson(await client.patch('/admin/settings/', data: data));
  Future<List<Map<String, dynamic>>> staff() async =>
      ((await client.get('/admin/staff/')) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Future<void> addStaff(Map<String, dynamic> data) => client.post('/admin/staff/', data: data);
  Future<void> updateStaff(int id, Map<String, dynamic> data) => client.patch('/admin/staff/$id/', data: data);
  Future<Map<String, dynamic>> collections(DateTime from, DateTime to, {int? staffId}) async => Map<String, dynamic>.from(
      await client.get('/admin/collections/', query: {'from': _day(from), 'to': _day(to), if (staffId != null) 'staff': staffId}) as Map);
  static String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Future<PageResult<Map<String, dynamic>>> auditLog({int page = 1, int? staffId}) async => PageResult.fromJson(
      await client.get<Map<String, dynamic>>('/admin/audit/', query: {'page': page, if (staffId != null) 'staff': staffId}),
      (j) => j);
  Future<List<int>> auditCsv({int? staffId}) =>
      client.getBytes('/admin/audit/', query: {'format': 'xlsx', 'lang': moneyLang, if (staffId != null) 'staff': staffId});
  Future<Map<String, dynamic>> whatsApp() async => Map<String, dynamic>.from(await client.get('/admin/whatsapp/') as Map);
  Future<Map<String, dynamic>> saveWhatsApp(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(await client.patch('/admin/whatsapp/', data: data) as Map);
  Future<Map<String, dynamic>> whatsAppLink() async => Map<String, dynamic>.from(await client.get('/admin/whatsapp/link/') as Map);
  Future<void> unlinkWhatsApp() => client.post('/admin/whatsapp/link/', data: {});
  Future<String> pairWhatsApp(String phone) async =>
      ((await client.post('/admin/whatsapp/link/', data: {'action': 'pair', 'phone': phone})) as Map)['code'] as String;
  Future<Map<String, dynamic>> testWhatsApp(String phone) async =>
      Map<String, dynamic>.from(await client.post('/admin/whatsapp/', data: {'phone': phone}) as Map);
  Future<List<LegalPage>> legalPages() async => _list(await client.get('/admin/legal/'), LegalPage.fromJson);
  Future<void> saveLegal(String slug, Map<String, dynamic> data) => client.patch('/admin/legal/$slug/', data: data);

  // Reports
  Future<Report> report(String period, DateTime from, DateTime to) async =>
      Report.fromJson(await client.get('/admin/reports/', query: {'period': period, 'from': isoDate(from), 'to': isoDate(to)}));
  Future<List<int>> reportCsv(String period, DateTime from, DateTime to) =>
      client.getBytes('/admin/reports/', query: {'period': period, 'from': isoDate(from), 'to': isoDate(to), 'format': 'xlsx', 'lang': moneyLang});

  Future<void> registerDevice(String token, String lang) =>
      client.post('/devices/', data: {'token': token, 'app': 'admin', 'platform': 'android', 'language': lang});
}
