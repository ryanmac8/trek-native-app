import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/journey/journey_api.dart';
import 'package:trek/journey/journey_local_store.dart';
import 'package:trek/journey/journey_repository.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';

import 'journey_fixtures.dart';

void main() {
  late FakeJourneyServer server;
  late JourneyLocalStore store;
  String? scope;

  JourneyRepository buildRepository() => JourneyRepository(
    journeyApi: JourneyApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: server.client,
      ),
    ),
    localStore: store,
    cacheScope: () async => scope,
    clock: () => DateTime.utc(2026, 9, 26, 9),
  );

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    server = FakeJourneyServer();
    store = PreferencesJourneyLocalStore();
    scope = 'https://trek.example.com#1';
  });

  test('refreshList fetches GET /api/journeys', () async {
    final result = await buildRepository().refreshList();

    expect(server.requests.map((r) => '${r.method} ${r.url.path}'), [
      'GET /api/journeys',
    ]);
    expect(result.value.journeys, hasLength(2));
    expect(result.fetchedAt, DateTime.utc(2026, 9, 26, 9));
  });

  test('refreshJourney fetches GET /api/journeys/:id', () async {
    final result = await buildRepository().refreshJourney(7);

    expect(server.requests.single.url.path, '/api/journeys/7');
    expect(result.value.title, 'South Island loop');
  });

  test('refreshes write through to the cache, per journey', () async {
    final repository = buildRepository();
    expect(await repository.cachedList(), isNull);
    expect(await repository.cachedJourney(7), isNull);

    await repository.refreshList();
    await repository.refreshJourney(7);

    expect((await repository.cachedList())!.value.journeys.first.id, 7);
    final journey = await repository.cachedJourney(7);
    expect(journey!.value.entries, hasLength(3));
    expect(journey.fetchedAt, DateTime.utc(2026, 9, 26, 9));
    expect(await repository.cachedJourney(9), isNull);
  });

  test('offline: refresh throws NetworkException, cache still reads', () async {
    final repository = buildRepository();
    await repository.refreshList();
    await repository.refreshJourney(7);

    server.offline = true;
    await expectLater(
      repository.refreshList(),
      throwsA(isA<NetworkException>()),
    );
    await expectLater(
      repository.refreshJourney(7),
      throwsA(isA<NetworkException>()),
    );

    expect((await repository.cachedList())!.value.journeys, hasLength(2));
    expect((await repository.cachedJourney(7))!.value.id, 7);
  });

  test('cached reads never touch the network', () async {
    final repository = buildRepository();
    await repository.cachedList();
    await repository.cachedJourney(7);
    expect(server.requests, isEmpty);
  });

  test('a failed refresh leaves the previous snapshot intact', () async {
    final repository = buildRepository();
    await repository.refreshList();

    server.list = {'journeys': []};
    server.offline = true;
    await expectLater(
      repository.refreshList(),
      throwsA(isA<NetworkException>()),
    );

    expect((await repository.cachedList())!.value.journeys, hasLength(2));
  });

  test('the addon gate surfaces as a 404 ServerException', () async {
    server.addonDisabled = true;
    await expectLater(
      buildRepository().refreshList(),
      throwsA(
        isA<ServerException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', contains('addon')),
      ),
    );
  });

  test('caches are separate per account and server', () async {
    await buildRepository().refreshList();

    scope = 'https://trek.example.com#2';
    expect(await buildRepository().cachedList(), isNull);

    scope = 'https://other.example.com#1';
    expect(await buildRepository().cachedList(), isNull);

    scope = 'https://trek.example.com#1';
    expect(await buildRepository().cachedList(), isNotNull);
  });

  test('without a session nothing is cached or read', () async {
    scope = null;
    final repository = buildRepository();

    final fresh = await repository.refreshList();
    expect(fresh.value.journeys, hasLength(2));
    expect(await repository.cachedList(), isNull);
    expect(await repository.cachedJourney(7), isNull);
  });

  test('a corrupt cache entry is treated as a miss', () async {
    await SharedPreferencesAsync().setString(
      'trek.journey.list.$scope',
      '{not json',
    );
    await SharedPreferencesAsync().setString(
      'trek.journey.detail.7.$scope',
      '{"value":{"id":"seven"},"fetchedAt":"2026-01-01T00:00:00Z"}',
    );

    expect(await buildRepository().cachedList(), isNull);
    expect(await buildRepository().cachedJourney(7), isNull);
  });
}
