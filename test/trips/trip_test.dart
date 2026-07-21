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

    test('a server-fetched trip is never pending', () {
      final trip = Trip.fromJson({'id': 20, 'title': 'New Zealand'});

      expect(trip.isPending, isFalse);
    });
  });

  group('Trip.isPending', () {
    test('a locally-created trip with no server id is pending', () {
      const trip = Trip(localId: 'local-1', title: 'Draft trip');

      expect(trip.isPending, isTrue);
    });
  });

  group('Trip cache round-trip', () {
    test('toCacheJson then fromCacheJson preserves a synced trip', () {
      final trip = Trip.fromJson({
        'id': 20,
        'title': 'New Zealand',
        'description': 'ATL to Auckland',
        'start_date': '2026-11-28',
        'end_date': '2026-12-13',
        'currency': 'USD',
        'day_count': 16,
        'place_count': 17,
      });

      final restored = Trip.fromCacheJson(trip.toCacheJson());

      expect(restored.id, trip.id);
      expect(restored.localId, trip.localId);
      expect(restored.title, trip.title);
      expect(restored.description, trip.description);
      expect(restored.startDate, trip.startDate);
      expect(restored.endDate, trip.endDate);
      expect(restored.currency, trip.currency);
      expect(restored.dayCount, trip.dayCount);
      expect(restored.placeCount, trip.placeCount);
      expect(restored.isPending, isFalse);
    });

    test('toCacheJson then fromCacheJson preserves a pending trip', () {
      const trip = Trip(localId: 'local-1', title: 'Draft trip');

      final restored = Trip.fromCacheJson(trip.toCacheJson());

      expect(restored.id, isNull);
      expect(restored.localId, 'local-1');
      expect(restored.isPending, isTrue);
    });
  });
}
