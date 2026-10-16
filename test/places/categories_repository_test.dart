import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/places/categories_api.dart';
import 'package:trek/places/categories_repository.dart';
import 'package:trek/places/place.dart';

import '../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

CategoriesRepository _repository({
  required http.Client httpClient,
  InMemoryCategoriesLocalStore? localStore,
}) {
  return CategoriesRepository(
    categoriesApi: CategoriesApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: httpClient,
      ),
    ),
    localStore: localStore ?? InMemoryCategoriesLocalStore(),
  );
}

/// A row as `GET /api/categories` returns it (`SELECT * FROM categories`).
Map<String, dynamic> _row(int id, String name, String color, String icon) => {
  'id': id,
  'name': name,
  'color': color,
  'icon': icon,
  'user_id': null,
  'created_at': '2026-01-01 00:00:00',
};

void main() {
  test(
    'refreshCategories reads the real response shape and caches it',
    () async {
      final localStore = InMemoryCategoriesLocalStore();
      final repository = _repository(
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/categories');
          return _json({
            'categories': [
              _row(6, 'Activity', '#10b981', '🎯'),
              _row(11, 'Wineries', '#6366f1', 'MapPin'),
            ],
          });
        }),
        localStore: localStore,
      );

      final categories = await repository.refreshCategories();

      expect(categories.map((c) => c.name), ['Activity', 'Wineries']);
      expect(categories.first.color, '#10b981');
      expect(categories.last.emoji, isNull);
      expect((await localStore.read()).map((c) => c.id), [6, 11]);
    },
  );

  test('a response without a categories key is an empty list', () async {
    final repository = _repository(
      httpClient: MockClient((request) async => _json({})),
    );

    expect(await repository.refreshCategories(), isEmpty);
  });

  test('cachedCategories never touches the network', () async {
    final repository = _repository(
      httpClient: MockClient((request) async {
        fail('cachedCategories() should not hit the network');
      }),
      localStore: InMemoryCategoriesLocalStore(
        initial: const [PlaceCategoryRef(id: 2, name: 'Restaurant')],
      ),
    );

    expect((await repository.cachedCategories()).single.name, 'Restaurant');
  });

  group('offline', () {
    test('refreshCategories falls back to the cache', () async {
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: InMemoryCategoriesLocalStore(
          initial: const [PlaceCategoryRef(id: 2, name: 'Restaurant')],
        ),
      );

      final categories = await repository.refreshCategories();

      expect(categories.single.id, 2);
    });

    test('refreshCategories throws when nothing is cached', () async {
      final repository = _repository(
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
      );

      expect(repository.refreshCategories(), throwsA(isA<NetworkException>()));
    });
  });

  test('a server error leaves the cache untouched', () async {
    final localStore = InMemoryCategoriesLocalStore(
      initial: const [PlaceCategoryRef(id: 2, name: 'Restaurant')],
    );
    final repository = _repository(
      httpClient: MockClient((request) async => _json({'error': 'boom'}, 500)),
      localStore: localStore,
    );

    await expectLater(
      repository.refreshCategories(),
      throwsA(isA<ApiException>()),
    );
    expect((await localStore.read()).single.name, 'Restaurant');
  });
}
