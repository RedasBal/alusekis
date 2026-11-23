import 'package:alusekis/core/utils/price_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatPrice', () {
    test('formats cents with comma and euro sign', () {
      expect(formatPrice(199), '1,99 €');
      expect(formatPrice(100), '1,00 €');
      expect(formatPrice(5), '0,05 €');
      expect(formatPrice(0), '0,00 €');
      expect(formatPrice(50000), '500,00 €');
    });

    test('rejects negative values', () {
      expect(() => formatPrice(-1), throwsArgumentError);
    });
  });
}
