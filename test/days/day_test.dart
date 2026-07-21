import 'package:flutter_test/flutter_test.dart';
import 'package:trek/days/day.dart';

void main() {
  group('Day.fromJson', () {
    test('parses the real API shape, deriving assignmentCount from the '
        'nested assignments array', () {
      final day = Day.fromJson({
        'id': 101,
        'trip_id': 20,
        'day_number': 1,
        'date': '2026-11-28',
        'notes': 'Arrival day',
        'title': null,
        'assignments': [
          {'id': 1},
          {'id': 2},
        ],
        'notes_items': [],
      });

      expect(day.id, 101);
      expect(day.tripId, 20);
      expect(day.dayNumber, 1);
      expect(day.date, DateTime.parse('2026-11-28'));
      expect(day.notes, 'Arrival day');
      expect(day.title, isNull);
      expect(day.assignmentCount, 2);
    });

    test('defaults assignmentCount to 0 when assignments is absent', () {
      final day = Day.fromJson({'id': 101, 'trip_id': 20, 'day_number': 1});

      expect(day.assignmentCount, 0);
      expect(day.date, isNull);
    });
  });

  group('cache round-trip', () {
    test('toCacheJson/fromCacheJson preserves every field', () {
      const day = Day(
        id: 101,
        tripId: 20,
        dayNumber: 3,
        date: null,
        notes: 'Rest day',
        title: 'Queenstown',
        assignmentCount: 4,
      );

      final restored = Day.fromCacheJson(day.toCacheJson());

      expect(restored.id, day.id);
      expect(restored.tripId, day.tripId);
      expect(restored.dayNumber, day.dayNumber);
      expect(restored.date, day.date);
      expect(restored.notes, day.notes);
      expect(restored.title, day.title);
      expect(restored.assignmentCount, day.assignmentCount);
    });

    test('round-trips a date correctly', () {
      final day = Day(
        id: 1,
        tripId: 1,
        dayNumber: 1,
        date: DateTime.parse('2026-11-28'),
      );

      final restored = Day.fromCacheJson(day.toCacheJson());

      expect(restored.date, day.date);
    });
  });
}
