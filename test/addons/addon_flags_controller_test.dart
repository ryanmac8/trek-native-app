import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/addons/addon_flags.dart';
import 'package:trek/addons/addon_flags_controller.dart';
import 'package:trek/addons/addon_flags_repository.dart';
import 'package:trek/addons/addons_api.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/network/api_client.dart';

import '../test_helpers.dart';
import 'addon_fixtures.dart';

const _server = 'https://trek.example.com';

void main() {
  late InMemoryAddonFlagsLocalStore store;

  setUp(() => store = InMemoryAddonFlagsLocalStore());

  ProviderContainer container(MockClientHandler handler) {
    final repository = AddonFlagsRepository(
      addonsApi: AddonsApi(
        apiClient: ApiClient(baseUrl: _server, httpClient: MockClient(handler)),
      ),
      localStore: store,
      cacheScope: () async => _server,
      clock: () => DateTime.utc(2026, 10, 7, 9),
    );
    final c = ProviderContainer(
      overrides: [addonFlagsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(c.dispose);
    return c;
  }

  http.Response ok(Map<String, dynamic> body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  void cache(Map<String, dynamic> body) {
    store.entries[_server] = CachedAddonFlags(
      flags: AddonFlags.fromJson(body),
      fetchedAt: DateTime.utc(2026, 10, 1),
    );
  }

  test('starts on fresh-install defaults without waiting on anything', () {
    final c = container((_) => Completer<http.Response>().future);

    final state = c.read(addonFlagsProvider);
    expect(state.source, AddonFlagsSource.defaults);
    expect(state.isEnabled(AddonIds.budget), isTrue);
    expect(state.isEnabled(AddonIds.journey), isFalse);
  });

  test('shows cached flags while the refresh is still in flight', () async {
    cache(addonsResponse(budget: false));
    final response = Completer<http.Response>();
    final c = container((_) => response.future);

    c.read(addonFlagsProvider);
    await pumpEventQueue();

    var state = c.read(addonFlagsProvider);
    expect(state.source, AddonFlagsSource.cache);
    expect(state.isEnabled(AddonIds.budget), isFalse);

    response.complete(ok(addonsResponse()));
    await pumpEventQueue();

    state = c.read(addonFlagsProvider);
    expect(state.source, AddonFlagsSource.server);
    expect(state.isEnabled(AddonIds.budget), isTrue);
    expect(state.fetchedAt, DateTime.utc(2026, 10, 7, 9));
    expect(state.refreshFailed, isFalse);
  });

  test(
    'offline with a cache: keeps the cached flags, flags the failure',
    () async {
      cache(addonsResponse(packing: false));
      final c = container((_) async => throw const SocketException('down'));

      c.read(addonFlagsProvider);
      await pumpEventQueue();

      final state = c.read(addonFlagsProvider);
      expect(state.source, AddonFlagsSource.cache);
      expect(state.isEnabled(AddonIds.packing), isFalse);
      expect(state.fetchedAt, DateTime.utc(2026, 10, 1));
      expect(state.refreshFailed, isTrue);
    },
  );

  test(
    'offline without a cache: stays on defaults, flags the failure',
    () async {
      final c = container((_) async => throw const SocketException('down'));

      c.read(addonFlagsProvider);
      await pumpEventQueue();

      final state = c.read(addonFlagsProvider);
      expect(state.source, AddonFlagsSource.defaults);
      expect(state.isEnabled(AddonIds.packing), isTrue);
      expect(state.refreshFailed, isTrue);
    },
  );

  test('a server error or malformed body degrades the same way', () async {
    cache(addonsResponse());
    var call = 0;
    final c = container((_) async {
      call++;
      return call == 1
          ? http.Response('{"error":"boom"}', 500)
          : http.Response('[]', 200);
    });

    c.read(addonFlagsProvider);
    await pumpEventQueue();
    expect(c.read(addonFlagsProvider).refreshFailed, isTrue);

    await c.read(addonFlagsProvider.notifier).refresh();
    final state = c.read(addonFlagsProvider);
    expect(state.refreshFailed, isTrue);
    expect(state.source, AddonFlagsSource.cache);
  });

  test('a later successful refresh clears refreshFailed', () async {
    var online = false;
    final c = container((_) async {
      if (!online) throw const SocketException('down');
      return ok(addonsResponse(budget: false));
    });

    c.read(addonFlagsProvider);
    await pumpEventQueue();
    expect(c.read(addonFlagsProvider).refreshFailed, isTrue);

    online = true;
    await c.read(addonFlagsProvider.notifier).refresh();

    final state = c.read(addonFlagsProvider);
    expect(state.refreshFailed, isFalse);
    expect(state.source, AddonFlagsSource.server);
    expect(state.isEnabled(AddonIds.budget), isFalse);
    expect(store.entries[_server], isNotNull);
  });
}
