import 'package:flutter_test/flutter_test.dart';
import 'package:trek/trips/trip.dart';

void main() {
  group('Trip.fromJson', () {
    test('parses the real /api/trips response shape', () {
      final trip = Trip.fromJson({
        'id': 20,
        'user_id': 1,
        'title': 'New Zealand',
        'description': 'ATL to Auckland...',
        'start_date': '2026-11-28',
        'end_date': '2026-12-13',
        'currency': 'USD',
        'cover_image': null,
        'is_archived': 0,
        'day_count': 16,
        'place_count': 17,
        'is_owner': 0,
        'owner_username': 'Ryan',
      });

      expect(trip.id, 20);
      expect(trip.title, 'New Zealand');
      expect(trip.startDate, DateTime(2026, 11, 28));
      expect(trip.endDate, DateTime(2026, 12, 13));
      expect(trip.dayCount, 16);
      expect(trip.placeCount, 17);
    });

    test('defaults counts to 0 and dates to null when absent', () {
      final trip = Trip.fromJson({'id': 1, 'title': 'Minimal Trip'});

      expect(trip.startDate, isNull);
      expect(trip.endDate, isNull);
      expect(trip.dayCount, 0);
      expect(trip.placeCount, 0);
    });
  });
}
