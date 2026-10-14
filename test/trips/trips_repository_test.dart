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

  group('editTrip', () {
    test('applies the edit locally, then reconciles with the server', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({'id': 20, 'title': 'New Zealand'}),
        ],
      );
      final repository = _repository(
        httpClient: MockClient(
          (request) async => _json({
            'trip': {'id': 20, 'title': 'Aotearoa'},
          }),
        ),
        localStore: localStore,
      );

      final trip = await repository.editTrip(id: 20, title: 'Aotearoa');

      expect(trip.title, 'Aotearoa');
      expect(trip.hasPendingEdit, isFalse);
      expect((await localStore.read()).single.title, 'Aotearoa');
    });

    test('stays applied locally (flagged pending) when the network is '
        'unreachable, instead of failing or blocking', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({'id': 20, 'title': 'New Zealand'}),
        ],
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      final trip = await repository.editTrip(id: 20, title: 'Aotearoa');

      expect(trip.title, 'Aotearoa');
      expect(trip.hasPendingEdit, isTrue);
      final cached = await localStore.read();
      expect(cached.single.title, 'Aotearoa');
      expect(cached.single.hasPendingEdit, isTrue);
    });

    test('rolls back the edit when the server rejects the request', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({'id': 20, 'title': 'New Zealand'}),
        ],
      );
      final repository = _repository(
        httpClient: MockClient(
          (request) async => _json({'error': 'Title is required'}, 400),
        ),
        localStore: localStore,
      );

      await expectLater(
        repository.editTrip(id: 20, title: ''),
        throwsA(isA<ValidationException>()),
      );
      expect((await localStore.read()).single.title, 'New Zealand');
    });

    test('a pending edit is retried by refreshTrips()', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({
            'id': 20,
            'title': 'New Zealand',
          }).copyWith(hasPendingEdit: true),
        ],
      );
      var putCalls = 0;
      final repository = _repository(
        httpClient: MockClient((request) async {
          if (request.method == 'PUT') {
            putCalls++;
            return _json({
              'trip': {'id': 20, 'title': 'New Zealand'},
            });
          }
          return _json({
            'trips': [
              {'id': 20, 'title': 'New Zealand'},
            ],
          });
        }),
        localStore: localStore,
      );

      final trips = await repository.refreshTrips();

      expect(putCalls, 1);
      expect(trips.single.hasPendingEdit, isFalse);
    });
  });

  group('setArchived', () {
    test('archives locally, then reconciles with the server', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({'id': 20, 'title': 'New Zealand'}),
        ],
      );
      final repository = _repository(
        httpClient: MockClient(
          (request) async => _json({
            'trip': {'id': 20, 'title': 'New Zealand', 'is_archived': 1},
          }),
        ),
        localStore: localStore,
      );

      final trip = await repository.setArchived(id: 20, archived: true);

      expect(trip.isArchived, isTrue);
      expect(trip.hasPendingArchiveSync, isFalse);
      expect((await localStore.read()).single.isArchived, isTrue);
    });

    test('stays archived locally (flagged pending) when the network is '
        'unreachable', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({'id': 20, 'title': 'New Zealand'}),
        ],
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      final trip = await repository.setArchived(id: 20, archived: true);

      expect(trip.isArchived, isTrue);
      expect(trip.hasPendingArchiveSync, isTrue);
    });
  });

  group('refreshTrips with archived trips', () {
    test('the default refresh only calls GET /api/trips with no archived '
        'param', () async {
      final requested = <Uri>[];
      final repository = _repository(
        httpClient: MockClient((request) async {
          requested.add(request.url);
          return _json({'trips': []});
        }),
      );

      await repository.refreshTrips();

      expect(requested, hasLength(1));
      expect(requested.single.path, '/api/trips');
      expect(requested.single.queryParameters, isEmpty);
    });

    test('includeArchived fetches both lists and caches them together, '
        'archived ones flagged', () async {
      final localStore = InMemoryTripsLocalStore();
      final repository = _repository(
        httpClient: MockClient((request) async {
          if (request.url.queryParameters['archived'] == '1') {
            return _json({
              'trips': [
                {'id': 7, 'title': 'Iceland', 'is_archived': 1},
              ],
            });
          }
          return _json({
            'trips': [
              {'id': 20, 'title': 'New Zealand', 'is_archived': 0},
            ],
          });
        }),
        localStore: localStore,
      );

      final trips = await repository.refreshTrips(includeArchived: true);

      expect(trips.map((t) => (t.id, t.isArchived)), [(20, false), (7, true)]);
      expect(await localStore.read(), hasLength(2));
    });

    test('a default refresh keeps cached archived trips the default list '
        "can't see", () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({'id': 7, 'title': 'Iceland', 'is_archived': 1}),
        ],
      );
      final repository = _repository(
        httpClient: MockClient((request) async => _json({'trips': []})),
        localStore: localStore,
      );

      final trips = await repository.refreshTrips();

      expect(trips.single.id, 7);
      expect(trips.single.isArchived, isTrue);
    });

    test('a trip archived on this device stays in the cache after the next '
        'default refresh', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({'id': 20, 'title': 'New Zealand'}),
        ],
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          if (request.method == 'PUT') {
            return _json({
              'trip': {'id': 20, 'title': 'New Zealand', 'is_archived': 1},
            });
          }
          // The default list excludes the now-archived trip.
          return _json({'trips': []});
        }),
        localStore: localStore,
      );

      await repository.setArchived(id: 20, archived: true);
      final trips = await repository.refreshTrips();

      expect(trips.single.id, 20);
      expect(trips.single.isArchived, isTrue);
    });

    test('a cached archived trip the default list now returns was unarchived '
        'elsewhere — the server copy wins', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({'id': 7, 'title': 'Iceland', 'is_archived': 1}),
        ],
      );
      final repository = _repository(
        httpClient: MockClient(
          (request) async => _json({
            'trips': [
              {'id': 7, 'title': 'Iceland', 'is_archived': 0},
            ],
          }),
        ),
        localStore: localStore,
      );

      final trips = await repository.refreshTrips();

      expect(trips, hasLength(1));
      expect(trips.single.isArchived, isFalse);
    });

    test('an archived trip missing from both lists is dropped (deleted '
        'server-side)', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({'id': 7, 'title': 'Iceland', 'is_archived': 1}),
        ],
      );
      final repository = _repository(
        httpClient: MockClient((request) async => _json({'trips': []})),
        localStore: localStore,
      );

      final trips = await repository.refreshTrips(includeArchived: true);

      expect(trips, isEmpty);
      expect(await localStore.read(), isEmpty);
    });

    test('an unarchive queued offline wins over the server copy and is '
        'retried on the next refresh', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({'id': 7, 'title': 'Iceland', 'is_archived': 1}),
        ],
      );
      var online = false;
      final requests = <String>[];
      final repository = _repository(
        httpClient: MockClient((request) async {
          if (!online) throw http.ClientException('Connection refused');
          requests.add('${request.method} ${request.url}');
          if (request.method == 'PUT') {
            return _json({
              'trip': {'id': 7, 'title': 'Iceland', 'is_archived': 0},
            });
          }
          return _json({
            'trips': request.url.queryParameters['archived'] == '1'
                ? []
                : [
                    {'id': 7, 'title': 'Iceland', 'is_archived': 0},
                  ],
          });
        }),
        localStore: localStore,
      );

      final queued = await repository.setArchived(id: 7, archived: false);
      expect(queued.isArchived, isFalse);
      expect(queued.hasPendingArchiveSync, isTrue);

      // Still offline: the cached (unarchived, pending) copy is returned.
      final offline = await repository.refreshTrips(includeArchived: true);
      expect(offline.single.isArchived, isFalse);
      expect(offline.single.hasPendingArchiveSync, isTrue);

      online = true;
      final synced = await repository.refreshTrips(includeArchived: true);
      expect(requests.first, 'PUT https://trek.example.com/api/trips/7');
      expect(synced, hasLength(1));
      expect(synced.single.isArchived, isFalse);
      expect(synced.single.hasPendingArchiveSync, isFalse);
    });

    test('includeArchived falls back to the cache, archived trips included, '
        'when offline', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({'id': 20, 'title': 'New Zealand'}),
          Trip.fromJson({'id': 7, 'title': 'Iceland', 'is_archived': 1}),
        ],
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      final trips = await repository.refreshTrips(includeArchived: true);

      expect(trips.map((t) => t.id), [20, 7]);
    });

    test('includeArchived rethrows NetworkException when offline with an '
        'empty cache', () async {
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
      );

      expect(
        repository.refreshTrips(includeArchived: true),
        throwsA(isA<NetworkException>()),
      );
    });

    test('a server copy never duplicates a trip with an unsynced local '
        'edit', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({
            'id': 20,
            'title': 'Old title',
          }).copyWith(hasPendingEdit: true),
        ],
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          // The edit retry is rejected as offline, but the list call
          // happens to get through.
          if (request.method == 'PUT') {
            throw http.ClientException('Connection reset');
          }
          return _json({
            'trips': [
              {'id': 20, 'title': 'Old title'},
            ],
          });
        }),
        localStore: localStore,
      );

      final trips = await repository.refreshTrips();

      expect(trips, hasLength(1));
      expect(trips.single.hasPendingEdit, isTrue);
    });
  });

  group('deleteTrip', () {
    test('removes the trip locally and deletes it on the server', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({'id': 20, 'title': 'New Zealand'}),
        ],
      );
      var deleteCalls = 0;
      final repository = _repository(
        httpClient: MockClient((request) async {
          deleteCalls++;
          return _json({'success': true});
        }),
        localStore: localStore,
      );

      await repository.deleteTrip(20);

      expect(deleteCalls, 1);
      expect(await localStore.read(), isEmpty);
    });

    test('removes the trip locally and queues the delete when offline, '
        'instead of failing or blocking', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({'id': 20, 'title': 'New Zealand'}),
        ],
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      await repository.deleteTrip(20);

      expect(await localStore.read(), isEmpty);
      expect(await localStore.readPendingDeletes(), {20});
    });

    test('a queued delete is retried by refreshTrips() and stops the trip '
        'reappearing even if the server list call still returns it', () async {
      final localStore = InMemoryTripsLocalStore(
        initial: [],
        pendingDeletes: {20},
      );
      var deleteCalls = 0;
      final repository = _repository(
        httpClient: MockClient((request) async {
          if (request.method == 'DELETE') {
            deleteCalls++;
            throw http.ClientException('Connection refused');
          }
          // Still returns the trip — the delete above hasn't reached the
          // server yet, so the trip must not reappear.
          return _json({
            'trips': [
              {'id': 20, 'title': 'New Zealand'},
            ],
          });
        }),
        localStore: localStore,
      );

      final trips = await repository.refreshTrips();

      expect(deleteCalls, 1);
      expect(trips, isEmpty);
      expect(await localStore.readPendingDeletes(), {20});
    });
  });
}
