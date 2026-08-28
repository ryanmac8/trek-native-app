import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/reservations/reservation.dart';
import 'package:trek/reservations/reservations_api.dart';
import 'package:trek/reservations/reservations_repository.dart';

import '../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

ReservationsRepository _repository({
  required http.Client httpClient,
  InMemoryReservationsLocalStore? localStore,
}) {
  return ReservationsRepository(
    reservationsApi: ReservationsApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: httpClient,
      ),
    ),
    localStore: localStore ?? InMemoryReservationsLocalStore(),
  );
}

Reservation _booking(int id) => Reservation.fromJson({
  'id': id,
  'trip_id': 20,
  'title': 'NZ201 AKL → ZQN',
  'type': 'flight',
  'status': 'confirmed',
});

void main() {
  group('cachedReservations', () {
    test(
      'reads straight from the local store without touching the network',
      () async {
        final repository = _repository(
          httpClient: MockClient((request) async {
            fail('cachedReservations() should not hit the network');
          }),
          localStore: InMemoryReservationsLocalStore(
            initial: {
              '20': [_booking(7)],
            },
          ),
        );

        final result = await repository.cachedReservations('20');

        expect(result.single.id, 7);
      },
    );
  });

  group('refreshReservations', () {
    test(
      'fetches from the network and writes the result to the cache',
      () async {
        final localStore = InMemoryReservationsLocalStore();
        final repository = _repository(
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/trips/20/reservations');
            return _json({
              'reservations': [
                {
                  'id': 7,
                  'trip_id': 20,
                  'title': 'NZ201 AKL → ZQN',
                  'type': 'flight',
                  'status': 'confirmed',
                },
              ],
            });
          }),
          localStore: localStore,
        );

        final result = await repository.refreshReservations('20');

        expect(result.single.id, 7);
        expect((await localStore.read('20')).single.id, 7);
      },
    );

    test(
      'falls back to the cache on NetworkException when bookings are cached',
      () async {
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: InMemoryReservationsLocalStore(
            initial: {
              '20': [_booking(7)],
            },
          ),
        );

        final result = await repository.refreshReservations('20');

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
        repository.refreshReservations('20'),
        throwsA(isA<NetworkException>()),
      );
    });

    test(
      'a trip with no reservations returns an empty list, not an error',
      () async {
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({'reservations': []}),
          ),
        );

        expect(await repository.refreshReservations('20'), isEmpty);
      },
    );

    test('a stale cache is replaced by the fresh server list', () async {
      final localStore = InMemoryReservationsLocalStore(
        initial: {
          '20': [_booking(7), _booking(8)],
        },
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          return _json({
            'reservations': [
              {
                'id': 8,
                'trip_id': 20,
                'title': 'Hotel Sofitel',
                'type': 'hotel',
                'status': 'confirmed',
              },
            ],
          });
        }),
        localStore: localStore,
      );

      final result = await repository.refreshReservations('20');

      expect(result.map((r) => r.id), [8]);
      expect((await localStore.read('20')).map((r) => r.id), [8]);
    });
  });
}
