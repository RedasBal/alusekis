/// Smallest and largest price the app and server accept, in whole euro cents.
const int minPriceCents = 1;
const int maxPriceCents = 50000;

/// Formats whole euro [cents] for display, e.g. `199` -> `1,99 €`.
///
/// Prices are never handled as floating point numbers. Negative values are a
/// programming error and throw an [ArgumentError].
String formatPrice(int cents) {
  if (cents < 0) {
    throw ArgumentError.value(cents, 'cents', 'must not be negative');
  }
  final euros = cents ~/ 100;
  final remainder = (cents % 100).toString().padLeft(2, '0');
  return '$euros,$remainder €';
}
