import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/tags/tag.dart';
import 'package:trek/tags/tags_api.dart';
import 'package:trek/tags/tags_repository.dart';

import '../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

TagsRepository _repository({
  required http.Client httpClient,
  InMemoryTagsLocalStore? localStore,
}) {
  return TagsRepository(
    tagsApi: TagsApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: httpClient,
      ),
    ),
    localStore: localStore ?? InMemoryTagsLocalStore(),
  );
}

void main() {
  group('cachedTags', () {
    test(
      'reads straight from the local store without touching the network',
      () async {
        final localStore = InMemoryTagsLocalStore(
          initial: [
            Tag.fromJson({'id': 1, 'user_id': 1, 'name': 'Cached Tag'}),
          ],
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            fail('cachedTags() should not hit the network');
          }),
          localStore: localStore,
        );

        final tags = await repository.cachedTags();

        expect(tags, hasLength(1));
        expect(tags.single.name, 'Cached Tag');
      },
    );
  });

  group('refreshTags', () {
    test(
      'fetches from the network and writes the result to the cache',
      () async {
        final localStore = InMemoryTagsLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({
              'tags': [
                {'id': 1, 'user_id': 1, 'name': 'Foodie'},
              ],
            }),
          ),
          localStore: localStore,
        );

        final tags = await repository.refreshTags();

        expect(tags.single.name, 'Foodie');
        expect((await localStore.read()).single.name, 'Foodie');
      },
    );

    test(
      'falls back to the cache on NetworkException when tags are cached',
      () async {
        final localStore = InMemoryTagsLocalStore(
          initial: [
            Tag.fromJson({'id': 1, 'user_id': 1, 'name': 'Cached Tag'}),
          ],
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: localStore,
        );

        final tags = await repository.refreshTags();

        expect(tags.single.name, 'Cached Tag');
      },
    );

    test('rethrows NetworkException when the cache is empty', () async {
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
      );

      expect(repository.refreshTags(), throwsA(isA<NetworkException>()));
    });

    test(
      'a user with no tags yet returns an empty list, not an error',
      () async {
        final repository = _repository(
          httpClient: MockClient((request) async => _json({'tags': []})),
        );

        final tags = await repository.refreshTags();

        expect(tags, isEmpty);
      },
    );

    test('retries a pending offline-created tag and reconciles it', () async {
      final localStore = InMemoryTagsLocalStore(
        initial: [const Tag(localId: 'local-1', name: 'Draft tag')],
      );
      var createCalls = 0;
      final repository = _repository(
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            createCalls++;
            return _json({
              'tag': {'id': 42, 'user_id': 1, 'name': 'Draft tag'},
            }, 201);
          }
          return _json({'tags': []});
        }),
        localStore: localStore,
      );

      final tags = await repository.refreshTags();

      expect(createCalls, 1);
      expect(tags.single.id, 42);
      expect(tags.single.localId, 'local-1');
      expect(tags.single.isPending, isFalse);
    });

    test(
      'leaves a pending tag queued when the retry is still offline',
      () async {
        final localStore = InMemoryTagsLocalStore(
          initial: [const Tag(localId: 'local-1', name: 'Draft tag')],
        );
        final repository = _repository(
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: localStore,
        );

        final tags = await repository.refreshTags();

        expect(tags.single.isPending, isTrue);
        expect(tags.single.localId, 'local-1');
      },
    );
  });

  group('createTag', () {
    test(
      'writes the tag locally first, then reconciles with the server id',
      () async {
        final localStore = InMemoryTagsLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({
              'tag': {
                'id': 7,
                'user_id': 1,
                'name': 'Foodie',
                'color': '#10b981',
              },
            }, 201),
          ),
          localStore: localStore,
        );

        final tag = await repository.createTag(
          name: 'Foodie',
          color: '#10b981',
        );

        expect(tag.id, 7);
        expect(tag.isPending, isFalse);
        final cached = await localStore.read();
        expect(cached, hasLength(1));
        expect(cached.single.id, 7);
      },
    );

    test('stays queued as a pending tag in the cache when offline, instead of '
        'failing or blocking', () async {
      final localStore = InMemoryTagsLocalStore();
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      final tag = await repository.createTag(name: 'Foodie');

      expect(tag.isPending, isTrue);
      expect(tag.name, 'Foodie');
      final cached = await localStore.read();
      expect(cached, hasLength(1));
      expect(cached.single.isPending, isTrue);
    });

    test(
      'rolls back the optimistic write when the server rejects the request',
      () async {
        final localStore = InMemoryTagsLocalStore();
        final repository = _repository(
          httpClient: MockClient(
            (request) async => _json({'error': 'Tag name is required'}, 400),
          ),
          localStore: localStore,
        );

        await expectLater(
          repository.createTag(name: ''),
          throwsA(isA<ValidationException>()),
        );
        expect(await localStore.read(), isEmpty);
      },
    );
  });
}
