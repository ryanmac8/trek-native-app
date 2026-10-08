import 'package:flutter_test/flutter_test.dart';
import 'package:trek/design/formats/trek_date_range.dart';

void main() {
  group('spanDays', () {
    test('counts both ends', () {
      expect(
        TrekDateRange(
          start: DateTime(2026, 3, 1),
          end: DateTime(2026, 3, 1),
        ).spanDays,
        1,
      );
      expect(
        TrekDateRange(
          start: DateTime(2026, 3, 1),
          end: DateTime(2026, 3, 7),
        ).spanDays,
        7,
      );
    });

    test('is calendar-based across a month and leap day', () {
      expect(
        TrekDateRange.spanBetween(DateTime(2028, 2, 27), DateTime(2028, 3, 1)),
        4,
      );
    });

    test('is zero or negative when the end is before the start', () {
      expect(
        TrekDateRange.spanBetween(DateTime(2026, 3, 2), DateTime(2026, 3, 1)),
        0,
      );
    });

    test('is null unless both days are set', () {
      expect(TrekDateRange(start: DateTime(2026, 3, 1)).spanDays, isNull);
      expect(TrekDateRange.empty.spanDays, isNull);
    });
  });

  group('withStart', () {
    test('sets the end to the start when there was no end', () {
      expect(
        TrekDateRange.empty.withStart(DateTime(2026, 5, 10)),
        TrekDateRange(start: DateTime(2026, 5, 10), end: DateTime(2026, 5, 10)),
      );
    });

    test('moves the end along so the trip keeps its length', () {
      final range = TrekDateRange(
        start: DateTime(2026, 5, 10),
        end: DateTime(2026, 5, 14),
      );
      expect(
        range.withStart(DateTime(2026, 5, 12)),
        TrekDateRange(start: DateTime(2026, 5, 12), end: DateTime(2026, 5, 16)),
      );
      expect(
        range.withStart(DateTime(2026, 5, 1)),
        TrekDateRange(start: DateTime(2026, 5, 1), end: DateTime(2026, 5, 5)),
      );
    });

    test('collapses to one day when the start moves past the end', () {
      final range = TrekDateRange(
        start: DateTime(2026, 5, 10),
        end: DateTime(2026, 5, 14),
      );
      expect(
        range.withStart(DateTime(2026, 5, 30)),
        TrekDateRange(start: DateTime(2026, 5, 30), end: DateTime(2026, 5, 30)),
      );
    });

    test('keeps the length across a DST change', () {
      // 29 March 2026 is a DST switch in much of Europe.
      final range = TrekDateRange(
        start: DateTime(2026, 3, 20),
        end: DateTime(2026, 3, 27),
      );
      expect(
        range.withStart(DateTime(2026, 3, 25)),
        TrekDateRange(start: DateTime(2026, 3, 25), end: DateTime(2026, 4, 1)),
      );
    });

    test('with only an end set, keeps it unless the start passes it', () {
      final endOnly = TrekDateRange(end: DateTime(2026, 5, 20));
      expect(
        endOnly.withStart(DateTime(2026, 5, 12)),
        TrekDateRange(start: DateTime(2026, 5, 12), end: DateTime(2026, 5, 20)),
      );
      expect(
        endOnly.withStart(DateTime(2026, 5, 25)),
        TrekDateRange(start: DateTime(2026, 5, 25), end: DateTime(2026, 5, 25)),
      );
    });

    test('clearing the start leaves the end alone', () {
      final range = TrekDateRange(
        start: DateTime(2026, 5, 10),
        end: DateTime(2026, 5, 14),
      );
      expect(range.withStart(null), TrekDateRange(end: DateTime(2026, 5, 14)));
    });

    test('drops the time of day', () {
      expect(
        TrekDateRange.empty.withStart(DateTime(2026, 5, 10, 15, 30)).start,
        DateTime(2026, 5, 10),
      );
    });
  });

  test('withEnd keeps the start and can clear the end', () {
    final range = TrekDateRange(
      start: DateTime(2026, 5, 10),
      end: DateTime(2026, 5, 14),
    );
    expect(range.withEnd(DateTime(2026, 5, 20)).end, DateTime(2026, 5, 20));
    expect(range.withEnd(DateTime(2026, 5, 20)).start, DateTime(2026, 5, 10));
    expect(range.withEnd(null), TrekDateRange(start: DateTime(2026, 5, 10)));
  });

  group('validate', () {
    test('accepts a same-day or partial range', () {
      expect(
        TrekDateRange(
          start: DateTime(2026, 5, 10),
          end: DateTime(2026, 5, 10),
        ).validate(),
        isNull,
      );
      expect(TrekDateRange(start: DateTime(2026, 5, 10)).validate(), isNull);
      expect(TrekDateRange.empty.validate(), isNull);
    });

    test('rejects an end before the start with the server message', () {
      expect(
        TrekDateRange(
          start: DateTime(2026, 5, 10),
          end: DateTime(2026, 5, 9),
        ).validate(),
        'End date must be after start date',
      );
    });

    test('enforces the 999-day trip limit by default', () {
      final start = DateTime(2026, 1, 1);
      expect(
        TrekDateRange(start: start, end: DateTime(2026, 1, 999)).validate(),
        isNull,
      );
      expect(
        TrekDateRange(start: start, end: DateTime(2026, 1, 1000)).validate(),
        'A trip can span at most 999 days',
      );
    });

    test('takes a custom limit, or none', () {
      final range = TrekDateRange(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 10),
      );
      expect(range.validate(maxDays: 7), 'A trip can span at most 7 days');
      expect(
        TrekDateRange(
          start: DateTime(2026, 1, 1),
          end: DateTime(2030, 1, 1),
        ).validate(maxDays: null),
        isNull,
      );
    });
  });
}
