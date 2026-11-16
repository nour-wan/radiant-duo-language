import 'package:intl/intl.dart';

final _money = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
final _moneyCompact = NumberFormat.compactCurrency(locale: 'en_US', symbol: '\$', decimalDigits: 1);

/// Prices are always shown as "$1,234.50" with Western digits in both languages.
String money(num? v) => v == null ? '—' : _money.format(v);
String moneyCompact(num v) => v.abs() >= 10000 ? _moneyCompact.format(v) : _money.format(v);

String formatDate(DateTime d, String lang) => DateFormat('d MMM y', lang == 'ar' ? 'ar' : 'en').format(d);
String formatDateTime(DateTime d, String lang) => DateFormat('d MMM y – HH:mm', lang == 'ar' ? 'ar' : 'en').format(d);
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
