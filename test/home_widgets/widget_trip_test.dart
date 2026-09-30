import 'package:flutter_test/flutter_test.dart';
import 'package:trek/home_widgets/widget_trip.dart';

void main() {
  group('WidgetTrip.fromJson', () {
    test('reads a GET /api/trips row', () {
      final trip = WidgetTrip.fromJson({
        'id': 20,
        'title': ' New Zealand ',
        'start_date': '2026-11-02',
        'end_date': '2026-11-20',
        'day_count': 19,
        'is_owner': 1,
      });
      expect(
        trip,
        const WidgetTrip(
          id: 20,
          title: 'New Zealand',
          startDate: '2026-11-02',
          endDate: '2026-11-20',
        ),
      );
    });

    test('treats missing or malformed dates as undated', () {
      final trip = WidgetTrip.fromJson({
        'id': '7',
        'title': null,
        'start_date': null,
        'end_date': 'soon',
      });
      expect(trip, const WidgetTrip(id: 7, title: ''));
    });

    test('keeps only the date part of a timestamp', () {
      final trip = WidgetTrip.fromJson({
        'id': 1,
        'title': 'x',
        'start_date': '2026-01-05T00:00:00.000Z',
      });
      expect(trip.startDate, '2026-01-05');
    });

    test('round-trips through toJson', () {
      const trip = WidgetTrip(
        id: 3,
        title: 'Lisbon',
        startDate: '2026-10-01',
        endDate: null,
      );
      expect(WidgetTrip.fromJson(trip.toJson()), trip);
    });
  });

  test('formatTrekDate pads to YYYY-MM-DD', () {
    expect(formatTrekDate(DateTime(2026, 3, 7, 23, 59)), '2026-03-07');
  });

  group('nextTripCandidates', () {
    final today = DateTime(2026, 9, 30, 8);

    WidgetTrip trip(int id, String? start, [String? end]) =>
        WidgetTrip(id: id, title: 'Trip $id', startDate: start, endDate: end);

    test('puts a trip running today before upcoming ones', () {
      final result = nextTripCandidates([
        trip(1, '2026-10-10', '2026-10-12'),
        trip(2, '2026-09-28', '2026-10-02'),
        trip(3, '2026-10-05', '2026-10-06'),
      ], today);
      expect(result.map((t) => t.id), [2, 3, 1]);
    });

    test('drops past, undated, and started open-ended trips', () {
      final result = nextTripCandidates([
        trip(1, '2026-09-01', '2026-09-29'),
        trip(2, null),
        trip(3, '2026-09-29'),
        trip(4, '2026-09-30'),
        trip(5, '2026-09-30', '2026-09-30'),
      ], today);
      expect(result.map((t) => t.id), [4, 5]);
    });

    test('breaks ties on start date by id', () {
      final result = nextTripCandidates([
        trip(9, '2026-10-01', '2026-10-03'),
        trip(4, '2026-10-01', '2026-10-02'),
      ], today);
      expect(result.map((t) => t.id), [4, 9]);
    });

    test('caps the list at limit', () {
      final trips = [for (var i = 1; i <= 8; i++) trip(i, '2026-10-0$i')];
      expect(nextTripCandidates(trips, today, limit: 3).map((t) => t.id), [
        1,
        2,
        3,
      ]);
    });

    test('is empty when nothing is ahead', () {
      expect(
        nextTripCandidates([trip(1, '2025-01-01', '2025-01-02')], today),
        isEmpty,
      );
    });
  });
}
