import 'package:alusekis/core/auth/auth_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateEmail', () {
    test('accepts ordinary addresses and trims spaces', () {
      expect(validateEmail('jonas@example.lt'), isNull);
      expect(validateEmail('  jonas@example.lt '), isNull);
    });

    test('rejects empty, malformed and too long addresses in Lithuanian', () {
      expect(validateEmail(''), 'Įveskite el. pašto adresą.');
      expect(validateEmail(null), 'Įveskite el. pašto adresą.');
      expect(validateEmail('jonas'), 'Neteisingas el. pašto adresas.');
      expect(validateEmail('a@b'), 'Neteisingas el. pašto adresas.');
      expect(validateEmail('jo nas@example.lt'), 'Neteisingas el. pašto adresas.');
      expect(
        validateEmail('${'a' * 250}@x.lt'),
        'El. paštas negali būti ilgesnis nei 254 simbolių.',
      );
    });
  });

  group('validateNewPassword', () {
    test('requires 12 to 128 characters', () {
      expect(validateNewPassword('a' * 11), isNotNull);
      expect(validateNewPassword('a' * 12), isNull);
      expect(validateNewPassword('a' * 128), isNull);
      expect(validateNewPassword('a' * 129), isNotNull);
      expect(validateNewPassword(''), 'Įveskite slaptažodį.');
      expect(
        validateNewPassword('short'),
        'Slaptažodis turi būti 12–128 simbolių.',
      );
    });
  });

  test('validateRequiredPassword only checks presence', () {
    expect(validateRequiredPassword(''), 'Įveskite slaptažodį.');
    expect(validateRequiredPassword('x'), isNull);
  });

  group('extractResetToken', () {
    test('returns a bare token unchanged', () {
      expect(extractResetToken('  abc-DEF_123 '), 'abc-DEF_123');
    });

    test('takes the token out of the e-mailed link', () {
      expect(
        extractResetToken('alusekis://reset-password?token=abc-DEF_123'),
        'abc-DEF_123',
      );
      expect(
        extractResetToken('alusekis://reset-password?token=a%2Bb'),
        'a+b',
      );
    });
  });
}
