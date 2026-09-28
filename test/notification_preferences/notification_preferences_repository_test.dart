import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/notification_preferences/notification_preferences_api.dart';
import 'package:trek/notification_preferences/notification_preferences_local_store.dart';
import 'package:trek/notification_preferences/notification_preferences_repository.dart';

import 'notification_preferences_fixtures.dart';

void main() {
  late FakePreferencesServer server;
  late NotificationPreferencesLocalStore store;
  String? scope;

  NotificationPreferencesRepository buildRepository() =>
      NotificationPreferencesRepository(
        api: NotificationPreferencesApi(
          apiClient: ApiClient(
            baseUrl: 'https://trek.example.com',
            httpClient: server.client,
          ),
        ),
        localStore: store,
        cacheScope: () async => scope,
        clock: () => DateTime.utc(2026, 9, 28, 9),
      );

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    server = FakePreferencesServer();
    store = PreferencesNotificationPreferencesLocalStore();
    scope = 'https://trek.example.com#1';
  });

  test('refresh fetches GET /api/notifications/preferences', () async {
    final result = await buildRepository().refresh();

    expect(server.requests.single.method, 'GET');
    expect(server.requests.single.url.path, '/api/notifications/preferences');
    expect(result.matrix.eventTypes, contains('trip_invite'));
    expect(result.fetchedAt, DateTime.utc(2026, 9, 28, 9));
    expect(result.hasPending, isFalse);
  });

  test('refresh writes through to the cache', () async {
    final repository = buildRepository();
    expect(await repository.cached(), isNull);

    await repository.refresh();

    final cached = await repository.cached();
    expect(cached!.matrix.visibleChannels, hasLength(4));
  });

  test('setPreference applies locally without touching the network', () async {
    final repository = buildRepository();
    await repository.refresh();
    server.requests.clear();

    final updated = await repository.setPreference(
      'trip_invite',
      'email',
      false,
    );

    expect(server.requests, isEmpty);
    expect(updated.matrix.isEnabled('trip_invite', 'email'), isFalse);
    expect(updated.serverMatrix.isEnabled('trip_invite', 'email'), isTrue);
    expect(updated.pendingCount, 1);
    expect((await repository.cached())!.pendingCount, 1);
  });

  test('setPreference coalesces repeated toggles of the same cell', () async {
    final repository = buildRepository();
    await repository.refresh();

    await repository.setPreference('trip_invite', 'email', false);
    await repository.setPreference('trip_invite', 'email', true);
    final updated = await repository.setPreference(
      'trip_invite',
      'email',
      false,
    );

    expect(updated.pending, {
      'trip_invite': {'email': false},
    });
  });

  test('setPreference throws before anything has loaded', () async {
    expect(
      () => buildRepository().setPreference('trip_invite', 'email', false),
      throwsStateError,
    );
  });

  test('syncPending PUTs only the changed cells', () async {
    final repository = buildRepository();
    await repository.refresh();
    await repository.setPreference('trip_invite', 'email', false);
    await repository.setPreference('collab_message', 'inapp', false);

    final synced = await repository.syncPending();

    final put = server.puts.single;
    expect(put.url.path, '/api/notifications/preferences');
    expect(jsonDecode(put.body), {
      'trip_invite': {'email': false},
      'collab_message': {'inapp': false},
    });
    expect(synced!.hasPending, isFalse);
    expect(synced.serverMatrix.isEnabled('trip_invite', 'email'), isFalse);
    expect(synced.serverMatrix.isEnabled('collab_message', 'inapp'), isFalse);
    expect((await repository.cached())!.hasPending, isFalse);
  });

  test('syncPending with nothing pending makes no request', () async {
    final repository = buildRepository();
    await repository.refresh();
    server.requests.clear();

    await repository.syncPending();

    expect(server.requests, isEmpty);
  });

  test('a toggle made during an in-flight sync goes out next', () async {
    final repository = buildRepository();
    await repository.refresh();
    await repository.setPreference('trip_invite', 'email', false);

    final gate = Completer<void>();
    server.putGate = gate.future;
    final sync = repository.syncPending();
    await pumpEventQueue();

    // Flip the same cell back while the first PUT is still in flight.
    await repository.setPreference('trip_invite', 'email', true);
    gate.complete();
    final synced = await sync;

    expect(server.puts.map((r) => jsonDecode(r.body)), [
      {
        'trip_invite': {'email': false},
      },
      {
        'trip_invite': {'email': true},
      },
    ]);
    expect(synced!.hasPending, isFalse);
    expect(synced.matrix.isEnabled('trip_invite', 'email'), isTrue);
    expect(server.stored['trip_invite']!['email'], isTrue);
  });

  test('concurrent syncPending calls share one run', () async {
    final repository = buildRepository();
    await repository.refresh();
    await repository.setPreference('trip_invite', 'email', false);

    await Future.wait([repository.syncPending(), repository.syncPending()]);

    expect(server.puts, hasLength(1));
  });

  test('a rejected sync drops the rejected cells and rethrows', () async {
    final repository = buildRepository();
    await repository.refresh();
    await repository.setPreference('trip_invite', 'email', false);
    server.putStatus = 400;

    await expectLater(
      repository.syncPending(),
      throwsA(isA<ValidationException>()),
    );

    final cached = (await repository.cached())!;
    expect(cached.hasPending, isFalse);
    expect(cached.matrix.isEnabled('trip_invite', 'email'), isTrue);
  });

  test('a 401 keeps the pending cells', () async {
    final repository = buildRepository();
    await repository.refresh();
    await repository.setPreference('trip_invite', 'email', false);
    server.putStatus = 401;

    await expectLater(
      repository.syncPending(),
      throwsA(isA<UnauthorizedException>()),
    );

    expect((await repository.cached())!.pendingCount, 1);
  });

  group('offline', () {
    test('cached preferences are still readable', () async {
      final repository = buildRepository();
      await repository.refresh();
      server.offline = true;

      await expectLater(repository.refresh(), throwsA(isA<NetworkException>()));

      final cached = await repository.cached();
      expect(cached!.matrix.eventTypes, hasLength(4));
    });

    test('toggles still apply locally and stay pending', () async {
      final repository = buildRepository();
      await repository.refresh();
      server.offline = true;

      final updated = await repository.setPreference(
        'booking_change',
        'webhook',
        false,
      );
      expect(updated.matrix.isEnabled('booking_change', 'webhook'), isFalse);

      await expectLater(
        repository.syncPending(),
        throwsA(isA<NetworkException>()),
      );

      final cached = (await repository.cached())!;
      expect(cached.pending, {
        'booking_change': {'webhook': false},
      });
      expect(cached.matrix.isEnabled('booking_change', 'webhook'), isFalse);
    });

    test(
      'pending toggles survive a restart and sync once back online',
      () async {
        await buildRepository().refresh();
        server.offline = true;
        final first = buildRepository();
        await first.setPreference('collab_message', 'plugin:matrix', false);
        await expectLater(
          first.syncPending(),
          throwsA(isA<NetworkException>()),
        );

        // A fresh repository over the same store (an app restart).
        server.offline = false;
        server.requests.clear();
        final restarted = buildRepository();
        final refreshed = await restarted.refresh();

        expect(jsonDecode(server.puts.single.body), {
          'collab_message': {'plugin:matrix': false},
        });
        expect(refreshed.hasPending, isFalse);
        expect(
          refreshed.matrix.isEnabled('collab_message', 'plugin:matrix'),
          isFalse,
        );
      },
    );

    test('refresh with nothing cached throws NetworkException', () async {
      server.offline = true;
      await expectLater(
        buildRepository().refresh(),
        throwsA(isA<NetworkException>()),
      );
      expect(await buildRepository().cached(), isNull);
    });
  });

  group('account scoping', () {
    test('another account never sees or syncs these changes', () async {
      final repository = buildRepository();
      await repository.refresh();
      await repository.setPreference('trip_invite', 'email', false);

      scope = 'https://trek.example.com#2';
      expect(await repository.cached(), isNull);
      server.requests.clear();
      await repository.syncPending();
      expect(server.puts, isEmpty);
    });

    test('without a session nothing is cached', () async {
      scope = null;
      final repository = buildRepository();

      final result = await repository.refresh();

      expect(result.matrix.eventTypes, isNotEmpty);
      expect(await repository.cached(), isNull);
      expect(
        () => repository.setPreference('trip_invite', 'email', false),
        throwsStateError,
      );
    });
  });
}
