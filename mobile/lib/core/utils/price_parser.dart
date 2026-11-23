import 'price_format.dart';

final RegExp _priceInput = RegExp(r'^(\d{1,6})(?:[.,](\d{1,2}))?$');

/// Parses user input such as `1,99`, `1.99`, `2` or `0,5` into whole euro cents.
///
/// Returns `null` for anything invalid: empty text, letters, negative values,
/// more than two decimals, or a value outside
/// [minPriceCents]..[maxPriceCents]. Uses integer arithmetic only.
int? parsePriceToCents(String input) {
  final match = _priceInput.firstMatch(input.trim());
  if (match == null) {
    return null;
  }
  final euros = int.parse(match.group(1)!);
  final decimals = (match.group(2) ?? '').padRight(2, '0');
  final cents = euros * 100 + int.parse(decimals.isEmpty ? '0' : decimals);
  if (cents < minPriceCents || cents > maxPriceCents) {
    return null;
  }
  return cents;
}
