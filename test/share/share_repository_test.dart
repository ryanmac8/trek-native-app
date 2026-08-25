import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/share/share_api.dart';
import 'package:trek/share/share_link.dart';
import 'package:trek/share/share_repository.dart';

import '../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

ShareRepository _repository({
  required http.Client httpClient,
  InMemoryShareLocalStore? localStore,
}) {
  return ShareRepository(
    shareApi: ShareApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: httpClient,
      ),
    ),
    localStore: localStore ?? InMemoryShareLocalStore(),
  );
}

void main() {
  group('cachedShareLink', () {
    test(
      'reads straight from the local store without touching the network',
      () async {
        final localStore = InMemoryShareLocalStore(
          initial: {'20': const ShareLink(tripId: '20', token: 'abc123')},
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            fail('cachedShareLink() should not hit the network');
          }),
          localStore: localStore,
        );

        final link = await repository.cachedShareLink('20');

        expect(link?.token, 'abc123');
      },
    );

    test('null when sharing has never been touched for this trip', () async {
      final repository = _repository(
        httpClient: MockClient((request) async {
          fail('cachedShareLink() should not hit the network');
        }),
      );

      expect(await repository.cachedShareLink('20'), isNull);
    });
  });

  group('refreshShareLink', () {
    test(
      'fetches from the network and writes the result to the cache',
      () async {
        final localStore = InMemoryShareLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({'token': 'abc123', 'share_map': true}),
          ),
          localStore: localStore,
        );

        final link = await repository.refreshShareLink('20');

        expect(link?.token, 'abc123');
        expect((await localStore.read('20'))?.token, 'abc123');
      },
    );

    test(
      'falls back to the cache on NetworkException when a link is cached',
      () async {
        final localStore = InMemoryShareLocalStore(
          initial: {'20': const ShareLink(tripId: '20', token: 'abc123')},
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: localStore,
        );

        final link = await repository.refreshShareLink('20');

        expect(link?.token, 'abc123');
      },
    );

    test(
      'rethrows NetworkException when nothing has ever been cached',
      () async {
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
        );

        expect(
          repository.refreshShareLink('20'),
          throwsA(isA<NetworkException>()),
        );
      },
    );

    test('a trip with no share link returns null, not an error', () async {
      final repository = _repository(
        httpClient: MockClient((request) async => _json({'token': null})),
      );

      expect(await repository.refreshShareLink('20'), isNull);
    });

    test('retries a pending offline enable and reconciles the token', () async {
      final localStore = InMemoryShareLocalStore(
        initial: {
          '20': const ShareLink(
            tripId: '20',
            shareBudget: true,
            needsSync: true,
          ),
        },
      );
      var postCalls = 0;
      final repository = _repository(
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            postCalls++;
            return _json({'token': 'abc123'}, 201);
          }
          return _json({'token': 'abc123', 'share_budget': true});
        }),
        localStore: localStore,
      );

      final link = await repository.refreshShareLink('20');

      expect(postCalls, 1);
      expect(link?.token, 'abc123');
      expect(link?.needsSync, isFalse);
    });

    test(
      'leaves a pending enable queued when the retry is still offline',
      () async {
        final localStore = InMemoryShareLocalStore(
          initial: {'20': const ShareLink(tripId: '20', needsSync: true)},
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: localStore,
        );

        final link = await repository.refreshShareLink('20');

        expect(link?.needsSync, isTrue);
        expect(link?.token, isNull);
      },
    );

    test(
      'retries a pending offline disable and clears the cache once it syncs',
      () async {
        final localStore = InMemoryShareLocalStore(
          initial: {
            '20': const ShareLink(
              tripId: '20',
              token: 'abc123',
              pendingDelete: true,
            ),
          },
        );
        var deleteCalls = 0;
        final repository = _repository(
          httpClient: MockClient((request) async {
            if (request.method == 'DELETE') {
              deleteCalls++;
              return _json({'success': true});
            }
            return _json({'token': null});
          }),
          localStore: localStore,
        );

        final link = await repository.refreshShareLink('20');

        expect(deleteCalls, 1);
        expect(link, isNull);
        expect(await localStore.read('20'), isNull);
      },
    );

    test(
      'leaves a pending disable tombstoned when the retry is still offline',
      () async {
        final localStore = InMemoryShareLocalStore(
          initial: {
            '20': const ShareLink(
              tripId: '20',
              token: 'abc123',
              pendingDelete: true,
            ),
          },
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: localStore,
        );

        final link = await repository.refreshShareLink('20');

        expect(link, isNull); // hidden from the UI...
        final cached = await localStore.read('20');
        expect(cached?.pendingDelete, isTrue); // ...but still queued to retry
      },
    );

    test(
      'caches for different trips stay independent through a refresh',
      () async {
        final localStore = InMemoryShareLocalStore(
          initial: {
            '21': const ShareLink(tripId: '21', token: 'other-trip-token'),
          },
        );
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({'token': 'this-trip-token'}),
          ),
          localStore: localStore,
        );

        await repository.refreshShareLink('20');

        expect((await localStore.read('20'))?.token, 'this-trip-token');
        expect((await localStore.read('21'))?.token, 'other-trip-token');
      },
    );
  });

  group('setSharing', () {
    test(
      'writes the link locally first, then reconciles with the server token',
      () async {
        final localStore = InMemoryShareLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({'token': 'abc123'}, 201),
          ),
          localStore: localStore,
        );

        final link = await repository.setSharing('20', shareBudget: true);

        expect(link.token, 'abc123');
        expect(link.needsSync, isFalse);
        expect((await localStore.read('20'))?.token, 'abc123');
      },
    );

    test('stays queued (needsSync) in the cache when offline, instead of '
        'failing or blocking', () async {
      final localStore = InMemoryShareLocalStore();
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      final link = await repository.setSharing('20', shareBudget: true);

      expect(link.needsSync, isTrue);
      expect(link.token, isNull);
      final cached = await localStore.read('20');
      expect(cached?.needsSync, isTrue);
      expect(cached?.shareBudget, isTrue);
    });

    test(
      'rolls back the optimistic write when the server rejects the request',
      () async {
        final localStore = InMemoryShareLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({'error': 'No permission'}, 403),
          ),
          localStore: localStore,
        );

        await expectLater(
          repository.setSharing('20', shareBudget: true),
          throwsA(isA<ForbiddenException>()),
        );
        expect(await localStore.read('20'), isNull);
      },
    );

    test('updating an already-enabled link keeps its token visible while '
        'the update syncs', () async {
      final localStore = InMemoryShareLocalStore(
        initial: {'20': const ShareLink(tripId: '20', token: 'abc123')},
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      final link = await repository.setSharing('20', shareBudget: true);

      expect(link.token, 'abc123');
      expect(link.needsSync, isTrue);
      expect(link.shareBudget, isTrue);
    });
  });

  group('disableSharing', () {
    test('deletes on the server, then clears the cache', () async {
      final localStore = InMemoryShareLocalStore(
        initial: {'20': const ShareLink(tripId: '20', token: 'abc123')},
      );
      var deleteCalls = 0;
      final repository = _repository(
        httpClient: MockClient((request) async {
          deleteCalls++;
          return _json({'success': true});
        }),
        localStore: localStore,
      );

      await repository.disableSharing('20');

      expect(deleteCalls, 1);
      expect(await localStore.read('20'), isNull);
    });

    test('stays tombstoned (hidden) but queued when offline, instead of '
        'failing or blocking', () async {
      final localStore = InMemoryShareLocalStore(
        initial: {'20': const ShareLink(tripId: '20', token: 'abc123')},
      );
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      await repository.disableSharing('20');

      final cached = await localStore.read('20');
      expect(cached?.pendingDelete, isTrue);
      // Retried (not lost) on the next refresh — still offline, so it stays
      // tombstoned and nothing else is left to show.
      expect(await repository.refreshShareLink('20'), isNull);
      expect((await localStore.read('20'))?.pendingDelete, isTrue);
    });

    test('restores the link when the server rejects the delete', () async {
      final localStore = InMemoryShareLocalStore(
        initial: {'20': const ShareLink(tripId: '20', token: 'abc123')},
      );
      final repository = _repository(
        httpClient: MockClient(
          (request) async => _json({'error': 'No permission'}, 403),
        ),
        localStore: localStore,
      );

      await expectLater(
        repository.disableSharing('20'),
        throwsA(isA<ForbiddenException>()),
      );
      final cached = await localStore.read('20');
      expect(cached?.token, 'abc123');
      expect(cached?.pendingDelete, isFalse);
    });

    test('a no-op when sharing is not currently enabled', () async {
      final repository = _repository(
        httpClient: MockClient((request) async {
          fail(
            'disableSharing() with nothing cached should not hit the '
            'network',
          );
        }),
      );

      await repository.disableSharing('20');
    });
  });
}
