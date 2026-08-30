import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/transit/transit_api.dart';
import 'package:trek/transit/transit_models.dart';
import 'package:trek/transit/transit_repository.dart';

import '../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

http.Client _offline() =>
    MockClient((_) async => throw http.ClientException('offline'));

TransitRepository _repository({
  required http.Client httpClient,
  InMemoryTransitLocalStore? localStore,
}) {
  return TransitRepository(
    transitApi: TransitApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: httpClient,
      ),
    ),
    localStore: localStore ?? InMemoryTransitLocalStore(),
  );
}

Map<String, dynamic> _stopJson(String name) => {
  'name': name,
  'lat': 1.0,
  'lng': 2.0,
  'type': 'STOP',
};

void main() {
  group('searchStops', () {
    test('short queries never touch the network or the cache', () async {
      final repository = _repository(
        httpClient: MockClient((_) async => fail('should not hit the network')),
      );

      expect(await repository.searchStops('a'), isEmpty);
    });

    test('fetches, then writes the result to the cache', () async {
      final store = InMemoryTransitLocalStore();
      final repository = _repository(
        httpClient: MockClient(
          (_) async => _json({
            'results': [_stopJson('Wellington Station')],
          }),
        ),
        localStore: store,
      );

      final results = await repository.searchStops('  Wellington  ');

      expect(results.single.name, 'Wellington Station');
      // Normalised key: trimmed + lower-cased.
      expect(store.stops['wellington']?.single.name, 'Wellington Station');
    });

    test(
      'falls back to the cached result for the same query when offline',
      () async {
        final store = InMemoryTransitLocalStore()
          ..stops['wellington'] = const [
            TransitPlace(name: 'Cached Station', lat: 1, lng: 2),
          ];
        final repository = _repository(
          httpClient: _offline(),
          localStore: store,
        );

        final results = await repository.searchStops('Wellington');

        expect(results.single.name, 'Cached Station');
      },
    );

    test('rethrows NetworkException when nothing is cached', () async {
      final repository = _repository(httpClient: _offline());

      expect(
        repository.searchStops('Wellington'),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('planRoute', () {
    const query = TransitPlanQuery(from: '1,2', to: '3,4');

    test('fetches and caches by the query cache key', () async {
      final store = InMemoryTransitLocalStore();
      final repository = _repository(
        httpClient: MockClient(
          (_) async => _json({
            'itineraries': [
              {
                'startTime': 'a',
                'endTime': 'b',
                'duration': 600,
                'transfers': 0,
                'walkSeconds': 0,
                'legs': const [],
              },
            ],
          }),
        ),
        localStore: store,
      );

      final itineraries = await repository.planRoute(query);

      expect(itineraries, hasLength(1));
      expect(store.plans[query.cacheKey], hasLength(1));
    });

    test('serves the cached plan on NetworkException', () async {
      final store = InMemoryTransitLocalStore()
        ..plans[query.cacheKey] = const [
          TransitItinerary(startTime: 'a', endTime: 'b', duration: 900),
        ];
      final repository = _repository(httpClient: _offline(), localStore: store);

      final itineraries = await repository.planRoute(query);

      expect(itineraries.single.duration, 900);
    });

    test('rethrows NetworkException with no cached plan', () async {
      final repository = _repository(httpClient: _offline());

      expect(repository.planRoute(query), throwsA(isA<NetworkException>()));
    });
  });

  group('searchAirports', () {
    test('fetches and caches; empty query is a no-op', () async {
      final store = InMemoryTransitLocalStore();
      final repository = _repository(
        httpClient: MockClient(
          (_) async => _json([
            {
              'iata': 'AKL',
              'name': 'Auckland',
              'city': 'Auckland',
              'country': 'NZ',
              'lat': 1.0,
              'lng': 2.0,
              'tz': 'Pacific/Auckland',
            },
          ]),
        ),
        localStore: store,
      );

      expect(await repository.searchAirports('   '), isEmpty);

      final results = await repository.searchAirports('AKL');
      expect(results.single.iata, 'AKL');
      expect(store.airports['akl'], hasLength(1));
    });

    test('falls back to the cached airports when offline', () async {
      final store = InMemoryTransitLocalStore()
        ..airports['akl'] = const [
          Airport(
            iata: 'AKL',
            name: 'Auckland',
            city: 'Auckland',
            country: 'NZ',
            lat: 1,
            lng: 2,
            tz: 'Pacific/Auckland',
          ),
        ];
      final repository = _repository(httpClient: _offline(), localStore: store);

      expect((await repository.searchAirports('AKL')).single.iata, 'AKL');
    });
  });

  group('cached reads', () {
    test('return null before anything has been fetched', () async {
      final repository = _repository(
        httpClient: MockClient((_) async => fail('no network')),
      );

      expect(await repository.cachedStops('Wellington'), isNull);
      expect(
        await repository.cachedRoute(
          const TransitPlanQuery(from: '1,2', to: '3,4'),
        ),
        isNull,
      );
      expect(await repository.cachedAirports('AKL'), isNull);
    });
  });
}
