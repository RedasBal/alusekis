import 'dart:math';

import 'package:alusekis/features/submit_price/submit_price_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('checkPriceInput', () {
    test('accepts a comma or a point and gives whole cents', () {
      expect(checkPriceInput('1,99').cents, 199);
      expect(checkPriceInput('1.99').cents, 199);
      expect(checkPriceInput(' 2 ').cents, 200);
      expect(checkPriceInput('0,5').cents, 50);
      expect(checkPriceInput('0,01').cents, 1);
      expect(checkPriceInput('500').cents, 50000);
      expect(checkPriceInput('500,00').cents, 50000);
    });

    test('an empty field asks for a price', () {
      expect(checkPriceInput('').error, 'Įveskite kainą.');
      expect(checkPriceInput('   ').error, 'Įveskite kainą.');
    });

    test('a value outside 0,01 to 500,00 says the limits', () {
      for (final text in ['0', '0,00', '500,01', '999']) {
        expect(
          checkPriceInput(text).error,
          'Kaina turi būti nuo 0,01 iki 500,00 €.',
          reason: text,
        );
      }
    });

    test('anything that is not a price says how to write one', () {
      for (final text in ['abc', '1,999', '1,2,3', '-1', '1 99', ',5', '1,']) {
        expect(
          checkPriceInput(text).error,
          'Neteisingas kainos formatas. Pavyzdžiui, 1,99.',
          reason: text,
        );
      }
    });

    test('a valid price has no error and an invalid one no cents', () {
      final ok = checkPriceInput('1,49');
      final bad = checkPriceInput('x');
      expect(ok.error, isNull);
      expect(bad.cents, isNull);
    });
  });

  group('newIdempotencyKey', () {
    final uuidV4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

    test('is a random version 4 UUID', () {
      expect(newIdempotencyKey(), matches(uuidV4));
      expect(newIdempotencyKey(Random(1)), matches(uuidV4));
    });

    test('is different every time', () {
      final keys = {for (var i = 0; i < 200; i++) newIdempotencyKey()};
      expect(keys, hasLength(200));
    });

    test('fits the server limit of 100 characters', () {
      expect(newIdempotencyKey().length, 36);
    });
  });
}
