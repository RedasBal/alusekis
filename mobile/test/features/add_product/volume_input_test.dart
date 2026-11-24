import 'package:alusekis/features/add_product/volume_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('volume in litres becomes whole millilitres', () {
    test('0,5 l is 500 ml', () => expect(checkVolumeInput('0,5', VolumeUnit.l).ml, 500));
    test('a point works as well as a comma', () => expect(checkVolumeInput('0.5', VolumeUnit.l).ml, 500));
    test('1,25 l is 1250 ml', () => expect(checkVolumeInput('1,25', VolumeUnit.l).ml, 1250));
    test('1,5 l is 1500 ml', () => expect(checkVolumeInput('1,5', VolumeUnit.l).ml, 1500));
    test('0,001 l is 1 ml', () => expect(checkVolumeInput('0,001', VolumeUnit.l).ml, 1));
    test('2 l is 2000 ml', () => expect(checkVolumeInput('2', VolumeUnit.l).ml, 2000));
    test('50 l is 50000 ml', () => expect(checkVolumeInput('50', VolumeUnit.l).ml, 50000));
    test('0,5000 l is still 500 ml', () => expect(checkVolumeInput('0,5000', VolumeUnit.l).ml, 500));

    test('0,0005 l is not a whole millilitre', () {
      final input = checkVolumeInput('0,0005', VolumeUnit.l);
      expect(input.ml, isNull);
      expect(input.error, 'Talpa turi būti sveika ml reikšmė.');
    });

    test('1,2345 l is not a whole millilitre', () {
      expect(checkVolumeInput('1,2345', VolumeUnit.l).ml, isNull);
    });

    test('50,1 l is too much', () {
      final input = checkVolumeInput('50,1', VolumeUnit.l);
      expect(input.ml, isNull);
      expect(input.error, 'Talpa turi būti nuo 1 iki 50 000 ml (50 l).');
    });

    test('0 l is too little', () => expect(checkVolumeInput('0', VolumeUnit.l).ml, isNull));
  });

  group('volume in millilitres', () {
    test('500 ml', () => expect(checkVolumeInput('500', VolumeUnit.ml).ml, 500));
    test('1 ml is the lower limit', () => expect(checkVolumeInput('1', VolumeUnit.ml).ml, 1));
    test('50000 ml is the upper limit', () => expect(checkVolumeInput('50000', VolumeUnit.ml).ml, 50000));
    test('0 ml is rejected', () => expect(checkVolumeInput('0', VolumeUnit.ml).ml, isNull));
    test('50001 ml is rejected', () => expect(checkVolumeInput('50001', VolumeUnit.ml).ml, isNull));

    test('a fraction of a millilitre is rejected', () {
      expect(checkVolumeInput('500,5', VolumeUnit.ml).error, 'Talpa turi būti sveika ml reikšmė.');
    });

    test('500,0 ml is a whole number', () => expect(checkVolumeInput('500,0', VolumeUnit.ml).ml, 500));
  });

  group('wrong text', () {
    test('empty', () {
      expect(checkVolumeInput('', VolumeUnit.ml).error, 'Įveskite talpą.');
      expect(checkVolumeInput('   ', VolumeUnit.l).error, 'Įveskite talpą.');
    });

    test('letters, signs and double separators', () {
      for (final text in ['abc', '-5', '1,2,3', '5 0', ',5', '1e3']) {
        expect(
          checkVolumeInput(text, VolumeUnit.l).error,
          'Neteisingas talpos formatas. Pavyzdžiui, 500 arba 0,5.',
          reason: text,
        );
      }
    });
  });

  group('product name', () {
    test('is trimmed', () => expect(checkProductName('  Žalgiris ').name, 'Žalgiris'));
    test('empty', () => expect(checkProductName('   ').error, 'Įveskite pavadinimą.'));
    test('1 character is too short', () => expect(checkProductName(' a ').error, isNotNull));
    test('2 characters are enough', () => expect(checkProductName('ab').name, 'ab'));
    test('150 characters are enough', () => expect(checkProductName('a' * 150).name, isNotNull));
    test('151 characters are too long', () {
      expect(checkProductName('a' * 151).error, 'Pavadinimas turi būti 2–150 simbolių.');
    });
  });
}
