import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/places/place.dart';
import 'package:trek/places/places_api.dart';
import 'package:trek/places/places_repository.dart';

import '../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

PlacesRepository _repository({
  required http.Client httpClient,
  InMemoryPlacesLocalStore? localStore,
}) {
  return PlacesRepository(
    placesApi: PlacesApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: httpClient,
      ),
    ),
    localStore: localStore ?? InMemoryPlacesLocalStore(),
  );
}

void main() {
  group('cachedPlaces', () {
    test(
      'reads straight from the local store without touching the network',
      () async {
        final localStore = InMemoryPlacesLocalStore(
          initial: {
            '20': [
              Place.fromJson({'id': 1, 'trip_id': 20, 'name': 'Fergburger'}),
            ],
          },
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            fail('cachedPlaces() should not hit the network');
          }),
          localStore: localStore,
        );

        final places = await repository.cachedPlaces('20');

        expect(places, hasLength(1));
        expect(places.single.id, 1);
      },
    );
  });

  group('refreshPlaces', () {
    test(
      'fetches from the network and writes the result to the cache',
      () async {
        final localStore = InMemoryPlacesLocalStore();
        final repository = _repository(
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/trips/20/places');
            return _json({
              'places': [
                {'id': 1, 'trip_id': 20, 'name': 'Fergburger'},
              ],
            });
          }),
          localStore: localStore,
        );

        final places = await repository.refreshPlaces('20');

        expect(places.single.id, 1);
        expect((await localStore.read('20')).single.id, 1);
      },
    );

    test(
      'falls back to the cache on NetworkException when places are cached',
      () async {
        final localStore = InMemoryPlacesLocalStore(
          initial: {
            '20': [
              Place.fromJson({'id': 1, 'trip_id': 20, 'name': 'Fergburger'}),
            ],
          },
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: localStore,
        );

        final places = await repository.refreshPlaces('20');

        expect(places.single.id, 1);
      },
    );

    test('rethrows NetworkException when the cache is empty', () async {
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
      );

      expect(repository.refreshPlaces('20'), throwsA(isA<NetworkException>()));
    });

    test(
      'a trip with no places yet returns an empty list, not an error',
      () async {
        final repository = _repository(
          httpClient: MockClient((request) async => _json({'places': []})),
        );

        final places = await repository.refreshPlaces('20');

        expect(places, isEmpty);
      },
    );
  });
}
