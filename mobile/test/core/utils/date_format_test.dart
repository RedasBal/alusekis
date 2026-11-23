import 'package:alusekis/core/utils/date_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDateTime', () {
    test('uses UTC+2 in winter', () {
      expect(formatDateTime(DateTime.utc(2026, 1, 15, 10, 30)),
          '2026-01-15 12:30');
    });

    test('uses UTC+3 in summer', () {
      expect(formatDateTime(DateTime.utc(2026, 7, 15, 10, 30)),
          '2026-07-15 13:30');
    });

    test('rolls over to the next day after midnight Vilnius time', () {
      expect(formatDateTime(DateTime.utc(2026, 12, 31, 22, 5)),
          '2027-01-01 00:05');
    });

    test('handles the daylight saving switch (2026-03-29 and 2026-10-25)', () {
      // 01:00 UTC on 2026-03-29 is 04:00 EEST (clocks moved 03:00 -> 04:00).
      expect(formatDateTime(DateTime.utc(2026, 3, 29, 1, 0)),
          '2026-03-29 04:00');
      expect(formatDateTime(DateTime.utc(2026, 3, 29, 0, 59)),
          '2026-03-29 02:59');
      // 01:00 UTC on 2026-10-25 is 03:00 EET (clocks moved 04:00 -> 03:00).
      expect(formatDateTime(DateTime.utc(2026, 10, 25, 1, 0)),
          '2026-10-25 03:00');
    });

    test('zero-pads fields', () {
      expect(formatDateTime(DateTime.utc(2026, 2, 3, 4, 5)),
          '2026-02-03 06:05');
    });

    test('rejects non-UTC values', () {
      expect(() => formatDateTime(DateTime(2026, 1, 1)), throwsArgumentError);
    });
  });

  group('server date time', () {
    test('parses ISO 8601 with Z as UTC', () {
      final parsed = parseServerDateTime('2026-11-23T09:37:29.9521625Z');
      expect(parsed.isUtc, isTrue);
      expect(parsed.hour, 9);
    });

    test('treats values without offset as UTC', () {
      final parsed = parseServerDateTime('2026-11-23T09:37:29');
      expect(parsed.isUtc, isTrue);
      expect(parsed.hour, 9);
    });

    test('serializes with Z suffix', () {
      expect(toServerDateTime(DateTime.utc(2026, 11, 23, 9, 37, 29)),
          '2026-11-23T09:37:29.000Z');
    });
  });
}
