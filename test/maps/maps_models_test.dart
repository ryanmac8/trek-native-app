import 'package:flutter_test/flutter_test.dart';
import 'package:trek/maps/maps_models.dart';

void main() {
  group('LatLng', () {
    test('round-trips through JSON', () {
      const point = LatLng(48.8566, 2.3522);
      expect(LatLng.fromJson(point.toJson()), point);
    });

    test('cacheKey rounds to 5 decimal places', () {
      const a = LatLng(48.856601, 2.352202);
      const b = LatLng(48.856604, 2.352204);
      expect(a.cacheKey, b.cacheKey);
    });

    test('cacheKey differs for coordinates further apart', () {
      const a = LatLng(48.8566, 2.3522);
      const b = LatLng(48.8600, 2.3522);
      expect(a.cacheKey, isNot(b.cacheKey));
    });
  });

  group('ReverseGeocodeResult', () {
    test('parses a full answer from JSON', () {
      final result = ReverseGeocodeResult.fromJson({
        'name': 'Eiffel Tower',
        'address': 'Champ de Mars, 5 Avenue Anatole France, Paris, France',
      });
      expect(result.name, 'Eiffel Tower');
      expect(result.address, isNotNull);
      expect(result.isEmpty, isFalse);
    });

    test('an all-null answer is empty', () {
      final result = ReverseGeocodeResult.fromJson({
        'name': null,
        'address': null,
      });
      expect(result.isEmpty, isTrue);
    });

    test('round-trips through JSON', () {
      const result = ReverseGeocodeResult(
        name: 'Eiffel Tower',
        address: 'Paris, France',
      );
      final decoded = ReverseGeocodeResult.fromJson(result.toJson());
      expect(decoded.name, result.name);
      expect(decoded.address, result.address);
    });
  });

  group('ResolvedPlace', () {
    test('parses the resolve-url response shape', () {
      final place = ResolvedPlace.fromJson({
        'lat': 48.8584,
        'lng': 2.2945,
        'name': 'Eiffel Tower',
        'address': 'Paris, France',
        'google_ftid': '0x47e66e2964e34e2d:0x8ddca9ee380ef7e0',
      });
      expect(place.point, const LatLng(48.8584, 2.2945));
      expect(place.name, 'Eiffel Tower');
      expect(place.googleFtid, isNotNull);
    });

    test('round-trips through JSON, omitting a null google_ftid', () {
      const place = ResolvedPlace(
        point: LatLng(48.8584, 2.2945),
        name: 'Eiffel Tower',
        address: 'Paris, France',
      );
      final json = place.toJson();
      expect(json.containsKey('google_ftid'), isFalse);

      final decoded = ResolvedPlace.fromJson(json);
      expect(decoded.point, place.point);
      expect(decoded.name, place.name);
      expect(decoded.address, place.address);
      expect(decoded.googleFtid, isNull);
    });
  });
}
