import 'dart:math';

String formatAmount(double value, {int decimals = 2}) {
  if (value.abs() < pow(10, -decimals - 4)) {
    return '0.' + '0' * decimals;
  }
  String formatted = value.toStringAsFixed(decimals);
  if (formatted == '-0' || formatted == '-0.0' || formatted == '-0.00' || formatted.startsWith('-0.')) {
    if (formatted.startsWith('-0.')) {
      return formatted.substring(1);
    }
    return '0.' + '0' * decimals;
  }
  return formatted;
}
