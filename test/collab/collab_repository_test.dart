import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/collab/collab_api.dart';
import 'package:trek/collab/collab_note.dart';
import 'package:trek/collab/collab_repository.dart';
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

CollabRepository _repository({
  required http.Client httpClient,
  InMemoryCollabLocalStore? localStore,
}) {
  return CollabRepository(
    collabApi: CollabApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: httpClient,
      ),
    ),
    localStore: localStore ?? InMemoryCollabLocalStore(),
  );
}

void main() {
  group('cachedNotes', () {
    test(
      'reads straight from the local store without touching the network',
      () async {
        final localStore = InMemoryCollabLocalStore(
          initial: {
            '20': [
              CollabNote.fromJson({
                'id': 1,
                'trip_id': 20,
                'title': 'Cached note',
              }, tripId: '20'),
            ],
          },
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            fail('cachedNotes() should not hit the network');
          }),
          localStore: localStore,
        );

        final notes = await repository.cachedNotes('20');

        expect(notes, hasLength(1));
        expect(notes.single.title, 'Cached note');
      },
    );
  });

  group('refreshNotes', () {
    test(
      'fetches from the network and writes the result to the cache',
      () async {
        final localStore = InMemoryCollabLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({
              'notes': [
                {'id': 1, 'trip_id': 20, 'title': 'Packing reminders'},
              ],
            }),
          ),
          localStore: localStore,
        );

        final notes = await repository.refreshNotes('20');

        expect(notes.single.title, 'Packing reminders');
        expect((await localStore.read('20')).single.title, 'Packing reminders');
      },
    );

    test(
      'falls back to the cache on NetworkException when notes are cached',
      () async {
        final localStore = InMemoryCollabLocalStore(
          initial: {
            '20': [
              CollabNote.fromJson({
                'id': 1,
                'trip_id': 20,
                'title': 'Cached note',
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

        final notes = await repository.refreshNotes('20');

        expect(notes.single.title, 'Cached note');
      },
    );

    test('rethrows NetworkException when the cache is empty', () async {
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
      );

      expect(repository.refreshNotes('20'), throwsA(isA<NetworkException>()));
    });

    test(
      'a trip with no notes yet returns an empty list, not an error',
      () async {
        final repository = _repository(
          httpClient: MockClient((request) async => _json({'notes': []})),
        );

        final notes = await repository.refreshNotes('20');

        expect(notes, isEmpty);
      },
    );

    test('retries a pending offline-created note and reconciles it', () async {
      final localStore = InMemoryCollabLocalStore(
        initial: {
          '20': [
            const CollabNote(localId: 'local-1', tripId: '20', title: 'Draft'),
          ],
        },
      );
      var createCalls = 0;
      final repository = _repository(
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            createCalls++;
            return _json({
              'note': {'id': 42, 'trip_id': 20, 'title': 'Draft'},
            }, 201);
          }
          return _json({'notes': []});
        }),
        localStore: localStore,
      );

      final notes = await repository.refreshNotes('20');

      expect(createCalls, 1);
      expect(notes.single.id, 42);
      expect(notes.single.localId, 'local-1');
      expect(notes.single.isPending, isFalse);
    });

    test(
      'leaves a pending note queued when the retry is still offline',
      () async {
        final localStore = InMemoryCollabLocalStore(
          initial: {
            '20': [
              const CollabNote(
                localId: 'local-1',
                tripId: '20',
                title: 'Draft',
              ),
            ],
          },
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: localStore,
        );

        final notes = await repository.refreshNotes('20');

        expect(notes.single.isPending, isTrue);
        expect(notes.single.localId, 'local-1');
      },
    );

    test(
      'caches for different trips stay independent through a refresh',
      () async {
        final localStore = InMemoryCollabLocalStore(
          initial: {
            '21': [
              CollabNote.fromJson({
                'id': 9,
                'trip_id': 21,
                'title': 'Other trip note',
              }, tripId: '21'),
            ],
          },
        );
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({
              'notes': [
                {'id': 1, 'trip_id': 20, 'title': 'This trip note'},
              ],
            }),
          ),
          localStore: localStore,
        );

        await repository.refreshNotes('20');

        expect((await localStore.read('20')).single.title, 'This trip note');
        expect((await localStore.read('21')).single.title, 'Other trip note');
      },
    );
  });

  group('createNote', () {
    test(
      'writes the note locally first, then reconciles with the server id',
      () async {
        final localStore = InMemoryCollabLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({
              'note': {
                'id': 7,
                'trip_id': 20,
                'title': 'Packing reminders',
                'content': 'Bring sunscreen',
              },
            }, 201),
          ),
          localStore: localStore,
        );

        final note = await repository.createNote(
          '20',
          title: 'Packing reminders',
          content: 'Bring sunscreen',
        );

        expect(note.id, 7);
        expect(note.isPending, isFalse);
        final cached = await localStore.read('20');
        expect(cached, hasLength(1));
        expect(cached.single.id, 7);
      },
    );

    test('stays queued as a pending note in the cache when offline, instead of '
        'failing or blocking', () async {
      final localStore = InMemoryCollabLocalStore();
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      final note = await repository.createNote('20', title: 'Draft');

      expect(note.isPending, isTrue);
      expect(note.title, 'Draft');
      final cached = await localStore.read('20');
      expect(cached, hasLength(1));
      expect(cached.single.isPending, isTrue);
    });

    test(
      'rolls back the optimistic write when the server rejects the request',
      () async {
        final localStore = InMemoryCollabLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({'error': 'Title is required'}, 400),
          ),
          localStore: localStore,
        );

        await expectLater(
          repository.createNote('20', title: ''),
          throwsA(isA<ValidationException>()),
        );
        expect(await localStore.read('20'), isEmpty);
      },
    );
  });
}
