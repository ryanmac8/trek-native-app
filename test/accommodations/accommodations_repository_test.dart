import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/accommodations/accommodation.dart';
import 'package:trek/accommodations/accommodations_api.dart';
import 'package:trek/accommodations/accommodations_repository.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';

import '../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

AccommodationsRepository _repository({
  required http.Client httpClient,
  InMemoryAccommodationsLocalStore? localStore,
}) {
  return AccommodationsRepository(
    accommodationsApi: AccommodationsApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: httpClient,
      ),
    ),
    localStore: localStore ?? InMemoryAccommodationsLocalStore(),
  );
}

Accommodation _stay(int id) => Accommodation.fromJson({
  'id': id,
  'trip_id': 20,
  'place_id': 501,
  'start_day_id': 1,
  'end_day_id': 2,
  'place_name': 'Sofitel Queenstown',
});

void main() {
  group('cachedAccommodations', () {
    test(
      'reads straight from the local store without touching the network',
      () async {
        final repository = _repository(
          httpClient: MockClient((request) async {
            fail('cachedAccommodations() should not hit the network');
          }),
          localStore: InMemoryAccommodationsLocalStore(
            initial: {
              '20': [_stay(7)],
            },
          ),
        );

        final result = await repository.cachedAccommodations('20');

        expect(result.single.id, 7);
      },
    );
  });

  group('refreshAccommodations', () {
    test(
      'fetches from the network and writes the result to the cache',
      () async {
        final localStore = InMemoryAccommodationsLocalStore();
        final repository = _repository(
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/trips/20/accommodations');
            return _json({
              'accommodations': [
                {
                  'id': 7,
                  'trip_id': 20,
                  'place_id': 501,
                  'start_day_id': 1,
                  'end_day_id': 2,
                  'place_name': 'Sofitel Queenstown',
                },
              ],
            });
          }),
          localStore: localStore,
        );

        final result = await repository.refreshAccommodations('20');

        expect(result.single.id, 7);
        expect((await localStore.read('20')).single.id, 7);
      },
    );

    test(
      'falls back to the cache on NetworkException when stays are cached',
      () async {
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: InMemoryAccommodationsLocalStore(
            initial: {
              '20': [_stay(7)],
            },
          ),
        );

        final result = await repository.refreshAccommodations('20');

        expect(result.single.id, 7);
      },
    );

    test('rethrows NetworkException when the cache is empty', () async {
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
      );

      expect(
        repository.refreshAccommodations('20'),
        throwsA(isA<NetworkException>()),
      );
    });

    test(
      'a trip with no accommodations returns an empty list, not an error',
      () async {
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({'accommodations': []}),
          ),
        );

        expect(await repository.refreshAccommodations('20'), isEmpty);
      },
    );

    test('a stale cache is replaced by the fresh server list', () async {
      final localStore = InMemoryAccommodationsLocalStore(
        initial: {
          '20': [_stay(7), _stay(8)],
        },
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          return _json({
            'accommodations': [
              {
                'id': 8,
                'trip_id': 20,
                'place_id': 501,
                'start_day_id': 1,
                'end_day_id': 2,
              },
            ],
          });
        }),
        localStore: localStore,
      );

      final result = await repository.refreshAccommodations('20');

      expect(result.map((a) => a.id), [8]);
      expect((await localStore.read('20')).map((a) => a.id), [8]);
    });
  });
}
