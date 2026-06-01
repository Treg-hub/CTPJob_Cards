import 'package:intl/intl.dart';

/// South African formatting helpers for WasteTrack (and Job Cards where applicable).
/// - Dates: DD/MM/YYYY
/// - Currency: R 12 450.75 (space as thousands separator)
/// - Weight: 1 234.5 kg

final _saNumberFormat = NumberFormat('#,##0.##', 'en_ZA');
final _saCurrencyFormat = NumberFormat.currency(
  locale: 'en_ZA',
  symbol: 'R ',
  decimalDigits: 2,
);

String formatSAWeight(double kg) {
  return '${_saNumberFormat.format(kg)} kg';
}

String formatSACurrency(double amount) {
  // NumberFormat.currency with en_ZA already uses space as thousands separator.
  return _saCurrencyFormat.format(amount);
}

String formatSADate(DateTime date) {
  return DateFormat('dd/MM/yyyy').format(date);
}

String formatSADateTime(DateTime dateTime) {
  return DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
}

/// For very large numbers in reports.
String formatSALargeNumber(num value) {
  return _saNumberFormat.format(value);
}
