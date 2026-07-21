import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/trips/trip.dart';
import 'package:trek/trips/trips_api.dart';
import 'package:trek/trips/trips_repository.dart';

import '../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

TripsRepository _repository({
  required http.Client httpClient,
  InMemoryTripsLocalStore? localStore,
}) {
  return TripsRepository(
    tripsApi: TripsApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: httpClient,
      ),
    ),
    localStore: localStore ?? InMemoryTripsLocalStore(),
  );
}

void main() {
  group('cachedTrips', () {
    test(
      'reads straight from the local store without touching the network',
      () async {
        final localStore = InMemoryTripsLocalStore(
          initial: [
            Trip.fromJson({'id': 1, 'title': 'Cached Trip'}),
          ],
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            fail('cachedTrips() should not hit the network');
          }),
          localStore: localStore,
        );

        final trips = await repository.cachedTrips();

        expect(trips, hasLength(1));
        expect(trips.single.title, 'Cached Trip');
      },
    );
  });

  group('refreshTrips', () {
    test(
      'fetches from the network and writes the result to the cache',
      () async {
        final localStore = InMemoryTripsLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({
              'trips': [
                {'id': 1, 'title': 'New Zealand'},
              ],
            }),
          ),
          localStore: localStore,
        );

        final trips = await repository.refreshTrips();

        expect(trips.single.title, 'New Zealand');
        expect((await localStore.read()).single.title, 'New Zealand');
      },
    );

    test(
      'falls back to the cache on NetworkException when trips are cached',
      () async {
        final localStore = InMemoryTripsLocalStore(
          initial: [
            Trip.fromJson({'id': 1, 'title': 'Cached Trip'}),
          ],
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: localStore,
        );

        final trips = await repository.refreshTrips();

        expect(trips.single.title, 'Cached Trip');
      },
    );

    test('rethrows NetworkException when the cache is empty', () async {
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
      );

      expect(repository.refreshTrips(), throwsA(isA<NetworkException>()));
    });

    test('retries a pending offline-created trip and reconciles it', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [const Trip(localId: 'local-1', title: 'Draft trip')],
      );
      var createCalls = 0;
      final repository = _repository(
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            createCalls++;
            return _json({
              'trip': {'id': 42, 'title': 'Draft trip'},
            }, 201);
          }
          return _json({'trips': []});
        }),
        localStore: localStore,
      );

      final trips = await repository.refreshTrips();

      expect(createCalls, 1);
      expect(trips.single.id, 42);
      expect(trips.single.localId, 'local-1');
      expect(trips.single.isPending, isFalse);
    });

    test(
      'leaves a pending trip queued when the retry is still offline',
      () async {
        final localStore = InMemoryTripsLocalStore(
          initial: [const Trip(localId: 'local-1', title: 'Draft trip')],
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: localStore,
        );

        final trips = await repository.refreshTrips();

        expect(trips.single.isPending, isTrue);
        expect(trips.single.localId, 'local-1');
      },
    );
  });

  group('createTrip', () {
    test(
      'writes the trip locally first, then reconciles with the server id',
      () async {
        final localStore = InMemoryTripsLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({
              'trip': {'id': 7, 'title': 'Iceland'},
            }, 201),
          ),
          localStore: localStore,
        );

        final trip = await repository.createTrip(title: 'Iceland');

        expect(trip.id, 7);
        expect(trip.isPending, isFalse);
        final cached = await localStore.read();
        expect(cached, hasLength(1));
        expect(cached.single.id, 7);
      },
    );

    test('stays queued as a pending trip in the cache when offline, instead of '
        'failing or blocking', () async {
      final localStore = InMemoryTripsLocalStore();
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      final trip = await repository.createTrip(title: 'Iceland');

      expect(trip.isPending, isTrue);
      expect(trip.title, 'Iceland');
      final cached = await localStore.read();
      expect(cached, hasLength(1));
      expect(cached.single.isPending, isTrue);
    });

    test(
      'rolls back the optimistic write when the server rejects the request',
      () async {
        final localStore = InMemoryTripsLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({'error': 'Title is required'}, 400),
          ),
          localStore: localStore,
        );

        await expectLater(
          repository.createTrip(title: ''),
          throwsA(isA<ValidationException>()),
        );
        expect(await localStore.read(), isEmpty);
      },
    );
  });
}
