import 'package:flutter_test/flutter_test.dart';
import 'package:trek/accommodations/accommodation.dart';

void main() {
  group('Accommodation.fromJson', () {
    test('parses the real list-endpoint shape, including joined fields', () {
      final accommodation = Accommodation.fromJson({
        'id': 7,
        'trip_id': 20,
        'place_id': 501,
        'start_day_id': 90,
        'end_day_id': 93,
        'check_in': '2026-03-04',
        'check_in_end': null,
        'check_out': '2026-03-07',
        'confirmation': 'ABC123',
        'notes': 'Late arrival',
        'created_at': '2026-01-02 10:00:00',
        'place_name': 'Sofitel Queenstown',
        'place_address': '8 Duke St, Queenstown',
        'place_image': 'https://example.com/hotel.jpg',
        'place_lat': -45.03,
        'place_lng': 168.66,
        'reservation_title': 'Sofitel Queenstown',
      });

      expect(accommodation.id, 7);
      expect(accommodation.tripId, 20);
      expect(accommodation.placeId, 501);
      expect(accommodation.placeName, 'Sofitel Queenstown');
      expect(accommodation.placeAddress, '8 Duke St, Queenstown');
      expect(accommodation.startDayId, 90);
      expect(accommodation.endDayId, 93);
      expect(accommodation.checkIn, '2026-03-04');
      expect(accommodation.checkInEnd, isNull);
      expect(accommodation.checkOut, '2026-03-07');
      expect(accommodation.confirmation, 'ABC123');
      expect(accommodation.notes, 'Late arrival');
      expect(accommodation.reservationTitle, 'Sofitel Queenstown');
    });

    test('place_id is null when the linked place was deleted', () {
      final accommodation = Accommodation.fromJson({
        'id': 7,
        'trip_id': 20,
        'place_id': null,
        'start_day_id': 90,
        'end_day_id': 93,
      });

      expect(accommodation.placeId, isNull);
      expect(accommodation.placeName, isNull);
    });

    test('optional string fields default to null when absent', () {
      final accommodation = Accommodation.fromJson({
        'id': 7,
        'trip_id': 20,
        'place_id': 501,
        'start_day_id': 90,
        'end_day_id': 90,
      });

      expect(accommodation.checkIn, isNull);
      expect(accommodation.checkOut, isNull);
      expect(accommodation.confirmation, isNull);
      expect(accommodation.notes, isNull);
      expect(accommodation.reservationTitle, isNull);
    });
  });

  group('cache round-trip', () {
    test('toCacheJson/fromCacheJson preserves every modeled field', () {
      const accommodation = Accommodation(
        id: 7,
        tripId: 20,
        placeId: 501,
        placeName: 'Sofitel Queenstown',
        placeAddress: '8 Duke St, Queenstown',
        startDayId: 90,
        endDayId: 93,
        checkIn: '2026-03-04',
        checkInEnd: '2026-03-05',
        checkOut: '2026-03-07',
        confirmation: 'ABC123',
        notes: 'Late arrival',
        reservationTitle: 'Sofitel Queenstown',
      );

      final restored = Accommodation.fromCacheJson(accommodation.toCacheJson());

      expect(restored.id, accommodation.id);
      expect(restored.tripId, accommodation.tripId);
      expect(restored.placeId, accommodation.placeId);
      expect(restored.placeName, accommodation.placeName);
      expect(restored.placeAddress, accommodation.placeAddress);
      expect(restored.startDayId, accommodation.startDayId);
      expect(restored.endDayId, accommodation.endDayId);
      expect(restored.checkIn, accommodation.checkIn);
      expect(restored.checkInEnd, accommodation.checkInEnd);
      expect(restored.checkOut, accommodation.checkOut);
      expect(restored.confirmation, accommodation.confirmation);
      expect(restored.notes, accommodation.notes);
      expect(restored.reservationTitle, accommodation.reservationTitle);
    });

    test('a deleted-place accommodation round-trips with a null place', () {
      const accommodation = Accommodation(
        id: 7,
        tripId: 20,
        startDayId: 90,
        endDayId: 90,
      );

      final restored = Accommodation.fromCacheJson(accommodation.toCacheJson());

      expect(restored.placeId, isNull);
      expect(restored.placeName, isNull);
    });
  });
}
