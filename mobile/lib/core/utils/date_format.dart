import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

bool _timeZonesReady = false;

tz.Location _vilnius() {
  if (!_timeZonesReady) {
    tz_data.initializeTimeZones();
    _timeZonesReady = true;
  }
  return tz.getLocation('Europe/Vilnius');
}

/// Formats a UTC instant as `YYYY-MM-DD HH:mm` in Europe/Vilnius time,
/// independent of the device time zone.
///
/// [utc] must be a UTC value (as parsed from the server ISO 8601 strings).
String formatDateTime(DateTime utc) {
  if (!utc.isUtc) {
    throw ArgumentError.value(utc, 'utc', 'must be a UTC DateTime');
  }
  final t = tz.TZDateTime.from(utc, _vilnius());
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

/// Parses a server ISO 8601 timestamp (e.g. `2026-11-23T09:37:29.95Z`) into a
/// UTC [DateTime]. Values without an offset are treated as UTC.
DateTime parseServerDateTime(String iso8601) {
  final parsed = DateTime.parse(iso8601);
  return parsed.isUtc
      ? parsed
      : DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour,
          parsed.minute, parsed.second, parsed.millisecond, parsed.microsecond);
}

/// Serializes [utc] for the server as ISO 8601 with a `Z` suffix.
String toServerDateTime(DateTime utc) {
  if (!utc.isUtc) {
    throw ArgumentError.value(utc, 'utc', 'must be a UTC DateTime');
  }
  return utc.toIso8601String();
}
