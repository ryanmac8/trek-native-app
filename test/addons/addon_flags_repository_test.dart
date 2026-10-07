import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/addons/addon_flags.dart';
import 'package:trek/addons/addon_flags_local_store.dart';
import 'package:trek/addons/addon_flags_repository.dart';
import 'package:trek/addons/addons_api.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';

import '../test_helpers.dart';
import 'addon_fixtures.dart';

const _server = 'https://trek.example.com';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late InMemoryAddonFlagsLocalStore store;
  final fetchedAt = DateTime.utc(2026, 10, 7, 9);

  setUp(() => store = InMemoryAddonFlagsLocalStore());

  AddonFlagsRepository repo(
    MockClientHandler handler, {
    String? scope = _server,
  }) {
    return AddonFlagsRepository(
      addonsApi: AddonsApi(
        apiClient: ApiClient(
          baseUrl: _server,
          httpClient: MockClient(handler),
          getAccessToken: () async => 'jwt',
        ),
      ),
      localStore: store,
      cacheScope: () async => scope,
      clock: () => fetchedAt,
    );
  }

  group('AddonsApi', () {
    test('GETs /api/addons with the bearer token', () async {
      late http.Request sent;
      final flags = await repo((request) async {
        sent = request;
        return _json(addonsResponse());
      }).refreshFlags();

      expect(sent.method, 'GET');
      expect(sent.url.toString(), '$_server/api/addons');
      expect(sent.headers['Authorization'], 'Bearer jwt');
      expect(flags.flags.isEnabled(AddonIds.journey), isTrue);
    });

    test('a non-object body is a FormatException', () {
      expect(
        repo((_) async => _json([])).refreshFlags(),
        throwsFormatException,
      );
    });

    test('a wrongly typed field is a FormatException', () {
      expect(
        repo(
          (_) async => _json({
            'addons': [
              {'id': 'atlas', 'name': 42},
            ],
          }),
        ).refreshFlags(),
        throwsFormatException,
      );
    });
  });

  group('AddonFlagsRepository', () {
    test('refreshFlags caches the fetched flags for the server', () async {
      final fresh = await repo(
        (_) async => _json(addonsResponse(budget: false)),
      ).refreshFlags();

      expect(fresh.fetchedAt, fetchedAt);
      expect(store.entries[_server]!.flags.isEnabled(AddonIds.budget), false);
    });

    test('cachedFlags reads the cache without touching the network', () async {
      store.entries[_server] = CachedAddonFlags(
        flags: AddonFlags.fromJson(addonsResponse(budget: false)),
        fetchedAt: fetchedAt,
      );
      var requests = 0;

      final cached = await repo((_) async {
        requests++;
        return _json(addonsResponse());
      }).cachedFlags();

      expect(requests, 0);
      expect(cached!.flags.isEnabled(AddonIds.budget), isFalse);
    });

    test(
      'offline: refresh throws NetworkException and keeps the cache',
      () async {
        final previous = CachedAddonFlags(
          flags: AddonFlags.fromJson(addonsResponse()),
          fetchedAt: DateTime.utc(2026, 10, 1),
        );
        store.entries[_server] = previous;
        final offline = repo((_) async => throw const SocketException('down'));

        await expectLater(
          offline.refreshFlags(),
          throwsA(isA<NetworkException>()),
        );
        expect(store.entries[_server], same(previous));
        expect((await offline.cachedFlags())!.fetchedAt, previous.fetchedAt);
      },
    );

    test('caches per server', () async {
      store.entries['https://other.example.com'] = CachedAddonFlags(
        flags: AddonFlags.fromJson(addonsResponse()),
        fetchedAt: fetchedAt,
      );

      expect(await repo((_) async => _json({})).cachedFlags(), isNull);
    });

    test('without a configured server nothing is cached', () async {
      final noServer = repo((_) async => _json(addonsResponse()), scope: null);

      expect(await noServer.cachedFlags(), isNull);
      await noServer.refreshFlags();
      expect(store.entries, isEmpty);
    });

    test('a failing local store never fails reads or refreshes', () async {
      store.throwOnAccess = true;
      final r = repo((_) async => _json(addonsResponse()));

      expect(await r.cachedFlags(), isNull);
      final fresh = await r.refreshFlags();
      expect(fresh.flags.isEnabled(AddonIds.atlas), isTrue);
    });
  });

  group('PreferencesAddonFlagsLocalStore', () {
    late InMemorySharedPreferencesAsync backend;

    setUp(() {
      backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
    });

    test('round-trips flags per server', () async {
      final prefsStore = PreferencesAddonFlagsLocalStore();
      await prefsStore.write(
        _server,
        CachedAddonFlags(
          flags: AddonFlags.fromJson(addonsResponse(packing: false)),
          fetchedAt: fetchedAt,
        ),
      );

      final restored = await prefsStore.read(_server);
      expect(restored!.fetchedAt, fetchedAt);
      expect(restored.flags.isEnabled(AddonIds.packing), isFalse);
      expect(await prefsStore.read('https://other.example.com'), isNull);
    });

    test('a corrupt entry reads as a cache miss', () async {
      final prefsStore = PreferencesAddonFlagsLocalStore();
      await SharedPreferencesAsync().setString(
        'trek.addons.flags.$_server',
        '{not json',
      );

      expect(await prefsStore.read(_server), isNull);
    });
  });
}
