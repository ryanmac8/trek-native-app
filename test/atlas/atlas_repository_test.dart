import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:trek/atlas/atlas_api.dart';
import 'package:trek/atlas/atlas_local_store.dart';
import 'package:trek/atlas/atlas_models.dart';
import 'package:trek/atlas/atlas_repository.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';

import 'atlas_fixtures.dart';

/// Backend state for a [MockClient]: either serves [body] or, when
/// [offline], fails the connection the way a dead network does.
class _FakeServer {
  bool offline = false;
  int status = 200;
  Map<String, dynamic> body = fullStatsJson();
  final requests = <http.Request>[];

  MockClient get client => MockClient((request) async {
    requests.add(request);
    if (offline) throw const SocketException('Network is unreachable');
    return http.Response(jsonEncode(body), status);
  });
}

void main() {
  late _FakeServer server;
  late AtlasLocalStore store;
  String? scope;

  AtlasRepository buildRepository() => AtlasRepository(
    atlasApi: AtlasApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: server.client,
      ),
    ),
    localStore: store,
    cacheScope: () async => scope,
    clock: () => DateTime.utc(2026, 9, 24, 9),
  );

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    server = _FakeServer();
    store = PreferencesAtlasLocalStore();
    scope = 'https://trek.example.com#1';
  });

  test('refreshStats fetches GET /api/addons/atlas/stats', () async {
    final result = await buildRepository().refreshStats();

    expect(server.requests.single.method, 'GET');
    expect(server.requests.single.url.path, '/api/addons/atlas/stats');
    expect(result.stats.totalTrips, 5);
    expect(result.fetchedAt, DateTime.utc(2026, 9, 24, 9));
  });

  test('refreshStats writes through to the cache', () async {
    final repository = buildRepository();
    expect(await repository.cachedStats(), isNull);

    await repository.refreshStats();

    final cached = await repository.cachedStats();
    expect(cached!.stats.totalPlaces, 17);
    expect(cached.fetchedAt, DateTime.utc(2026, 9, 24, 9));
  });

  group('offline', () {
    test('cached stats are still readable when the network is down', () async {
      final repository = buildRepository();
      await repository.refreshStats();
      server.offline = true;

      await expectLater(
        repository.refreshStats(),
        throwsA(isA<NetworkException>()),
      );
      final cached = await repository.cachedStats();
      expect(cached!.stats.nextTrip!.title, 'Japan');
    });

    test('cachedStats never touches the network', () async {
      server.offline = true;
      final repository = buildRepository();

      expect(await repository.cachedStats(), isNull);
      expect(server.requests, isEmpty);
    });

    test('a failed refresh leaves the previous snapshot intact', () async {
      final repository = buildRepository();
      await repository.refreshStats();
      server.status = 500;
      server.body = {'error': 'boom'};

      await expectLater(
        repository.refreshStats(),
        throwsA(isA<ServerException>()),
      );
      expect((await repository.cachedStats())!.stats.totalTrips, 5);
    });
  });

  group('cache scoping', () {
    test('a different account does not see another account\'s cache', () async {
      await buildRepository().refreshStats();

      scope = 'https://trek.example.com#2';
      expect(await buildRepository().cachedStats(), isNull);

      scope = 'https://other.example.com#1';
      expect(await buildRepository().cachedStats(), isNull);
    });

    test('without a session nothing is cached or read', () async {
      scope = null;
      final repository = buildRepository();

      final result = await repository.refreshStats();

      expect(result.stats.totalTrips, 5);
      expect(await repository.cachedStats(), isNull);
      scope = 'https://trek.example.com#1';
      expect(await buildRepository().cachedStats(), isNull);
    });
  });

  test('a corrupt cache entry reads as a miss', () async {
    await SharedPreferencesAsyncPlatform.instance!.setString(
      'trek.atlas.stats.https://trek.example.com#1',
      '{"stats": 42}',
      const SharedPreferencesOptions(),
    );

    expect(await buildRepository().cachedStats(), isNull);
  });

  test('parses the zero-trip response end to end', () async {
    server.body = zeroTripStatsJson();

    final result = await buildRepository().refreshStats();

    expect(result.stats.totalTrips, 0);
    expect(result.stats.countries.single.status, VisitStatus.visited);
  });
}
