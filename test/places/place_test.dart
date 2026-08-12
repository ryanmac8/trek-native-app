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
}
