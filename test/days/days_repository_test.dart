import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/days/day.dart';
import 'package:trek/days/days_api.dart';
import 'package:trek/days/days_repository.dart';
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

DaysRepository _repository({
  required http.Client httpClient,
  InMemoryDaysLocalStore? localStore,
}) {
  return DaysRepository(
    daysApi: DaysApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: httpClient,
      ),
    ),
    localStore: localStore ?? InMemoryDaysLocalStore(),
  );
}

void main() {
  group('cachedDays', () {
    test(
      'reads straight from the local store without touching the network',
      () async {
        final localStore = InMemoryDaysLocalStore(
          initial: {
            '20': [
              Day.fromJson({'id': 1, 'trip_id': 20, 'day_number': 1}),
            ],
          },
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            fail('cachedDays() should not hit the network');
          }),
          localStore: localStore,
        );

        final days = await repository.cachedDays('20');

        expect(days, hasLength(1));
        expect(days.single.id, 1);
      },
    );
  });

  group('refreshDays', () {
    test(
      'fetches from the network and writes the result to the cache',
      () async {
        final localStore = InMemoryDaysLocalStore();
        final repository = _repository(
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/trips/20/days');
            return _json({
              'days': [
                {'id': 1, 'trip_id': 20, 'day_number': 1},
              ],
            });
          }),
          localStore: localStore,
        );

        final days = await repository.refreshDays('20');

        expect(days.single.id, 1);
        expect((await localStore.read('20')).single.id, 1);
      },
    );

    test(
      'falls back to the cache on NetworkException when days are cached',
      () async {
        final localStore = InMemoryDaysLocalStore(
          initial: {
            '20': [
              Day.fromJson({'id': 1, 'trip_id': 20, 'day_number': 1}),
            ],
          },
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: localStore,
        );

        final days = await repository.refreshDays('20');

        expect(days.single.id, 1);
      },
    );

    test('rethrows NetworkException when the cache is empty', () async {
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
      );

      expect(repository.refreshDays('20'), throwsA(isA<NetworkException>()));
    });

    test(
      'a trip with no days yet returns an empty list, not an error',
      () async {
        final repository = _repository(
          httpClient: MockClient((request) async => _json({'days': []})),
        );

        final days = await repository.refreshDays('20');

        expect(days, isEmpty);
      },
    );
  });
}
