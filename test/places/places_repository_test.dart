import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/places/pending_place_op.dart';
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

  group('local-first writes', () {
    test('createPlace works offline: temp id, pending, queued', () async {
      final localStore = InMemoryPlacesLocalStore();
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      final place = await repository.createPlace(
        '20',
        const PlaceInput(name: 'Fergburger', price: 18, currency: 'nzd'),
      );
      final sync = await repository.syncPending('20');

      expect(place.id, -1);
      expect(place.syncStatus, PlaceSyncStatus.pending);
      expect(sync.offline, isTrue);
      final cached = await localStore.read('20');
      expect(cached.single.name, 'Fergburger');
      expect(cached.single.currency, 'NZD');
      final pending = await localStore.readPending('20');
      expect(pending.single.kind, PendingPlaceOpKind.create);
    });

    test(
      'syncPending posts a queued create and swaps in the server place',
      () async {
        final localStore = InMemoryPlacesLocalStore();
        late Map<String, dynamic> postedBody;
        final repository = _repository(
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/trips/20/places');
            postedBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({
              'place': {
                'id': 501,
                'trip_id': 20,
                'name': 'Fergburger',
                'notes': 'Get there early',
                'updated_at': '2026-10-13 09:00:00',
              },
            }, 201);
          }),
          localStore: localStore,
        );

        await repository.createPlace(
          '20',
          const PlaceInput(name: ' Fergburger ', notes: 'Get there early'),
        );
        final sync = await repository.syncPending('20');

        expect(postedBody, {'name': 'Fergburger', 'notes': 'Get there early'});
        expect(sync.offline, isFalse);
        expect(sync.rejections, isEmpty);
        final cached = await localStore.read('20');
        expect(cached.single.id, 501);
        expect(cached.single.syncStatus, PlaceSyncStatus.synced);
        expect(await localStore.readPending('20'), isEmpty);
      },
    );

    test(
      'an offline edit sends only changed fields with X-Base-Updated-At',
      () async {
        final original = Place.fromJson({
          'id': 501,
          'trip_id': 20,
          'name': 'Fergburger',
          'notes': 'Old note',
          'price': 18,
          'updated_at': '2026-10-01 10:00:00',
        });
        final localStore = InMemoryPlacesLocalStore(
          initial: {
            '20': [original],
          },
        );
        var online = false;
        late http.Request sent;
        final repository = _repository(
          httpClient: MockClient((request) async {
            if (!online) throw http.ClientException('Connection refused');
            sent = request;
            return _json({
              'place': {
                'id': 501,
                'trip_id': 20,
                'name': 'Fergburger',
                'price': 18,
                'updated_at': '2026-10-13 09:00:00',
              },
            });
          }),
          localStore: localStore,
        );

        final edited = await repository.updatePlace(
          '20',
          original,
          const PlaceInput(name: 'Fergburger', price: 18, notes: ''),
        );
        expect(edited.notes, isNull);
        expect(edited.syncStatus, PlaceSyncStatus.pending);
        expect((await repository.syncPending('20')).offline, isTrue);
        expect(
          (await localStore.read('20')).single.syncStatus,
          PlaceSyncStatus.pending,
        );

        online = true;
        await repository.syncPending('20');

        expect(sent.method, 'PUT');
        expect(sent.url.path, '/api/trips/20/places/501');
        expect(sent.headers['X-Base-Updated-At'], '2026-10-01 10:00:00');
        expect(jsonDecode(sent.body), {'notes': null});
        final cached = (await localStore.read('20')).single;
        expect(cached.syncStatus, PlaceSyncStatus.synced);
        expect(cached.updatedAt, '2026-10-13 09:00:00');
      },
    );

    test('edits to a place with a queued create merge into it', () async {
      final localStore = InMemoryPlacesLocalStore();
      final requests = <http.Request>[];
      final repository = _repository(
        httpClient: MockClient((request) async {
          requests.add(request);
          return _json({
            'place': {'id': 501, 'trip_id': 20, 'name': 'Fergburger'},
          }, 201);
        }),
        localStore: localStore,
      );

      final created = await repository.createPlace(
        '20',
        const PlaceInput(name: 'Ferg'),
      );
      await repository.updatePlace(
        '20',
        created,
        const PlaceInput(name: 'Fergburger', address: '42 Shotover St'),
      );
      expect(await localStore.readPending('20'), hasLength(1));

      await repository.syncPending('20');

      expect(requests, hasLength(1));
      expect(jsonDecode(requests.single.body), {
        'name': 'Fergburger',
        'address': '42 Shotover St',
      });
    });

    test('deleting a never-synced place sends nothing', () async {
      final localStore = InMemoryPlacesLocalStore();
      final repository = _repository(
        httpClient: MockClient((request) async {
          fail('nothing should reach the server');
        }),
        localStore: localStore,
      );

      final created = await repository.createPlace(
        '20',
        const PlaceInput(name: 'Typo'),
      );
      await repository.deletePlace('20', created.id);
      await repository.syncPending('20');

      expect(await localStore.read('20'), isEmpty);
      expect(await localStore.readPending('20'), isEmpty);
    });

    test(
      'an offline delete removes the place at once and replays later',
      () async {
        final localStore = InMemoryPlacesLocalStore(
          initial: {
            '20': [
              Place.fromJson({'id': 501, 'trip_id': 20, 'name': 'Fergburger'}),
            ],
          },
        );
        var online = false;
        final requests = <http.Request>[];
        final repository = _repository(
          httpClient: MockClient((request) async {
            if (!online) throw http.ClientException('Connection refused');
            requests.add(request);
            return _json({'success': true});
          }),
          localStore: localStore,
        );

        await repository.deletePlace('20', 501);
        await repository.syncPending('20');
        expect(await localStore.read('20'), isEmpty);
        expect(await localStore.readPending('20'), hasLength(1));

        online = true;
        await repository.syncPending('20');

        expect(requests.single.method, 'DELETE');
        expect(requests.single.url.path, '/api/trips/20/places/501');
        expect(await localStore.readPending('20'), isEmpty);
      },
    );

    test('a delete answered 404 counts as done', () async {
      final localStore = InMemoryPlacesLocalStore(
        initial: {
          '20': [
            Place.fromJson({'id': 501, 'trip_id': 20, 'name': 'Fergburger'}),
          ],
        },
      );
      final repository = _repository(
        httpClient: MockClient(
          (request) async => _json({'error': 'Place not found'}, 404),
        ),
        localStore: localStore,
      );

      await repository.deletePlace('20', 501);
      final sync = await repository.syncPending('20');

      expect(sync.rejections, isEmpty);
      expect(await localStore.readPending('20'), isEmpty);
    });

    test('a 5xx keeps the change queued for the next pass', () async {
      final localStore = InMemoryPlacesLocalStore();
      final repository = _repository(
        httpClient: MockClient(
          (request) async => _json({'error': 'Bad gateway'}, 502),
        ),
        localStore: localStore,
      );

      await repository.createPlace('20', const PlaceInput(name: 'Fergburger'));
      final sync = await repository.syncPending('20');

      expect(sync.rejections, isEmpty);
      expect(await localStore.readPending('20'), hasLength(1));
      expect(
        (await localStore.read('20')).single.syncStatus,
        PlaceSyncStatus.pending,
      );
    });

    test(
      'an edit made while the create is on the wire follows it to the real id',
      () async {
        final localStore = InMemoryPlacesLocalStore();
        final postResponse = Completer<http.Response>();
        final requests = <http.Request>[];
        final repository = _repository(
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.method == 'POST') return postResponse.future;
            return _json({
              'place': {
                'id': 501,
                'trip_id': 20,
                'name': 'Fergburger',
                'notes': 'Queue is worth it',
                'updated_at': '2026-10-13 09:05:00',
              },
            });
          }),
          localStore: localStore,
        );

        final created = await repository.createPlace(
          '20',
          const PlaceInput(name: 'Fergburger'),
        );
        final sync = repository.syncPending('20');
        await pumpEventQueue();
        expect(requests.single.method, 'POST');

        await repository.updatePlace(
          '20',
          created,
          const PlaceInput(name: 'Fergburger', notes: 'Queue is worth it'),
        );
        postResponse.complete(
          _json({
            'place': {
              'id': 501,
              'trip_id': 20,
              'name': 'Fergburger',
              'updated_at': '2026-10-13 09:00:00',
            },
          }, 201),
        );
        await sync;

        expect(requests, hasLength(2));
        expect(requests.last.method, 'PUT');
        expect(requests.last.url.path, '/api/trips/20/places/501');
        expect(
          requests.last.headers['X-Base-Updated-At'],
          '2026-10-13 09:00:00',
        );
        final cached = (await localStore.read('20')).single;
        expect(cached.id, 501);
        expect(cached.notes, 'Queue is worth it');
        expect(cached.syncStatus, PlaceSyncStatus.synced);
      },
    );
  });

  group('conflicts and rejections', () {
    final original = Place.fromJson({
      'id': 501,
      'trip_id': 20,
      'name': 'Fergburger',
      'notes': 'Old note',
      'updated_at': '2026-10-01 10:00:00',
    });
    final theirs = {
      'id': 501,
      'trip_id': 20,
      'name': 'Fergburger Queenstown',
      'notes': 'Their note',
      'updated_at': '2026-10-05 12:00:00',
    };

    Future<(PlacesRepository, InMemoryPlacesLocalStore, List<http.Request>)>
    conflicted() async {
      final localStore = InMemoryPlacesLocalStore(
        initial: {
          '20': [original],
        },
      );
      final requests = <http.Request>[];
      final repository = _repository(
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.headers['X-Base-Updated-At'] == '2026-10-01 10:00:00') {
            return _json({'error': 'conflict', 'server': theirs}, 409);
          }
          return _json({
            'place': {
              ...theirs,
              ...jsonDecode(request.body) as Map<String, dynamic>,
              'updated_at': '2026-10-13 09:00:00',
            },
          });
        }),
        localStore: localStore,
      );
      await repository.updatePlace(
        '20',
        original,
        const PlaceInput(name: 'Fergburger', notes: 'My note'),
      );
      await repository.syncPending('20');
      return (repository, localStore, requests);
    }

    test('a 409 marks the place conflicted and keeps the edit', () async {
      final (_, localStore, requests) = await conflicted();

      expect(requests, hasLength(1));
      final cached = (await localStore.read('20')).single;
      expect(cached.syncStatus, PlaceSyncStatus.conflict);
      expect(cached.notes, 'My note');
      final op = (await localStore.readPending('20')).single;
      expect(op.isConflicted, isTrue);
    });

    test('a conflicted place is not retried until resolved', () async {
      final (repository, _, requests) = await conflicted();

      await repository.syncPending('20');

      expect(requests, hasLength(1));
    });

    test('keep mine resends the edit based on the server version', () async {
      final (repository, localStore, requests) = await conflicted();

      await repository.resolveConflict('20', 501, keepMine: true);
      await repository.syncPending('20');

      expect(requests.last.headers['X-Base-Updated-At'], '2026-10-05 12:00:00');
      expect(jsonDecode(requests.last.body), {'notes': 'My note'});
      final cached = (await localStore.read('20')).single;
      expect(cached.notes, 'My note');
      expect(cached.name, 'Fergburger Queenstown');
      expect(cached.syncStatus, PlaceSyncStatus.synced);
    });

    test('use theirs drops the edit and shows the server version', () async {
      final (repository, localStore, requests) = await conflicted();

      await repository.resolveConflict('20', 501, keepMine: false);
      await repository.syncPending('20');

      expect(requests, hasLength(1));
      final cached = (await localStore.read('20')).single;
      expect(cached.notes, 'Their note');
      expect(cached.syncStatus, PlaceSyncStatus.synced);
      expect(await localStore.readPending('20'), isEmpty);
    });

    test('a refused edit is dropped and the server version restored', () async {
      final localStore = InMemoryPlacesLocalStore(
        initial: {
          '20': [original],
        },
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          if (request.method == 'PUT') {
            return _json({'error': 'No permission'}, 403);
          }
          return _json({
            'places': [original.toCacheJson()],
          });
        }),
        localStore: localStore,
      );

      await repository.updatePlace(
        '20',
        original,
        const PlaceInput(name: 'Fergburger', notes: 'My note'),
      );
      final sync = await repository.syncPending('20');

      expect(sync.rejections.single, contains('No permission'));
      final cached = (await localStore.read('20')).single;
      expect(cached.notes, 'Old note');
      expect(cached.syncStatus, PlaceSyncStatus.synced);
      expect(await localStore.readPending('20'), isEmpty);
    });

    test('a refused create removes the local place', () async {
      final localStore = InMemoryPlacesLocalStore();
      final repository = _repository(
        httpClient: MockClient(
          (request) async =>
              _json({'error': 'name must be 200 characters or less'}, 400),
        ),
        localStore: localStore,
      );

      await repository.createPlace('20', const PlaceInput(name: 'Fergburger'));
      final sync = await repository.syncPending('20');

      expect(sync.rejections.single, contains('200 characters'));
      expect(await localStore.read('20'), isEmpty);
      expect(await localStore.readPending('20'), isEmpty);
    });

    test('an edit to a place deleted elsewhere drops the place', () async {
      final localStore = InMemoryPlacesLocalStore(
        initial: {
          '20': [original],
        },
      );
      final repository = _repository(
        httpClient: MockClient(
          (request) async => _json({'error': 'Place not found'}, 404),
        ),
        localStore: localStore,
      );

      await repository.updatePlace(
        '20',
        original,
        const PlaceInput(name: 'Fergburger', notes: 'My note'),
      );
      final sync = await repository.syncPending('20');

      expect(sync.rejections.single, contains('no longer exists'));
      expect(await localStore.read('20'), isEmpty);
    });
  });

  group('refreshPlaces with queued changes', () {
    test('lays still-queued changes over the fetched list', () async {
      final localStore = InMemoryPlacesLocalStore(
        initial: {
          '20': [
            Place.fromJson({'id': 501, 'trip_id': 20, 'name': 'Fergburger'}),
            Place.fromJson({'id': 502, 'trip_id': 20, 'name': 'Skyline'}),
          ],
        },
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          if (request.method != 'GET') {
            return _json({'error': 'Service unavailable'}, 503);
          }
          return _json({
            'places': [
              {'id': 501, 'trip_id': 20, 'name': 'Fergburger'},
              {'id': 502, 'trip_id': 20, 'name': 'Skyline'},
              {'id': 503, 'trip_id': 20, 'name': 'Onsen Hot Pools'},
            ],
          });
        }),
        localStore: localStore,
      );

      final fergburger = (await localStore.read('20')).first;
      await repository.updatePlace(
        '20',
        fergburger,
        const PlaceInput(name: 'Fergburger', notes: 'Late night'),
      );
      await repository.deletePlace('20', 502);
      await repository.createPlace('20', const PlaceInput(name: 'Cookie Time'));

      final places = await repository.refreshPlaces('20');

      expect(places.map((p) => p.name), [
        'Fergburger',
        'Onsen Hot Pools',
        'Cookie Time',
      ]);
      expect(places.first.notes, 'Late night');
      expect(places.first.syncStatus, PlaceSyncStatus.pending);
      expect(places.last.id, isNegative);
    });
  });
}
