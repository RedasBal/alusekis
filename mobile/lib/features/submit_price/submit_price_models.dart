import 'dart:math';

import '../../core/utils/date_format.dart';
import '../../core/utils/price_parser.dart';

/// The product and store a price is submitted for, known before the form opens.
class SubmitPriceTarget {
  const SubmitPriceTarget({
    required this.productId,
    required this.productName,
    required this.volumeMl,
    required this.storeId,
    required this.storeName,
    this.currentPriceCents,
  });

  final int productId;
  final String productName;
  final int volumeMl;
  final int storeId;
  final String storeName;

  /// The latest price the user saw, shown for reference; null when unknown.
  final int? currentPriceCents;
}

/// The server's answer to a successful submission.
class SubmittedPrice {
  const SubmittedPrice({
    required this.id,
    required this.productId,
    required this.storeId,
    required this.priceCents,
    required this.observedAt,
    required this.isLargeChange,
  });

  factory SubmittedPrice.fromJson(Map<String, dynamic> json) => SubmittedPrice(
        id: (json['id'] as num).toInt(),
        productId: (json['productId'] as num).toInt(),
        storeId: (json['storeId'] as num).toInt(),
        priceCents: (json['priceCents'] as num).toInt(),
        observedAt: parseServerDateTime(json['observedAt'] as String),
        isLargeChange: json['isLargeChange'] as bool,
      );

  final int id;
  final int productId;
  final int storeId;
  final int priceCents;
  final DateTime observedAt;
  final bool isLargeChange;
}

/// The server wants confirmation: the price differs more than 50 % from [previousPriceCents].
class LargePriceChangeException implements Exception {
  const LargePriceChangeException(this.previousPriceCents);

  final int previousPriceCents;

  @override
  String toString() => 'LargePriceChangeException(previous: $previousPriceCents)';
}

/// Result of checking the price field: either [cents] or a Lithuanian [error].
class PriceInput {
  const PriceInput.valid(int this.cents) : error = null;

  const PriceInput.invalid(String this.error) : cents = null;

  final int? cents;
  final String? error;
}

final RegExp _priceShape = RegExp(r'^\d{1,6}(?:[.,]\d{1,2})?$');

/// Checks the text of the price field. Accepts a comma or a point ("1,99",
/// "1.99", "2"). Uses the shared [parsePriceToCents]: whole cents, no doubles.
PriceInput checkPriceInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const PriceInput.invalid('Įveskite kainą.');
  }
  final cents = parsePriceToCents(text);
  if (cents != null) {
    return PriceInput.valid(cents);
  }
  return _priceShape.hasMatch(text)
      ? const PriceInput.invalid('Kaina turi būti nuo 0,01 iki 500,00 €.')
      : const PriceInput.invalid('Neteisingas kainos formatas. Pavyzdžiui, 1,99.');
}

/// A random UUID (version 4) from a secure source, used as the idempotency key
/// of one submission.
String newIdempotencyKey([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
