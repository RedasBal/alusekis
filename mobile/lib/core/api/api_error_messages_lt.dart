/// User-facing Lithuanian texts for API failures. They never contain technical
/// details such as status codes, server messages or request ids.
library;

const String messageForTimeout =
    'Serveris neatsakė laiku. Bandykite dar kartą.';

const String messageForNetwork =
    'Nepavyko prisijungti prie serverio. Patikrinkite interneto ryšį.';

const String messageForUnknown =
    'Įvyko netikėta klaida. Bandykite vėliau.';

const Map<String, String> _messagesByCode = {
  'bad_request': 'Užklausa netinkama. Patikrinkite įvestus duomenis.',
  'validation_failed':
      'Įvesti duomenys netinkami. Patikrinkite juos ir bandykite dar kartą.',
  'unauthorized': 'Reikia prisijungti.',
  'forbidden': 'Neturite teisės atlikti šio veiksmo.',
  'not_found': 'Nieko nerasta.',
  'method_not_allowed': messageForUnknown,
  'conflict': 'Toks įrašas jau yra.',
  'payload_too_large': 'Siunčiama per daug duomenų.',
  'unsupported_media_type': messageForUnknown,
  'too_many_requests':
      'Per daug bandymų. Palaukite keliolika minučių ir bandykite dar kartą.',
  'internal_error': messageForUnknown,
  'service_unavailable':
      'Paslauga laikinai nepasiekiama. Bandykite vėliau.',
  'request_timeout': messageForTimeout,

  // Paskyra.
  'email_invalid': 'Neteisingas el. pašto adresas.',
  'email_taken': 'Šis el. paštas jau užregistruotas.',
  'password_length_invalid': 'Slaptažodis turi būti 12–128 simbolių.',
  'invalid_credentials': 'Neteisingas el. paštas arba slaptažodis.',
  'invalid_password': 'Neteisingas slaptažodis.',
  'invalid_reset_token':
      'Atkūrimo kodas neteisingas, nebegalioja arba jau panaudotas.',

  // Kainų pateikimas.
  'price_invalid': 'Kaina turi būti nuo 0,01 iki 500,00 €.',
  'large_price_change': 'Kaina labai skiriasi nuo ankstesnės.',
  'idempotency_key_reused':
      'Šis pateikimas jau buvo išsiųstas su kita kaina. Bandykite dar kartą.',
};

/// Picks a message by the server error [code]; falls back to the HTTP
/// [statusCode] when the body was not the standard error DTO.
String messageForServerError({String? code, int? statusCode}) {
  final byCode = code == null ? null : _messagesByCode[code];
  if (byCode != null) {
    return byCode;
  }
  return switch (statusCode) {
    400 => _messagesByCode['bad_request']!,
    401 => _messagesByCode['unauthorized']!,
    403 => _messagesByCode['forbidden']!,
    404 => _messagesByCode['not_found']!,
    409 => _messagesByCode['conflict']!,
    422 => _messagesByCode['validation_failed']!,
    429 => _messagesByCode['too_many_requests']!,
    503 => _messagesByCode['service_unavailable']!,
    504 => messageForTimeout,
    _ => messageForUnknown,
  };
}
