import '../api/api_error.dart';
import '../api/api_error_messages_lt.dart';

/// Form fields a server error can belong to.
enum AuthField { email, password, token }

/// Which field a server error [code] is about, or null for a general error.
AuthField? fieldForErrorCode(String? code) => switch (code) {
      'email_invalid' || 'email_taken' => AuthField.email,
      'password_length_invalid' || 'invalid_password' => AuthField.password,
      'invalid_reset_token' => AuthField.token,
      _ => null,
    };

/// A failed form submission: shown next to [field] when there is one on the
/// screen, otherwise as a general message. The text is always Lithuanian and
/// free of technical detail.
class FormFailure {
  const FormFailure({required this.message, this.field});

  /// [fields] are the fields the current screen actually has.
  factory FormFailure.from(Object error, Set<AuthField> fields) {
    if (error is ApiException) {
      final field = fieldForErrorCode(error.error.code);
      return FormFailure(
        message: error.userMessage,
        field: field != null && fields.contains(field) ? field : null,
      );
    }
    return const FormFailure(message: messageForUnknown);
  }

  final String message;
  final AuthField? field;

  String? errorFor(AuthField target) => field == target ? message : null;

  /// Message for the banner above the form; null when it belongs to a field.
  String? get general => field == null ? message : null;
}
