import 'package:alusekis/core/utils/price_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePriceToCents', () {
    test('accepts comma and dot as decimal separator', () {
      expect(parsePriceToCents('1,99'), 199);
      expect(parsePriceToCents('1.99'), 199);
    });

    test('handles whole numbers and one decimal', () {
      expect(parsePriceToCents('2'), 200);
      expect(parsePriceToCents('1,5'), 150);
      expect(parsePriceToCents('0,5'), 50);
      expect(parsePriceToCents('0,05'), 5);
      expect(parsePriceToCents('2,'), isNull);
    });

    test('trims whitespace', () {
      expect(parsePriceToCents('  1,20 '), 120);
    });

    test('accepts boundary values', () {
      expect(parsePriceToCents('0,01'), 1);
      expect(parsePriceToCents('500'), 50000);
      expect(parsePriceToCents('500,00'), 50000);
    });

    test('rejects out of range values', () {
      expect(parsePriceToCents('0'), isNull);
      expect(parsePriceToCents('0,00'), isNull);
      expect(parsePriceToCents('500,01'), isNull);
      expect(parsePriceToCents('9999999'), isNull);
    });

    test('rejects invalid text', () {
      expect(parsePriceToCents(''), isNull);
      expect(parsePriceToCents('   '), isNull);
      expect(parsePriceToCents('abc'), isNull);
      expect(parsePriceToCents('1,999'), isNull);
      expect(parsePriceToCents('-1'), isNull);
      expect(parsePriceToCents('1,2,3'), isNull);
      expect(parsePriceToCents('1 99'), isNull);
      expect(parsePriceToCents('€1'), isNull);
    });
  });
}
