/// Units the volume field accepts.
enum VolumeUnit {
  ml('ml'),
  l('l');

  const VolumeUnit(this.label);

  final String label;
}

/// Server limits for a product's volume, in whole millilitres.
const int minVolumeMl = 1;
const int maxVolumeMl = 50000;

/// Result of checking the volume field: either [ml] or a Lithuanian [error].
class VolumeInput {
  const VolumeInput.valid(int this.ml) : error = null;

  const VolumeInput.invalid(String this.error) : ml = null;

  final int? ml;
  final String? error;
}

final RegExp _volumeShape = RegExp(r'^(\d{1,6})(?:[.,](\d{1,6}))?$');

/// Checks the text of the volume field and converts it to whole millilitres.
///
/// Accepts a comma or a point. In litres up to three decimals are whole
/// millilitres ("0,5" = 500 ml, "1,25" = 1250 ml); "0,0005 l" is half a
/// millilitre and is rejected. Integer arithmetic only, no doubles.
VolumeInput checkVolumeInput(String raw, VolumeUnit unit) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const VolumeInput.invalid('Įveskite talpą.');
  }
  final match = _volumeShape.firstMatch(text);
  if (match == null) {
    return const VolumeInput.invalid('Neteisingas talpos formatas. Pavyzdžiui, 500 arba 0,5.');
  }

  final whole = int.parse(match.group(1)!);
  final fraction = match.group(2) ?? '';
  final decimals = unit == VolumeUnit.l ? 3 : 0;

  // Digits beyond the millilitre must all be zero ("0,5000 l" is fine).
  final extra = fraction.length > decimals ? fraction.substring(decimals) : '';
  if (extra.replaceAll('0', '').isNotEmpty) {
    return const VolumeInput.invalid('Talpa turi būti sveika ml reikšmė.');
  }

  final kept = fraction.length > decimals ? fraction.substring(0, decimals) : fraction;
  final fractionMl = decimals == 0 ? 0 : int.parse(kept.padRight(decimals, '0'));
  final ml = whole * (unit == VolumeUnit.l ? 1000 : 1) + fractionMl;

  if (ml < minVolumeMl || ml > maxVolumeMl) {
    return const VolumeInput.invalid('Talpa turi būti nuo 1 iki 50 000 ml (50 l).');
  }
  return VolumeInput.valid(ml);
}

/// Server limits for a product's name, after trimming.
const int minProductNameLength = 2;
const int maxProductNameLength = 150;

/// Result of checking the name field: either the trimmed [name] or a Lithuanian [error].
class NameInput {
  const NameInput.valid(String this.name) : error = null;

  const NameInput.invalid(String this.error) : name = null;

  final String? name;
  final String? error;
}

NameInput checkProductName(String raw) {
  final name = raw.trim();
  if (name.isEmpty) {
    return const NameInput.invalid('Įveskite pavadinimą.');
  }
  if (name.length < minProductNameLength || name.length > maxProductNameLength) {
    return const NameInput.invalid('Pavadinimas turi būti 2–150 simbolių.');
  }
  return NameInput.valid(name);
}
