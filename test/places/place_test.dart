import 'package:flutter_test/flutter_test.dart';
import 'package:trek/places/place.dart';

void main() {
  group('Place.fromJson', () {
    test('parses the real API shape, including the embedded category', () {
      final place = Place.fromJson({
        'id': 501,
        'trip_id': 20,
        'name': 'Fergburger',
        'description': 'Famous burger joint',
        'category': {
          'id': 2,
          'name': 'Restaurant',
          'color': '#ef4444',
          'icon': '🍽️',
        },
        'price': 15,
        'currency': 'NZD',
        'notes': 'Try the Sweet Bambi',
      });

      expect(place.id, 501);
      expect(place.tripId, 20);
      expect(place.name, 'Fergburger');
      expect(place.category?.id, 2);
      expect(place.category?.name, 'Restaurant');
      expect(place.category?.color, '#ef4444');
      expect(place.category?.icon, '🍽️');
      expect(place.price, 15);
      expect(place.currency, 'NZD');
      expect(place.notes, 'Try the Sweet Bambi');
    });

    test('category is null when the place has no category_id', () {
      final place = Place.fromJson({
        'id': 501,
        'trip_id': 20,
        'name': 'Unsorted spot',
        'category': null,
      });

      expect(place.category, isNull);
    });

    test('price/currency/notes default to null when absent', () {
      final place = Place.fromJson({
        'id': 501,
        'trip_id': 20,
        'name': 'Unsorted spot',
      });

      expect(place.price, isNull);
      expect(place.currency, isNull);
      expect(place.notes, isNull);
    });
  });

  group('cache round-trip', () {
    test(
      'toCacheJson/fromCacheJson preserves every field, including category',
      () {
        const place = Place(
          id: 501,
          tripId: 20,
          name: 'Fergburger',
          category: PlaceCategoryRef(
            id: 2,
            name: 'Restaurant',
            color: '#ef4444',
            icon: '🍽️',
          ),
          price: 15,
          currency: 'NZD',
          notes: 'Try the Sweet Bambi',
        );

        final restored = Place.fromCacheJson(place.toCacheJson());

        expect(restored.id, place.id);
        expect(restored.tripId, place.tripId);
        expect(restored.name, place.name);
        expect(restored.category?.id, place.category?.id);
        expect(restored.category?.name, place.category?.name);
        expect(restored.category?.color, place.category?.color);
        expect(restored.category?.icon, place.category?.icon);
        expect(restored.price, place.price);
        expect(restored.currency, place.currency);
        expect(restored.notes, place.notes);
      },
    );

    test('a null category round-trips as null', () {
      const place = Place(id: 1, tripId: 1, name: 'Unsorted spot');

      final restored = Place.fromCacheJson(place.toCacheJson());

      expect(restored.category, isNull);
    });
  });

  group('Place.applyFields / sync status', () {
    const place = Place(
      id: 501,
      tripId: 20,
      name: 'Fergburger',
      notes: 'Old note',
      price: 18,
      updatedAt: '2026-10-01 10:00:00',
    );

    test('changes only the keys present; explicit null clears', () {
      final updated = place.applyFields({
        'notes': null,
        'address': 'Shotover St',
      });

      expect(updated.name, 'Fergburger');
      expect(updated.price, 18);
      expect(updated.notes, isNull);
      expect(updated.address, 'Shotover St');
      expect(updated.updatedAt, place.updatedAt);
    });

    test('updated_at and sync status round-trip through the cache', () {
      final restored = Place.fromCacheJson(
        place.withSyncStatus(PlaceSyncStatus.conflict).toCacheJson(),
      );

      expect(restored.updatedAt, '2026-10-01 10:00:00');
      expect(restored.syncStatus, PlaceSyncStatus.conflict);
    });

    test('a cache entry without a sync status reads as synced', () {
      final restored = Place.fromCacheJson({
        'id': 1,
        'trip_id': 20,
        'name': 'Cached before sync status existed',
      });

      expect(restored.syncStatus, PlaceSyncStatus.synced);
    });

    test('fromJson reads description, address, and updated_at', () {
      final parsed = Place.fromJson({
        'id': 1,
        'trip_id': 20,
        'name': 'Skyline',
        'description': 'Gondola',
        'address': 'Brecon St',
        'updated_at': '2026-10-01 10:00:00',
      });

      expect(parsed.description, 'Gondola');
      expect(parsed.address, 'Brecon St');
      expect(parsed.updatedAt, '2026-10-01 10:00:00');
      expect(parsed.syncStatus, PlaceSyncStatus.synced);
    });
  });

  group('PlaceInput', () {
    test('toCreateJson trims, upper-cases currency, and drops blanks', () {
      const input = PlaceInput(
        name: '  Fergburger ',
        description: '   ',
        price: 18.5,
        currency: 'nzd',
        notes: '',
      );

      expect(input.toCreateJson(), {
        'name': 'Fergburger',
        'price': 18.5,
        'currency': 'NZD',
      });
    });

    test('changesFrom sends only differing fields, clears as null', () {
      const original = Place(
        id: 501,
        tripId: 20,
        name: 'Fergburger',
        address: 'Shotover St',
        notes: 'Old note',
        price: 18,
        currency: 'NZD',
      );
      const input = PlaceInput(
        name: 'Fergburger',
        address: 'Shotover St',
        notes: '',
        price: 20,
        currency: 'NZD',
      );

      expect(input.changesFrom(original), {'notes': null, 'price': 20.0});
    });

    test('changesFrom is empty when nothing changed', () {
      const original = Place(id: 501, tripId: 20, name: 'Fergburger');

      expect(PlaceInput.fromPlace(original).changesFrom(original), isEmpty);
    });
  });
}
