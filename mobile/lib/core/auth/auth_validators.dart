/// Client-side checks that mirror the server rules so most mistakes are caught
/// before a request is sent. The server remains the authority.
library;

const int maxEmailLength = 254;
const int minPasswordLength = 12;
const int maxPasswordLength = 128;

final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

String? validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) {
    return 'Įveskite el. pašto adresą.';
  }
  if (email.length > maxEmailLength) {
    return 'El. paštas negali būti ilgesnis nei $maxEmailLength simbolių.';
  }
  if (!_emailPattern.hasMatch(email)) {
    return 'Neteisingas el. pašto adresas.';
  }
  return null;
}

/// For choosing a new password (register, reset).
String? validateNewPassword(String? value) {
  final password = value ?? '';
  if (password.isEmpty) {
    return 'Įveskite slaptažodį.';
  }
  if (password.length < minPasswordLength ||
      password.length > maxPasswordLength) {
    return 'Slaptažodis turi būti $minPasswordLength–$maxPasswordLength simbolių.';
  }
  return null;
}

/// For entering an existing password (login, delete). Only presence is
/// checked so the form does not reveal the password rules to guessers.
String? validateRequiredPassword(String? value) =>
    (value ?? '').isEmpty ? 'Įveskite slaptažodį.' : null;

/// Accepts either the bare reset token or the whole link from the e-mail
/// (`alusekis://reset-password?token=...`) and returns the token.
String extractResetToken(String input) {
  final text = input.trim();
  if (!text.contains('token=')) {
    return text;
  }
  final uri = Uri.tryParse(text);
  final fromQuery = uri?.queryParameters['token'];
  if (fromQuery != null && fromQuery.isNotEmpty) {
    return fromQuery;
  }
  return text.substring(text.indexOf('token=') + 'token='.length);
}
