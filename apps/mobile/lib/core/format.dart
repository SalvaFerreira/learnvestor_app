import 'package:intl/intl.dart';

/// Virtual euros (the in-app currency).
String formatEur(num value, {String? locale, int decimals = 2}) =>
    NumberFormat.currency(locale: locale, symbol: '€', decimalDigits: decimals).format(value);

/// A price in the instrument's own currency (e.g. US stocks in USD).
String formatPrice(num value, String currency, {String? locale}) =>
    NumberFormat.simpleCurrency(locale: locale, name: currency).format(value);

String formatPercent(num value, {String? locale}) {
  final sign = value > 0 ? '+' : '';
  return '$sign${NumberFormat('0.00', locale).format(value)}%';
}

String formatQuantity(num value, {String? locale}) => NumberFormat('0.######', locale).format(value);

/// Supabase returns numeric columns as num or String depending on precision.
double toDouble(Object? value) => switch (value) {
      null => 0,
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

int toInt(Object? value) => toDouble(value).round();
