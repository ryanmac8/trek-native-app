import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/vacay/vacay_api.dart';
import 'package:trek/vacay/vacay_local_store.dart';
import 'package:trek/vacay/vacay_repository.dart';

import 'vacay_fixtures.dart';

void main() {
  late FakeVacayServer server;
  late VacayLocalStore store;
  String? scope;

  VacayRepository buildRepository() => VacayRepository(
    vacayApi: VacayApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: server.client,
      ),
    ),
    localStore: store,
    cacheScope: () async => scope,
    clock: () => DateTime.utc(2026, 9, 25, 9),
  );

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    server = FakeVacayServer();
    store = PreferencesVacayLocalStore();
    scope = 'https://trek.example.com#1';
  });

  test('refreshPlan fetches GET /plan and GET /years', () async {
    final result = await buildRepository().refreshPlan();

    expect(
      server.requests.map((r) => '${r.method} ${r.url.path}'),
      unorderedEquals([
        'GET /api/addons/vacay/plan',
        'GET /api/addons/vacay/years',
      ]),
    );
    expect(result.value.years, [2025, 2026]);
    expect(result.fetchedAt, DateTime.utc(2026, 9, 25, 9));
  });

  test('refreshYear fetches GET /stats/:year and GET /entries/:year', () async {
    final result = await buildRepository().refreshYear(2025);

    expect(
      server.requests.map((r) => r.url.path),
      unorderedEquals([
        '/api/addons/vacay/stats/2025',
        '/api/addons/vacay/entries/2025',
      ]),
    );
    expect(result.value.year, 2025);
    expect(result.value.entries.first.date, '2025-03-02');
  });

  test('refreshes write through to the cache, per year', () async {
    final repository = buildRepository();
    expect(await repository.cachedPlan(), isNull);
    expect(await repository.cachedYear(2026), isNull);

    await repository.refreshPlan();
    await repository.refreshYear(2026);

    expect((await repository.cachedPlan())!.value.users.length, 2);
    final year = await repository.cachedYear(2026);
    expect(year!.value.stats.first.used, 4.5);
    expect(year.fetchedAt, DateTime.utc(2026, 9, 25, 9));
    expect(await repository.cachedYear(2025), isNull);
  });

  group('offline', () {
    test(
      'cached plan and year are still readable when the network is down',
      () async {
        final repository = buildRepository();
        await repository.refreshPlan();
        await repository.refreshYear(2026);
        server.offline = true;

        await expectLater(
          repository.refreshPlan(),
          throwsA(isA<NetworkException>()),
        );
        await expectLater(
          repository.refreshYear(2026),
          throwsA(isA<NetworkException>()),
        );
        expect((await repository.cachedPlan())!.value.years, [2025, 2026]);
        expect(
          (await repository.cachedYear(
            2026,
          ))!.value.companyHolidays.single.note,
          'Office closed',
        );
      },
    );

    test('cached reads never touch the network', () async {
      server.offline = true;
      final repository = buildRepository();

      expect(await repository.cachedPlan(), isNull);
      expect(await repository.cachedYear(2026), isNull);
      expect(server.requests, isEmpty);
    });

    test('a failed refresh leaves the previous snapshot intact', () async {
      final repository = buildRepository();
      await repository.refreshYear(2026);
      server.status = 500;

      await expectLater(
        repository.refreshYear(2026),
        throwsA(isA<ServerException>()),
      );
      expect((await repository.cachedYear(2026))!.value.stats.length, 2);
    });
  });

  group('cache scoping', () {
    test('a different account does not see another account\'s cache', () async {
      await buildRepository().refreshPlan();
      await buildRepository().refreshYear(2026);

      scope = 'https://trek.example.com#2';
      expect(await buildRepository().cachedPlan(), isNull);
      expect(await buildRepository().cachedYear(2026), isNull);

      scope = 'https://other.example.com#1';
      expect(await buildRepository().cachedPlan(), isNull);
    });

    test('without a session nothing is cached or read', () async {
      scope = null;
      final repository = buildRepository();

      final result = await repository.refreshPlan();

      expect(result.value.users.length, 2);
      expect(await repository.cachedPlan(), isNull);
      scope = 'https://trek.example.com#1';
      expect(await buildRepository().cachedPlan(), isNull);
    });
  });

  test('a corrupt cache entry reads as a miss', () async {
    await SharedPreferencesAsyncPlatform.instance!.setString(
      'trek.vacay.plan.https://trek.example.com#1',
      '{"value": 42}',
      const SharedPreferencesOptions(),
    );

    expect(await buildRepository().cachedPlan(), isNull);
  });
}
