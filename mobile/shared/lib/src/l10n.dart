import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'format.dart';

/// Simple two-language string table. Each app registers its own keys on startup.
class L10n {
  static final Map<String, Map<String, String>> _table = {'ar': {}, 'en': {}};

  static void register(Map<String, List<String>> entries) {
    entries.forEach((key, pair) {
      _table['ar']![key] = pair[0];
      _table['en']![key] = pair[1];
    });
  }

  static String get(String lang, String key, [Map<String, Object?> args = const {}]) {
    var s = _table[lang]?[key] ?? _table['ar']?[key] ?? key;
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  /// Translate an API error code; falls back to a generic message.
  static String error(String lang, Object error) {
    final code = error is ApiException ? error.code : 'unknown';
    // A form error with its own message code (e.g. {"phone": ["phone_taken"]})
    if (code == 'invalid' && error is ApiException) {
      final field = _table[lang]?['err.${error.message}'];
      if (field != null) return field;
    }
    return _table[lang]?['err.$code'] ?? get(lang, 'err.unknown');
  }
}

extension L10nContext on BuildContext {
  String get lang => Localizations.localeOf(this).languageCode;
  bool get isAr => lang == 'ar';
  String tr(String key, [Map<String, Object?> args = const {}]) => L10n.get(lang, key, args);
  String trError(Object error) => L10n.error(lang, error);
}

/// Language and day/night appearance, persisted on the device.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs)
      : _lang = _prefs.getString('lang') ?? 'ar',
        _theme = ThemeMode.values[_prefs.getInt('theme') ?? ThemeMode.system.index] {
    moneyLang = _lang;
  }

  final SharedPreferences _prefs;
  String _lang;
  ThemeMode _theme;

  String get lang => _lang;
  Locale get locale => Locale(_lang);
  ThemeMode get themeMode => _theme;
  SharedPreferences get prefs => _prefs;

  Future<void> setLang(String lang) async {
    if (lang == _lang) return;
    _lang = lang;
    moneyLang = lang;
    await _prefs.setString('lang', lang);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _theme = mode;
    await _prefs.setInt('theme', mode.index);
    notifyListeners();
  }
}

/// Strings shared by both apps (error codes, common buttons, statuses).
const sharedStrings = <String, List<String>>{
  'app.retry': ['إعادة المحاولة', 'Try again'],
  'app.cancel': ['إلغاء', 'Cancel'],
  'app.save': ['حفظ', 'Save'],
  'app.delete': ['حذف', 'Delete'],
  'app.edit': ['تعديل', 'Edit'],
  'app.add': ['إضافة', 'Add'],
  'app.close': ['إغلاق', 'Close'],
  'app.confirm': ['تأكيد', 'Confirm'],
  'app.yes': ['نعم', 'Yes'],
  'app.no': ['لا', 'No'],
  'app.search': ['بحث', 'Search'],
  'app.loading': ['جارٍ التحميل…', 'Loading…'],
  'app.saved': ['تم الحفظ', 'Saved'],
  'app.offline': ['لا يوجد اتصال بالإنترنت', 'No internet connection'],
  'app.offline_hint': ['تحقق من اتصالك ثم حاول مجدداً.', 'Check your connection and try again.'],
  'app.empty': ['لا توجد بيانات', 'Nothing here yet'],
  'app.language': ['اللغة', 'Language'],
  'app.arabic': ['العربية', 'العربية'],
  'app.english': ['English', 'English'],
  'app.appearance': ['المظهر', 'Appearance'],
  'app.theme_system': ['حسب الجهاز', 'System'],
  'app.theme_light': ['نهاري', 'Light'],
  'app.theme_dark': ['ليلي', 'Dark'],
  'app.required': ['هذا الحقل مطلوب', 'This field is required'],
  'app.invalid_email': ['البريد الإلكتروني غير صحيح', 'Invalid email address'],
  'app.password_short': ['كلمة المرور 8 أحرف على الأقل', 'Password must be at least 8 characters'],
  'app.email': ['البريد الإلكتروني', 'Email'],
  'app.password': ['كلمة المرور', 'Password'],
  'app.logout': ['تسجيل الخروج', 'Log out'],
  'app.version': ['الإصدار', 'Version'],
  'app.all': ['الكل', 'All'],
  'app.currency_note': ['جميع الأسعار بالليرة السورية', 'All prices in Syrian pounds'],
  'status.pending': ['قيد المراجعة', 'Pending'],
  'status.confirmed': ['مؤكد', 'Confirmed'],
  'status.shipped': ['قيد التوصيل', 'Shipped'],
  'status.delivered': ['تم التسليم', 'Delivered'],
  'status.cancelled': ['ملغى', 'Cancelled'],
  'status.shipped_any': ['قيد التوصيل / جاهز للاستلام', 'Shipped / ready for pickup'],
  'status.shipped_pickup': ['جاهز للاستلام', 'Ready for pickup'],
  'status.delivered_pickup': ['تم الاستلام', 'Picked up'],
  'biz.cafe': ['مقهى / كافيه', 'Café'],
  'biz.restaurant': ['مطعم', 'Restaurant'],
  'biz.cafeteria': ['كافيتيريا', 'Cafeteria'],
  'biz.bakery': ['فرن / مخبز', 'Bakery'],
  'biz.sweets': ['محل حلويات', 'Sweets shop'],
  'biz.factory': ['معمل / مصنع', 'Factory / workshop'],
  'biz.ice_cream': ['محل بوظة / آيس كريم', 'Ice cream shop'],
  'biz.hotel': ['فندق', 'Hotel'],
  'biz.market': ['سوبرماركت / بقالية', 'Supermarket / grocery'],
  'biz.other': ['أخرى', 'Other'],
  'delivery.pickup': ['استلام من المحل', 'Pick up from store'],
  'delivery.delivery': ['توصيل', 'Delivery'],
  'delivery.free': ['مجاناً', 'Free'],
  'app_discount': ['خصم الطلب عبر التطبيق', 'App order discount'],
  'err.address_required': ['أدخل المنطقة والعنوان التفصيلي للتوصيل.', 'Enter your area and detailed delivery address.'],
  'ledger.title': ['كشف الحساب', 'Account statement'],
  'ledger.balance_owed': ['المتبقي عليك', 'Amount due'],
  'ledger.balance_owed_admin': ['المتبقي على الزبون', 'Customer owes'],
  'ledger.balance_credit': ['رصيد لصالحك', 'Your credit'],
  'ledger.balance_credit_admin': ['رصيد لصالح الزبون', 'Customer credit'],
  'ledger.settled': ['الحساب مسدد بالكامل', 'Fully paid'],
  'ledger.credit_limit': ['سقف الدين', 'Credit limit'],
  'ledger.no_limit': ['بلا سقف', 'No limit'],
  'ledger.credit_off': ['الدين غير مفعّل', 'Credit not enabled'],
  'ledger.available': ['المتاح للطلبات الجديدة', 'Available for new orders'],
  'ledger.open_orders': ['طلبات قيد التنفيذ', 'Orders in progress'],
  'ledger.empty': ['لا توجد حركات على الحساب بعد.', 'No account activity yet.'],
  'ledger.kind.order': ['طلب مُسلَّم', 'Delivered order'],
  'ledger.kind.payment': ['دفعة', 'Payment'],
  'ledger.kind.adjustment': ['تصحيح', 'Adjustment'],
  'ledger.balance_after': ['الرصيد', 'Balance'],
  'ledger.note_usd': ['المبالغ بالليرة السورية ولا تشمل أجرة التوصيل.', 'Amounts are in Syrian pounds and exclude delivery fees.'],
  'ledger.paid': ['المدفوع', 'Paid'],
  'ledger.credit_used': ['مخصوم من رصيدك لدينا', 'Paid from your credit'],
  'ledger.credit_used_admin': ['مخصوم من رصيد الزبون', 'Paid from customer credit'],
  'ledger.to_collect': ['المطلوب عند الاستلام', 'Due on delivery'],
  'ledger.to_collect_admin': ['المطلوب تحصيله', 'To collect'],
  'ledger.remaining': ['المتبقي من الطلب', 'Remaining on this order'],
  'invoice.download': ['الفاتورة PDF', 'Invoice PDF'],
  'invoice.share': ['مشاركة الفاتورة', 'Share invoice'],
  'err.credit_limit_exceeded': ['تجاوزت سقف الدين المسموح. تواصل معنا أو سدّد جزءاً من الحساب لإكمال الطلب.', 'This order exceeds your credit limit. Please contact us or settle part of your balance.'],
  'err.account_has_balance': ['لا يمكن حذف الحساب وعليه رصيد مفتوح. تواصل معنا لتسوية الحساب أولاً.', 'The account has an open balance. Please contact us to settle it first.'],
  'err.invalid_amount': ['أدخل مبلغاً صحيحاً.', 'Enter a valid amount.'],
  'err.note_required': ['اكتب سبب التصحيح.', 'Enter the reason for the adjustment.'],
  'err.invalid_order': ['لا يمكن تسجيل دفعة على هذا الطلب.', 'A payment cannot be recorded on this order.'],
  'err.payment_requires_delivered': ['المبلغ المدفوع يُسجَّل فقط عند التسليم.', 'A payment can only be recorded on delivery.'],
  'err.customer_deleted': ['حساب الزبون محذوف.', 'The customer account was deleted.'],
  'err.unknown': ['حدث خطأ غير متوقع، حاول مرة أخرى.', 'Something went wrong. Please try again.'],
  'err.network': ['تعذّر الاتصال بالخادم. تحقق من الإنترنت.', 'Could not reach the server. Check your internet.'],
  'err.server_error': ['الخادم غير متاح مؤقتاً، حاول لاحقاً.', 'The server is temporarily unavailable.'],
  'err.not_found': ['العنصر غير موجود.', 'Not found.'],
  'err.throttled': ['محاولات كثيرة، انتظر قليلاً ثم حاول.', 'Too many attempts. Please wait a moment.'],
  'err.invalid_credentials': ['بيانات الدخول غير صحيحة، تأكد من الرقم وكلمة السر.', 'Incorrect login details. Check the number and password.'],
  'err.not_on_whatsapp': ['هذا الرقم ليس عليه واتساب. اكتب رقماً عليه واتساب لتصلك رسالة التحقق.', 'This number has no WhatsApp. Use a number with WhatsApp to receive the code.'],
  'err.invalid_phone': ['رقم الهاتف غير صحيح. اكتبه مثل 0944123456', 'Invalid phone number. Write it like 0944123456'],
  'err.phone_taken': ['هذا الرقم مسجّل مسبقاً. سجّل الدخول أو استعد كلمة السر.', 'This number is already registered. Log in or reset your password.'],
  'err.code_invalid': ['رمز التحقق غير صحيح أو انتهت صلاحيته.', 'The verification code is wrong or expired.'],
  'err.code_too_soon': ['انتظر دقيقة قبل طلب رمز جديد.', 'Please wait a minute before asking for a new code.'],
  'err.too_many_codes': ['طلبت رموزاً كثيرة، حاول بعد ساعة.', 'Too many codes requested. Try again in an hour.'],
  'err.not_authenticated': ['يجب تسجيل الدخول.', 'Please log in.'],
  'err.authentication_failed': ['انتهت الجلسة، سجّل الدخول مجدداً.', 'Session expired. Please log in again.'],
  'err.token_not_valid': ['انتهت الجلسة، سجّل الدخول مجدداً.', 'Session expired. Please log in again.'],
  'err.permission_denied': ['ليست لديك صلاحية.', 'You do not have permission.'],
  'err.invalid': ['تحقق من البيانات المدخلة.', 'Please check the entered data.'],
  'err.wrong_password': ['كلمة المرور غير صحيحة.', 'Wrong password.'],
  'err.reset_code_invalid': ['الرمز غير صحيح أو منتهي الصلاحية.', 'The code is invalid or expired.'],
  'err.google_not_configured': ['الدخول عبر Google غير مفعّل حالياً.', 'Google sign-in is not available yet.'],
  'err.google_token_invalid': ['تعذّر التحقق من حساب Google.', 'Could not verify your Google account.'],
  'err.google_email_unverified': ['بريد Google غير موثّق.', 'Your Google email is not verified.'],
  'order.grand_total': ['الإجمالي مع التوصيل', 'Total incl. delivery'],
  'err.cart_empty': ['السلة فارغة.', 'Your cart is empty.'],
  'err.prices_changed': ['تغيّر سعر الصرف وتم تحديث الأسعار. راجع المجموع الجديد ثم أكّد الطلب.', 'The exchange rate changed and prices were updated. Check the new total, then place the order.'],
  'err.prices_unavailable': ['الأسعار غير متوفرة حالياً، حاول بعد قليل.', 'Prices are not available right now. Please try again shortly.'],
  'err.rate_fetch_failed': ['تعذّر قراءة سعر الدولار من موقع الليرة اليوم الآن.', 'Could not read the dollar rate from sp-today.com right now.'],
  'err.rate_out_of_range': ['السعر غير منطقي. اكتب سعر الدولار بالليرة الجديدة (مثلاً 149.5).', 'That rate looks wrong. Enter the dollar rate in new Syrian pounds (e.g. 149.5).'],
  'err.cart_invalid': ['بيانات السلة غير صحيحة.', 'Invalid cart.'],
  'err.item_unavailable': ['أحد المنتجات لم يعد متوفراً.', 'An item is no longer available.'],
  'err.below_min_qty': ['الكمية أقل من الحد الأدنى للطلب.', 'Quantity is below the minimum order.'],
  'err.insufficient_stock': ['الكمية المطلوبة غير متوفرة في المخزون.', 'Not enough stock for the requested quantity.'],
  'err.orders_disabled': ['استقبال الطلبات متوقف مؤقتاً.', 'Ordering is temporarily paused.'],
  'err.below_min_order_total': ['قيمة الطلب أقل من الحد الأدنى.', 'Order total is below the minimum.'],
  'err.coupon_invalid': ['رمز الخصم غير صحيح.', 'Invalid coupon code.'],
  'err.coupon_inactive': ['رمز الخصم غير فعّال.', 'This coupon is not active.'],
  'err.coupon_not_started': ['رمز الخصم لم يبدأ بعد.', 'This coupon has not started yet.'],
  'err.coupon_expired': ['انتهت صلاحية رمز الخصم.', 'This coupon has expired.'],
  'err.coupon_used_up': ['انتهى عدد مرات استخدام الكوبون.', 'This coupon has been fully used.'],
  'err.coupon_already_used': ['استخدمت هذا الكوبون سابقاً.', 'You have already used this coupon.'],
  'err.coupon_min_total': ['قيمة الطلب أقل من الحد الأدنى لهذا الكوبون.', 'Order total is below this coupon\'s minimum.'],
  'err.contact_required': ['أدخل الاسم والهاتف والمدينة.', 'Enter name, phone and city.'],
  'err.cannot_cancel': ['لا يمكن إلغاء الطلب في حالته الحالية.', 'This order can no longer be cancelled.'],
  'err.invalid_status_change': ['لا يمكن الانتقال إلى هذه الحالة.', 'This status change is not allowed.'],
  'err.confirmation_required': ['يجب تأكيد العملية.', 'Please confirm.'],
  'err.admin_cannot_self_delete': ['لا يمكن حذف حساب الإدارة من هنا.', 'Admin accounts cannot be deleted here.'],
  'err.category_has_products': ['لا يمكن حذف فئة تحتوي منتجات.', 'Cannot delete a category that has products.'],
  'err.image_required': ['اختر صورة.', 'Please choose an image.'],
  'err.too_many_images': ['الحد الأقصى 10 صور للمنتج.', 'Maximum 10 images per product.'],
  'err.invalid_date': ['تاريخ غير صحيح.', 'Invalid date.'],
  'err.forbidden': ['غير مسموح.', 'Not allowed.'],
};
