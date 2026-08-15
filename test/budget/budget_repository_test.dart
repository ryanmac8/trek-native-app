import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/budget/budget_api.dart';
import 'package:trek/budget/budget_item.dart';
import 'package:trek/budget/budget_repository.dart';
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

BudgetRepository _repository({
  required http.Client httpClient,
  InMemoryBudgetLocalStore? localStore,
}) {
  return BudgetRepository(
    budgetApi: BudgetApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: httpClient,
      ),
    ),
    localStore: localStore ?? InMemoryBudgetLocalStore(),
  );
}

void main() {
  group('cachedItems', () {
    test(
      'reads straight from the local store without touching the network',
      () async {
        final localStore = InMemoryBudgetLocalStore(
          initial: {
            '20': [
              BudgetItem.fromJson({
                'id': 1,
                'trip_id': 20,
                'name': 'Cached item',
              }, tripId: '20'),
            ],
          },
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            fail('cachedItems() should not hit the network');
          }),
          localStore: localStore,
        );

        final items = await repository.cachedItems('20');

        expect(items, hasLength(1));
        expect(items.single.name, 'Cached item');
      },
    );
  });

  group('refreshItems', () {
    test(
      'fetches from the network and writes the result to the cache',
      () async {
        final localStore = InMemoryBudgetLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({
              'items': [
                {'id': 1, 'trip_id': 20, 'name': 'Rental car'},
              ],
            }),
          ),
          localStore: localStore,
        );

        final items = await repository.refreshItems('20');

        expect(items.single.name, 'Rental car');
        expect((await localStore.read('20')).single.name, 'Rental car');
      },
    );

    test(
      'falls back to the cache on NetworkException when items are cached',
      () async {
        final localStore = InMemoryBudgetLocalStore(
          initial: {
            '20': [
              BudgetItem.fromJson({
                'id': 1,
                'trip_id': 20,
                'name': 'Cached item',
              }, tripId: '20'),
            ],
          },
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: localStore,
        );

        final items = await repository.refreshItems('20');

        expect(items.single.name, 'Cached item');
      },
    );

    test('rethrows NetworkException when the cache is empty', () async {
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
      );

      expect(repository.refreshItems('20'), throwsA(isA<NetworkException>()));
    });

    test(
      'a trip with no budget items yet returns an empty list, not an error',
      () async {
        final repository = _repository(
          httpClient: MockClient((request) async => _json({'items': []})),
        );

        final items = await repository.refreshItems('20');

        expect(items, isEmpty);
      },
    );

    test('retries a pending offline-created item and reconciles it', () async {
      final localStore = InMemoryBudgetLocalStore(
        initial: {
          '20': [
            const BudgetItem(localId: 'local-1', tripId: '20', name: 'Draft'),
          ],
        },
      );
      var createCalls = 0;
      final repository = _repository(
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            createCalls++;
            return _json({
              'item': {'id': 42, 'trip_id': 20, 'name': 'Draft'},
            }, 201);
          }
          return _json({'items': []});
        }),
        localStore: localStore,
      );

      final items = await repository.refreshItems('20');

      expect(createCalls, 1);
      expect(items.single.id, 42);
      expect(items.single.localId, 'local-1');
      expect(items.single.isPending, isFalse);
    });

    test(
      'leaves a pending item queued when the retry is still offline',
      () async {
        final localStore = InMemoryBudgetLocalStore(
          initial: {
            '20': [
              const BudgetItem(localId: 'local-1', tripId: '20', name: 'Draft'),
            ],
          },
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: localStore,
        );

        final items = await repository.refreshItems('20');

        expect(items.single.isPending, isTrue);
        expect(items.single.localId, 'local-1');
      },
    );

    test(
      'caches for different trips stay independent through a refresh',
      () async {
        final localStore = InMemoryBudgetLocalStore(
          initial: {
            '21': [
              BudgetItem.fromJson({
                'id': 9,
                'trip_id': 21,
                'name': 'Other trip item',
              }, tripId: '21'),
            ],
          },
        );
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({
              'items': [
                {'id': 1, 'trip_id': 20, 'name': 'This trip item'},
              ],
            }),
          ),
          localStore: localStore,
        );

        await repository.refreshItems('20');

        expect((await localStore.read('20')).single.name, 'This trip item');
        expect((await localStore.read('21')).single.name, 'Other trip item');
      },
    );
  });

  group('createItem', () {
    test(
      'writes the item locally first, then reconciles with the server id',
      () async {
        final localStore = InMemoryBudgetLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({
              'item': {
                'id': 7,
                'trip_id': 20,
                'name': 'Dinner',
                'total_price': 42.5,
              },
            }, 201),
          ),
          localStore: localStore,
        );

        final item = await repository.createItem(
          '20',
          name: 'Dinner',
          totalPrice: 42.5,
        );

        expect(item.id, 7);
        expect(item.isPending, isFalse);
        final cached = await localStore.read('20');
        expect(cached, hasLength(1));
        expect(cached.single.id, 7);
      },
    );

    test('stays queued as a pending item in the cache when offline, instead of '
        'failing or blocking', () async {
      final localStore = InMemoryBudgetLocalStore();
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      final item = await repository.createItem('20', name: 'Dinner');

      expect(item.isPending, isTrue);
      expect(item.name, 'Dinner');
      final cached = await localStore.read('20');
      expect(cached, hasLength(1));
      expect(cached.single.isPending, isTrue);
    });

    test(
      'rolls back the optimistic write when the server rejects the request',
      () async {
        final localStore = InMemoryBudgetLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({'error': 'Name is required'}, 400),
          ),
          localStore: localStore,
        );

        await expectLater(
          repository.createItem('20', name: ''),
          throwsA(isA<ValidationException>()),
        );
        expect(await localStore.read('20'), isEmpty);
      },
    );
  });
}
