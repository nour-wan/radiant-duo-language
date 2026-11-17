import 'package:intl/intl.dart';

final _whole = NumberFormat('#,##0', 'en_US');
final _fraction = NumberFormat('#,##0.##', 'en_US');
final _usd = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);

/// Language for currency labels; kept in sync by [AppSettings].
String moneyLang = 'ar';

String _amount(num v) => v == v.roundToDouble() ? _whole.format(v) : _fraction.format(v);

/// Amounts in Syrian pounds: "4,190 ل.س" / "4,190 SYP" with Western digits in both languages.
/// Every price a customer sees is in Syrian pounds.
String money(num? v) => v == null ? '—' : (moneyLang == 'ar' ? '${_amount(v)} ل.س' : '${_amount(v)} SYP');

/// Large Syrian-pound amounts shortened for dashboards: "1.2M ل.س".
String moneyCompact(num v) {
  if (v.abs() < 100000) return money(v);
  final c = NumberFormat.compact(locale: 'en_US').format(v);
  return moneyLang == 'ar' ? '$c ل.س' : '$c SYP';
}

/// US dollars — only in the admin app, where product prices are entered.
String usd(num? v) => v == null ? '—' : _usd.format(v);

String formatDate(DateTime d, String lang) => DateFormat('d MMM y', lang == 'ar' ? 'ar' : 'en').format(d);
String formatDateTime(DateTime d, String lang) => DateFormat('d MMM y – HH:mm', lang == 'ar' ? 'ar' : 'en').format(d);
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
