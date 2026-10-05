import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/design/formats/trek_date_time.dart';

void main() {
  group('dates', () {
    test('formats as zero-padded YYYY-MM-DD', () {
      expect(TrekDateTime.formatDate(DateTime(2026, 3, 7)), '2026-03-07');
      expect(
        TrekDateTime.formatDate(DateTime(2026, 12, 31, 23, 59)),
        '2026-12-31',
      );
    });

    test('parses YYYY-MM-DD to local midnight', () {
      expect(TrekDateTime.parseDate('2026-03-07'), DateTime(2026, 3, 7));
      expect(TrekDateTime.parseDate(' 2026-03-07 '), DateTime(2026, 3, 7));
    });

    test('rejects malformed and impossible dates', () {
      for (final value in [
        null,
        '',
        '2026-3-7',
        '07/03/2026',
        '2026-03-07T10:00',
        '2026-02-30',
        '2026-13-01',
      ]) {
        expect(TrekDateTime.parseDate(value), isNull, reason: '$value');
      }
    });

    test('round-trips', () {
      final date = DateTime(2024, 2, 29);
      expect(TrekDateTime.parseDate(TrekDateTime.formatDate(date)), date);
    });
  });

  group('times', () {
    test('formats as 24-hour zero-padded HH:MM', () {
      expect(
        TrekDateTime.formatTime(const TimeOfDay(hour: 9, minute: 5)),
        '09:05',
      );
      expect(
        TrekDateTime.formatTime(const TimeOfDay(hour: 23, minute: 30)),
        '23:30',
      );
    });

    test('parses bare HH:MM, ignoring seconds', () {
      expect(
        TrekDateTime.parseTime('14:30'),
        const TimeOfDay(hour: 14, minute: 30),
      );
      expect(
        TrekDateTime.parseTime('07:00:00'),
        const TimeOfDay(hour: 7, minute: 0),
      );
    });

    test('parses the time part of a local ISO datetime', () {
      expect(
        TrekDateTime.parseTime('2026-03-07T18:45'),
        const TimeOfDay(hour: 18, minute: 45),
      );
    });

    test('rejects malformed and out-of-range times', () {
      for (final value in [null, '', '9:05', '24:00', '12:60', 'noon']) {
        expect(TrekDateTime.parseTime(value), isNull, reason: '$value');
      }
    });
  });
}
