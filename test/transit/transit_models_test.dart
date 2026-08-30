import 'package:flutter_test/flutter_test.dart';
import 'package:trek/transit/transit_models.dart';

void main() {
  group('TransitPlace', () {
    test('parses a geocode result and exposes a "lat,lng" coordinate', () {
      final place = TransitPlace.fromJson(const {
        'name': 'Wellington Station',
        'lat': -41.2789,
        'lng': 174.7802,
        'type': 'STOP',
        'area': 'Wellington',
      });

      expect(place.name, 'Wellington Station');
      expect(place.type, 'STOP');
      expect(place.area, 'Wellington');
      expect(place.coordinate, '-41.2789,174.7802');
    });

    test('tolerates a missing area and string coordinates', () {
      final place = TransitPlace.fromJson(const {
        'name': 'Somewhere',
        'lat': '1.5',
        'lng': '2.5',
      });

      expect(place.area, isNull);
      expect(place.type, 'PLACE');
      expect(place.coordinate, '1.5,2.5');
    });

    test('round-trips through toJson', () {
      const original = TransitPlace(
        name: 'Aro Valley',
        lat: -41.29,
        lng: 174.76,
        type: 'ADDRESS',
        area: 'Wellington',
      );

      final restored = TransitPlace.fromJson(original.toJson());

      expect(restored.name, original.name);
      expect(restored.lat, original.lat);
      expect(restored.type, original.type);
      expect(restored.area, original.area);
    });
  });

  group('TransitItinerary', () {
    final json = {
      'startTime': '2026-08-30T08:00:00.000Z',
      'endTime': '2026-08-30T08:45:00.000Z',
      'duration': 2700,
      'transfers': 1,
      'walkSeconds': 360,
      'legs': [
        {
          'mode': 'walk',
          'from': {'name': 'Home'},
          'to': {'name': 'Stop A'},
          'duration': 300,
        },
        {
          'mode': 'BUS',
          'from': {'name': 'Stop A', 'lat': 1.0, 'lon': 2.0},
          'to': {'name': 'Stop B'},
          'duration': 1200,
          'line': '3',
          'intermediateStops': 4,
        },
      ],
    };

    test('parses the journey and its legs', () {
      final itinerary = TransitItinerary.fromJson(json);

      expect(itinerary.duration, 2700);
      expect(itinerary.transfers, 1);
      expect(itinerary.walkSeconds, 360);
      expect(itinerary.legs, hasLength(2));
      expect(itinerary.legs.first.mode, 'WALK');
      expect(itinerary.legs.first.isWalk, isTrue);
      expect(itinerary.legs[1].line, '3');
      expect(itinerary.legs[1].intermediateStops, 4);
    });

    test('transitLegs excludes walk legs', () {
      final itinerary = TransitItinerary.fromJson(json);

      expect(itinerary.transitLegs.map((l) => l.mode), ['BUS']);
    });

    test('round-trips through toJson for the local cache', () {
      final restored = TransitItinerary.fromJson(
        TransitItinerary.fromJson(json).toJson(),
      );

      expect(restored.legs, hasLength(2));
      expect(restored.transitLegs.single.line, '3');
    });
  });

  group('Airport', () {
    test('parses an airport record with a null icao', () {
      final airport = Airport.fromJson(const {
        'iata': 'WLG',
        'icao': null,
        'name': 'Wellington International Airport',
        'city': 'Wellington',
        'country': 'New Zealand',
        'lat': -41.3272,
        'lng': 174.8053,
        'tz': 'Pacific/Auckland',
      });

      expect(airport.iata, 'WLG');
      expect(airport.icao, isNull);
      expect(airport.city, 'Wellington');
      expect(airport.tz, 'Pacific/Auckland');
    });
  });

  group('TransitPlanQuery', () {
    test('builds query params, omitting "leave now" and empty filters', () {
      const query = TransitPlanQuery(from: '1,2', to: '3,4');

      expect(query.toQueryParameters(), {'from': '1,2', 'to': '3,4'});
    });

    test('includes time, arriveBy, modes and maxTransfers when set', () {
      final query = TransitPlanQuery(
        from: '1,2',
        to: '3,4',
        departAt: DateTime.utc(2026, 8, 30, 9),
        arriveBy: true,
        modes: const ['RAIL', 'BUS'],
        maxTransfers: 2,
      );

      final params = query.toQueryParameters();
      expect(params['time'], '2026-08-30T09:00:00.000Z');
      expect(params['arriveBy'], 'true');
      expect(params['modes'], 'RAIL,BUS');
      expect(params['maxTransfers'], '2');
    });

    test('cacheKey is stable regardless of mode ordering', () {
      const a = TransitPlanQuery(
        from: '1,2',
        to: '3,4',
        modes: ['BUS', 'RAIL'],
      );
      const b = TransitPlanQuery(
        from: '1,2',
        to: '3,4',
        modes: ['RAIL', 'BUS'],
      );

      expect(a.cacheKey, b.cacheKey);
    });
  });
}
