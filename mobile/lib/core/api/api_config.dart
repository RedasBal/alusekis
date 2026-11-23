/// Server base URL. Override without code changes:
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:5000`.
///
/// The default `10.0.2.2` is how the Android emulator reaches the host machine.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:5000',
);

/// Path prefix of all versioned endpoints.
const String apiPrefix = '/api/v1';

/// Applies to connecting, sending and receiving.
const Duration apiTimeout = Duration(seconds: 10);
