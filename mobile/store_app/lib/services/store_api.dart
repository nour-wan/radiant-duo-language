import 'package:alas_shared/alas_shared.dart';

class HomeData {
  HomeData.fromJson(Map<String, dynamic> j)
      : banners = _list(j['banners'], BannerItem.fromJson),
        categories = _list(j['categories'], Category.fromJson),
        featured = _list(j['featured'], ProductSummary.fromJson),
        offers = _list(j['offers'], ProductSummary.fromJson),
        bestSellers = _list(j['best_sellers'], ProductSummary.fromJson),
        newest = _list(j['newest'], ProductSummary.fromJson);

  final List<BannerItem> banners;
  final List<Category> categories;
  final List<ProductSummary> featured, offers, bestSellers, newest;
}

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
    (v as List? ?? []).map((e) => f(e as Map<String, dynamic>)).toList();

class ProductQuery {
  const ProductQuery({this.q = '', this.categoryId, this.minPrice, this.maxPrice, this.onSale = false, this.featured = false, this.sort = 'newest'});

  final String q;
  final int? categoryId;
  final double? minPrice, maxPrice;
  final bool onSale, featured;
  final String sort;

  bool get hasFilters => categoryId != null || minPrice != null || maxPrice != null || onSale;

  ProductQuery copyWith({String? q, int? Function()? categoryId, double? Function()? minPrice, double? Function()? maxPrice, bool? onSale, String? sort}) =>
      ProductQuery(
        q: q ?? this.q,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        minPrice: minPrice != null ? minPrice() : this.minPrice,
        maxPrice: maxPrice != null ? maxPrice() : this.maxPrice,
        onSale: onSale ?? this.onSale,
        featured: featured,
        sort: sort ?? this.sort,
      );

  Map<String, dynamic> toParams(int page) => {
        'page': page,
        'sort': sort,
        if (q.trim().isNotEmpty) 'q': q.trim(),
        if (categoryId != null) 'category': categoryId,
        if (minPrice != null) 'min_price': minPrice,
        if (maxPrice != null) 'max_price': maxPrice,
        if (onSale) 'on_sale': 1,
        if (featured) 'featured': 1,
      };
}

class Quote {
  Quote.fromJson(Map<String, dynamic> j)
      : lines = (j['lines'] as List).map((e) => QuoteLine.fromJson(e as Map<String, dynamic>)).toList(),
        subtotal = toMoney(j['subtotal']),
        discount = toMoney(j['discount']),
        appDiscount = toMoney(j['app_discount']),
        appDiscountPercent = toMoney(j['app_discount_percent']),
        total = toMoney(j['total']),
        deliveryMethod = j['delivery_method'] as String? ?? 'delivery',
        deliveryFee = toMoney(j['delivery_fee']),
        deliveryAreaListed = j['delivery_area_listed'] as bool? ?? true,
        currencyAr = j['delivery_currency_ar'] as String? ?? 'ل.س',
        currencyEn = j['delivery_currency_en'] as String? ?? 'SYP',
        couponCode = j['coupon_code'] as String?,
        couponProblem = j['coupon_problem'] as String?,
        orderProblem = j['order_problem'] as String?,
        minOrderTotal = toMoney(j['min_order_total']),
        ok = j['ok'] as bool? ?? false;

  final List<QuoteLine> lines;
  final double subtotal, discount, appDiscount, appDiscountPercent, total, deliveryFee, minOrderTotal;
  final String deliveryMethod, currencyAr, currencyEn;
  final bool deliveryAreaListed;
  final String? couponCode, couponProblem, orderProblem;
  final bool ok;

  String currency(String lang) => pick(lang, currencyAr, currencyEn);

  QuoteLine? line(int variantId) => lines.where((l) => l.variantId == variantId).firstOrNull;
}

class QuoteLine {
  QuoteLine.fromJson(Map<String, dynamic> j)
      : variantId = j['variant_id'] as int,
        quantity = j['quantity'] as int,
        unitPrice = toMoney(j['unit_price']),
        regularPrice = toMoney(j['regular_price']),
        lineTotal = toMoney(j['line_total']),
        stock = j['stock'] as int,
        minOrderQty = j['min_order_qty'] as int,
        problem = j['problem'] as String?;

  final int variantId, quantity, stock, minOrderQty;
  final double unitPrice, regularPrice, lineTotal;
  final String? problem;
}

/// All store endpoints in one place.
class StoreApi {
  StoreApi(this.client);

  final ApiClient client;

  Future<HomeData> home() async => HomeData.fromJson(await client.get('/home/'));
  Future<List<Category>> categories() async => _list(await client.get('/categories/'), Category.fromJson);
  Future<PageResult<ProductSummary>> products(ProductQuery q, {int page = 1}) async =>
      PageResult.fromJson(await client.get('/products/', query: q.toParams(page)), ProductSummary.fromJson);
  Future<ProductDetail> product(String key) async => ProductDetail.fromJson(await client.get('/products/$key/'));
  Future<StoreInfo> settings() async => StoreInfo.fromJson(await client.get('/settings/'));
  Future<LegalPage> legal(String slug) async => LegalPage.fromJson(await client.get('/legal/$slug/'));

  Future<DeliveryInfo> delivery() async => DeliveryInfo.fromJson(await client.get('/delivery/'));

  Future<Quote> quote(List<Map<String, dynamic>> items, String? coupon, {String? deliveryMethod, int? areaId}) async =>
      Quote.fromJson(await client.post('/cart/quote/', data: {
        'items': items,
        if (coupon != null) 'coupon_code': coupon,
        if (deliveryMethod != null) 'delivery_method': deliveryMethod,
        if (areaId != null) 'delivery_area_id': areaId,
      }));

  Future<OrderDetail> placeOrder(Map<String, dynamic> payload) async => OrderDetail.fromJson(await client.post('/orders/', data: payload));
  Future<PageResult<OrderSummary>> orders({int page = 1}) async =>
      PageResult.fromJson(await client.get('/orders/', query: {'page': page}), OrderSummary.fromJson);
  Future<OrderDetail> order(int id) async => OrderDetail.fromJson(await client.get('/orders/$id/'));
  Future<List<int>> invoicePdf(int id, String lang) => client.getBytes('/orders/$id/invoice/', query: {'lang': lang});
  Future<OrderDetail> cancelOrder(int id) async => OrderDetail.fromJson(await client.post('/orders/$id/cancel/'));
  Future<Statement> statement() async => Statement.fromJson(await client.get('/me/statement/', query: {'page_size': 100}));

  Future<List<Address>> addresses() async => _list(await client.get('/addresses/'), Address.fromJson);
  Future<Address> saveAddress(Address a) async => Address.fromJson(
      a.id == null ? await client.post('/addresses/', data: a.toJson()) : await client.patch('/addresses/${a.id}/', data: a.toJson()));
  Future<void> deleteAddress(int id) => client.delete('/addresses/$id/');

  Future<List<ProductSummary>> favorites() async => _list(await client.get('/favorites/'), ProductSummary.fromJson);
  Future<Set<int>> favoriteIds() async => ((await client.get<List>('/favorites/ids/'))).cast<int>().toSet();
  Future<void> addFavorite(int productId) => client.put('/favorites/$productId/');
  Future<void> removeFavorite(int productId) => client.delete('/favorites/$productId/');

  Future<PageResult<AppNotification>> notifications({int page = 1}) async =>
      PageResult.fromJson(await client.get('/notifications/', query: {'page': page}), AppNotification.fromJson);
  Future<int> unreadCount() async => (await client.get<Map>('/notifications/unread/'))['unread'] as int;
  Future<void> markNotificationsSeen() => client.post('/notifications/seen/');
  Future<void> registerDevice(String token, String lang) =>
      client.post('/devices/', data: {'token': token, 'app': 'store', 'platform': _platform, 'language': lang});
}

String get _platform => const String.fromEnvironment('PLATFORM', defaultValue: 'android');
