import 'package:flutter_test/flutter_test.dart';
import 'package:trek/reservations/reservation.dart';

void main() {
  group('Reservation.fromJson', () {
    test('parses the real list-endpoint shape, including joined fields', () {
      final reservation = Reservation.fromJson({
        'id': 12,
        'trip_id': 20,
        'day_id': 90,
        'title': 'Air NZ NZ201 AKL → ZQN',
        'type': 'flight',
        'status': 'confirmed',
        'reservation_time': '2026-03-04 07:30',
        'reservation_end_time': '2026-03-04 09:15',
        'location': 'Auckland Airport',
        'confirmation_number': 'ABC123',
        'notes': 'Window seat',
        'url': 'https://airnz.example/booking/ABC123',
        'created_at': '2026-01-02 10:00:00',
        'day_number': 3,
        'place_name': 'Auckland Airport',
      });

      expect(reservation.id, 12);
      expect(reservation.tripId, 20);
      expect(reservation.dayId, 90);
      expect(reservation.title, 'Air NZ NZ201 AKL → ZQN');
      expect(reservation.type, 'flight');
      expect(reservation.status, 'confirmed');
      expect(reservation.reservationTime, '2026-03-04 07:30');
      expect(reservation.reservationEndTime, '2026-03-04 09:15');
      expect(reservation.location, 'Auckland Airport');
      expect(reservation.confirmationNumber, 'ABC123');
      expect(reservation.notes, 'Window seat');
      expect(reservation.url, 'https://airnz.example/booking/ABC123');
      expect(reservation.dayNumber, 3);
      expect(reservation.placeName, 'Auckland Airport');
    });

    test('type and status fall back to the server column defaults', () {
      final reservation = Reservation.fromJson({
        'id': 1,
        'trip_id': 20,
        'title': 'Dinner somewhere',
      });

      expect(reservation.type, 'other');
      expect(reservation.status, 'pending');
    });

    test(
      'optional fields are null when absent, and for an unpinned booking',
      () {
        final reservation = Reservation.fromJson({
          'id': 1,
          'trip_id': 20,
          'title': 'Museum tour',
          'type': 'activity',
          'status': 'pending',
        });

        expect(reservation.reservationTime, isNull);
        expect(reservation.location, isNull);
        expect(reservation.confirmationNumber, isNull);
        expect(reservation.dayId, isNull);
        expect(reservation.dayNumber, isNull);
        expect(reservation.placeName, isNull);
      },
    );
  });

  group('cache round-trip', () {
    test('toCacheJson/fromCacheJson preserves every modeled field', () {
      const reservation = Reservation(
        id: 12,
        tripId: 20,
        title: 'Ferry to Waiheke',
        type: 'ferry',
        status: 'confirmed',
        reservationTime: '2026-03-06 10:00',
        reservationEndTime: '2026-03-06 10:40',
        location: 'Pier 2, Auckland',
        confirmationNumber: 'FBRY-9',
        notes: 'Arrive 20 min early',
        url: 'https://fullers.example/FBRY-9',
        dayId: 92,
        dayNumber: 5,
        placeName: 'Auckland Ferry Terminal',
      );

      final restored = Reservation.fromCacheJson(reservation.toCacheJson());

      expect(restored.id, reservation.id);
      expect(restored.tripId, reservation.tripId);
      expect(restored.title, reservation.title);
      expect(restored.type, reservation.type);
      expect(restored.status, reservation.status);
      expect(restored.reservationTime, reservation.reservationTime);
      expect(restored.reservationEndTime, reservation.reservationEndTime);
      expect(restored.location, reservation.location);
      expect(restored.confirmationNumber, reservation.confirmationNumber);
      expect(restored.notes, reservation.notes);
      expect(restored.url, reservation.url);
      expect(restored.dayId, reservation.dayId);
      expect(restored.dayNumber, reservation.dayNumber);
      expect(restored.placeName, reservation.placeName);
    });

    test('a timeless, unpinned booking round-trips with nulls intact', () {
      const reservation = Reservation(
        id: 3,
        tripId: 20,
        title: 'Pick up rental car',
        type: 'car',
      );

      final restored = Reservation.fromCacheJson(reservation.toCacheJson());

      expect(restored.reservationTime, isNull);
      expect(restored.dayId, isNull);
      expect(restored.status, 'pending');
    });
  });
}
