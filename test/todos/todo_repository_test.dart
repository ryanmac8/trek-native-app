import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/todos/todo_api.dart';
import 'package:trek/todos/todo_item.dart';
import 'package:trek/todos/todo_repository.dart';

import '../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

TodoRepository _repository({
  required http.Client httpClient,
  InMemoryTodoLocalStore? localStore,
}) {
  return TodoRepository(
    todoApi: TodoApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: httpClient,
      ),
    ),
    localStore: localStore ?? InMemoryTodoLocalStore(),
  );
}

void main() {
  group('cachedItems', () {
    test(
      'reads straight from the local store without touching the network',
      () async {
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [
              TodoItem.fromJson({
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
        final localStore = InMemoryTodoLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({
              'items': [
                {'id': 1, 'trip_id': 20, 'name': 'Book campsite'},
              ],
            }),
          ),
          localStore: localStore,
        );

        final items = await repository.refreshItems('20');

        expect(items.single.name, 'Book campsite');
        expect((await localStore.read('20')).single.name, 'Book campsite');
      },
    );

    test(
      'falls back to the cache on NetworkException when items are cached',
      () async {
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [
              TodoItem.fromJson({
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
      'a trip with no todos yet returns an empty list, not an error',
      () async {
        final repository = _repository(
          httpClient: MockClient((request) async => _json({'items': []})),
        );

        final items = await repository.refreshItems('20');

        expect(items, isEmpty);
      },
    );

    test('retries a pending offline-created item and reconciles it', () async {
      final localStore = InMemoryTodoLocalStore(
        initial: {
          '20': [
            const TodoItem(localId: 'local-1', tripId: '20', name: 'Draft'),
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
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [
              const TodoItem(localId: 'local-1', tripId: '20', name: 'Draft'),
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
      'retries a pending offline toggle and keeps its confirmed value',
      () async {
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [
              const TodoItem(
                id: 7,
                localId: 'server-7',
                tripId: '20',
                name: 'Book campsite',
                checked: true,
                pendingChecked: true,
              ),
            ],
          },
        );
        var putCalls = 0;
        final repository = _repository(
          httpClient: MockClient((request) async {
            if (request.method == 'PUT') {
              putCalls++;
              return _json({
                'item': {
                  'id': 7,
                  'trip_id': 20,
                  'name': 'Book campsite',
                  'checked': 1,
                },
              });
            }
            return _json({
              'items': [
                {'id': 7, 'trip_id': 20, 'name': 'Book campsite', 'checked': 1},
              ],
            });
          }),
          localStore: localStore,
        );

        final items = await repository.refreshItems('20');

        expect(putCalls, 1);
        expect(items.single.checked, isTrue);
        expect(items.single.pendingChecked, isFalse);
      },
    );

    test(
      'a still-offline toggle stays queued and overrides the stale server value',
      () async {
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [
              const TodoItem(
                id: 7,
                localId: 'server-7',
                tripId: '20',
                name: 'Book campsite',
                checked: true,
                pendingChecked: true,
              ),
            ],
          },
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            if (request.method == 'PUT') {
              throw http.ClientException('Connection refused');
            }
            return _json({
              'items': [
                {'id': 7, 'trip_id': 20, 'name': 'Book campsite', 'checked': 0},
              ],
            });
          }),
          localStore: localStore,
        );

        final items = await repository.refreshItems('20');

        expect(items.single.checked, isTrue);
        expect(items.single.pendingChecked, isTrue);
      },
    );

    test(
      'retries a pending offline delete and drops the item once synced',
      () async {
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [
              const TodoItem(
                id: 7,
                localId: 'server-7',
                tripId: '20',
                name: 'Book campsite',
                pendingDelete: true,
              ),
            ],
          },
        );
        var deleteCalls = 0;
        final repository = _repository(
          httpClient: MockClient((request) async {
            if (request.method == 'DELETE') {
              deleteCalls++;
              return _json({'success': true});
            }
            return _json({'items': []});
          }),
          localStore: localStore,
        );

        final items = await repository.refreshItems('20');

        expect(deleteCalls, 1);
        expect(items, isEmpty);
        expect(await localStore.read('20'), isEmpty);
      },
    );

    test('a still-offline delete stays queued and is not resurrected by the '
        'server still listing the item', () async {
      final localStore = InMemoryTodoLocalStore(
        initial: {
          '20': [
            const TodoItem(
              id: 7,
              localId: 'server-7',
              tripId: '20',
              name: 'Book campsite',
              pendingDelete: true,
            ),
          ],
        },
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          if (request.method == 'DELETE') {
            throw http.ClientException('Connection refused');
          }
          return _json({
            'items': [
              {'id': 7, 'trip_id': 20, 'name': 'Book campsite'},
            ],
          });
        }),
        localStore: localStore,
      );

      final items = await repository.refreshItems('20');

      expect(items.single.pendingDelete, isTrue);
      expect(items.single.localId, 'server-7');
    });

    test(
      'a delete retry that finds the item already gone (404) drops it too',
      () async {
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [
              const TodoItem(
                id: 7,
                localId: 'server-7',
                tripId: '20',
                name: 'Book campsite',
                pendingDelete: true,
              ),
            ],
          },
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            if (request.method == 'DELETE') {
              return _json({'error': 'Item not found'}, 404);
            }
            return _json({'items': []});
          }),
          localStore: localStore,
        );

        final items = await repository.refreshItems('20');

        expect(items, isEmpty);
      },
    );

    test(
      'caches for different trips stay independent through a refresh',
      () async {
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '21': [
              TodoItem.fromJson({
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
        final localStore = InMemoryTodoLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({
              'item': {'id': 7, 'trip_id': 20, 'name': 'Book campsite'},
            }, 201),
          ),
          localStore: localStore,
        );

        final item = await repository.createItem('20', name: 'Book campsite');

        expect(item.id, 7);
        expect(item.isPending, isFalse);
        final cached = await localStore.read('20');
        expect(cached, hasLength(1));
        expect(cached.single.id, 7);
      },
    );

    test('stays queued as a pending item in the cache when offline, instead of '
        'failing or blocking', () async {
      final localStore = InMemoryTodoLocalStore();
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      final item = await repository.createItem('20', name: 'Book campsite');

      expect(item.isPending, isTrue);
      expect(item.name, 'Book campsite');
      final cached = await localStore.read('20');
      expect(cached, hasLength(1));
      expect(cached.single.isPending, isTrue);
    });

    test(
      'rolls back the optimistic write when the server rejects the request',
      () async {
        final localStore = InMemoryTodoLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({'error': 'Item name is required'}, 400),
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

  group('toggleChecked', () {
    const item = TodoItem(
      id: 7,
      localId: 'server-7',
      tripId: '20',
      name: 'Book campsite',
      checked: false,
    );

    test(
      'flips the cache immediately, then reconciles with the server value',
      () async {
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [item],
          },
        );
        Map<String, dynamic>? sentBody;
        final repository = _repository(
          httpClient: MockClient((request) async {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({
              'item': {
                'id': 7,
                'trip_id': 20,
                'name': 'Book campsite',
                'checked': 1,
              },
            });
          }),
          localStore: localStore,
        );

        final updated = await repository.toggleChecked('20', item);

        expect(sentBody, {'checked': true});
        expect(updated.checked, isTrue);
        expect(updated.pendingChecked, isFalse);
        final cached = await localStore.read('20');
        expect(cached.single.checked, isTrue);
        expect(cached.single.pendingChecked, isFalse);
      },
    );

    test('stays queued as a pending toggle in the cache when offline, instead '
        'of failing or blocking', () async {
      final localStore = InMemoryTodoLocalStore(
        initial: {
          '20': [item],
        },
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      final updated = await repository.toggleChecked('20', item);

      expect(updated.checked, isTrue);
      expect(updated.pendingChecked, isTrue);
      final cached = await localStore.read('20');
      expect(cached.single.checked, isTrue);
      expect(cached.single.pendingChecked, isTrue);
    });

    test(
      'rolls back the optimistic flip when the server rejects the request',
      () async {
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [item],
          },
        );
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({'error': 'Item not found'}, 404),
          ),
          localStore: localStore,
        );

        await expectLater(
          repository.toggleChecked('20', item),
          throwsA(isA<ApiException>()),
        );
        final cached = await localStore.read('20');
        expect(cached.single.checked, isFalse);
        expect(cached.single.pendingChecked, isFalse);
      },
    );
  });

  group('deleteItem', () {
    const item = TodoItem(
      id: 7,
      localId: 'server-7',
      tripId: '20',
      name: 'Book campsite',
    );

    test('removes the item from the cache immediately once synced', () async {
      final localStore = InMemoryTodoLocalStore(
        initial: {
          '20': [item],
        },
      );
      Uri? requestedUri;
      final repository = _repository(
        httpClient: MockClient((request) async {
          requestedUri = request.url;
          return _json({'success': true});
        }),
        localStore: localStore,
      );

      await repository.deleteItem('20', item);

      expect(requestedUri?.path, '/api/trips/20/todo/7');
      expect(await localStore.read('20'), isEmpty);
    });

    test('drops a never-synced (pending) item locally without hitting the '
        'network', () async {
      const pending = TodoItem(localId: 'local-1', tripId: '20', name: 'Draft');
      final localStore = InMemoryTodoLocalStore(
        initial: {
          '20': [pending],
        },
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          fail('should not attempt to delete a not-yet-synced item');
        }),
        localStore: localStore,
      );

      await repository.deleteItem('20', pending);

      expect(await localStore.read('20'), isEmpty);
    });

    test('stays queued as a pending-delete tombstone in the cache when '
        'offline, instead of failing or blocking', () async {
      final localStore = InMemoryTodoLocalStore(
        initial: {
          '20': [item],
        },
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      await repository.deleteItem('20', item);

      final cached = await localStore.read('20');
      expect(cached.single.pendingDelete, isTrue);
    });

    test('treats a 404 (already gone) the same as success', () async {
      final localStore = InMemoryTodoLocalStore(
        initial: {
          '20': [item],
        },
      );
      final repository = _repository(
        httpClient: MockClient(
          (request) async => _json({'error': 'Item not found'}, 404),
        ),
        localStore: localStore,
      );

      await repository.deleteItem('20', item);

      expect(await localStore.read('20'), isEmpty);
    });

    test(
      'rolls back the optimistic delete when the server rejects the request',
      () async {
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [item],
          },
        );
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({'error': 'No permission'}, 403),
          ),
          localStore: localStore,
        );

        await expectLater(
          repository.deleteItem('20', item),
          throwsA(isA<ApiException>()),
        );
        final cached = await localStore.read('20');
        expect(cached.single.pendingDelete, isFalse);
      },
    );
  });

  group('reorderItems', () {
    const first = TodoItem(id: 1, localId: 'server-1', tripId: '20', name: 'A');
    const second = TodoItem(
      id: 2,
      localId: 'server-2',
      tripId: '20',
      name: 'B',
    );

    test(
      'writes the new order to the cache immediately, then syncs it',
      () async {
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [first, second],
          },
        );
        List<int>? sentIds;
        final repository = _repository(
          httpClient: MockClient((request) async {
            sentIds = List<int>.from(
              (jsonDecode(request.body) as Map<String, dynamic>)['orderedIds']
                  as List,
            );
            return _json({'success': true});
          }),
          localStore: localStore,
        );

        await repository.reorderItems('20', [second, first]);

        expect(sentIds, [2, 1]);
        final cached = await localStore.read('20');
        expect(cached.map((i) => i.id), [2, 1]);
        expect(await localStore.readReorderPending('20'), isFalse);
      },
    );

    test(
      'stays queued as reorder-pending in the cache when offline, instead of '
      'failing or blocking',
      () async {
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [first, second],
          },
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: localStore,
        );

        await repository.reorderItems('20', [second, first]);

        final cached = await localStore.read('20');
        expect(cached.map((i) => i.id), [2, 1]);
        expect(await localStore.readReorderPending('20'), isTrue);
      },
    );

    test(
      'rolls back to the previous order when the server rejects the request',
      () async {
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [first, second],
          },
        );
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({'error': 'No permission'}, 403),
          ),
          localStore: localStore,
        );

        await expectLater(
          repository.reorderItems('20', [second, first]),
          throwsA(isA<ApiException>()),
        );
        final cached = await localStore.read('20');
        expect(cached.map((i) => i.id), [1, 2]);
        expect(await localStore.readReorderPending('20'), isFalse);
      },
    );

    test(
      'excludes not-yet-synced and tombstoned items from the synced ids',
      () async {
        const pending = TodoItem(
          localId: 'local-1',
          tripId: '20',
          name: 'Draft',
        );
        const tombstoned = TodoItem(
          id: 3,
          localId: 'server-3',
          tripId: '20',
          name: 'C',
          pendingDelete: true,
        );
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [first, second, pending, tombstoned],
          },
        );
        List<int>? sentIds;
        final repository = _repository(
          httpClient: MockClient((request) async {
            sentIds = List<int>.from(
              (jsonDecode(request.body) as Map<String, dynamic>)['orderedIds']
                  as List,
            );
            return _json({'success': true});
          }),
          localStore: localStore,
        );

        await repository.reorderItems('20', [
          second,
          first,
          pending,
          tombstoned,
        ]);

        expect(sentIds, [2, 1]);
      },
    );
  });

  group('refreshItems reorder retry', () {
    const first = TodoItem(id: 1, localId: 'server-1', tripId: '20', name: 'A');
    const second = TodoItem(
      id: 2,
      localId: 'server-2',
      tripId: '20',
      name: 'B',
    );

    test(
      'syncs a queued reorder and clears the pending flag once it succeeds',
      () async {
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [second, first],
          },
        );
        await localStore.writeReorderPending('20', true);
        var reorderCalls = 0;
        // A real server persists sort_order before answering the next GET —
        // simulate that instead of returning a GET response that ignores
        // the PUT.
        var serverOrder = [1, 2];
        final repository = _repository(
          httpClient: MockClient((request) async {
            if (request.method == 'PUT') {
              reorderCalls++;
              serverOrder = List<int>.from(
                (jsonDecode(request.body) as Map<String, dynamic>)['orderedIds']
                    as List,
              );
              return _json({'success': true});
            }
            return _json({
              'items': [
                for (final id in serverOrder)
                  {'id': id, 'trip_id': 20, 'name': id == 1 ? 'A' : 'B'},
              ],
            });
          }),
          localStore: localStore,
        );

        final items = await repository.refreshItems('20');

        expect(reorderCalls, 1);
        expect(items.map((i) => i.id), [2, 1]);
        expect(await localStore.readReorderPending('20'), isFalse);
      },
    );

    test(
      'keeps the local order when the reorder retry is still offline',
      () async {
        final localStore = InMemoryTodoLocalStore(
          initial: {
            '20': [second, first],
          },
        );
        await localStore.writeReorderPending('20', true);
        final repository = _repository(
          httpClient: MockClient((request) async {
            if (request.method == 'PUT') {
              throw http.ClientException('Connection refused');
            }
            return _json({
              'items': [
                {'id': 1, 'trip_id': 20, 'name': 'A'},
                {'id': 2, 'trip_id': 20, 'name': 'B'},
              ],
            });
          }),
          localStore: localStore,
        );

        final items = await repository.refreshItems('20');

        expect(items.map((i) => i.id), [2, 1]);
        expect(await localStore.readReorderPending('20'), isTrue);
      },
    );
  });
}
