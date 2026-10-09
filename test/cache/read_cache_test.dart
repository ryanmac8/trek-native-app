import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trek/cache/cache_entry.dart';
import 'package:trek/cache/cache_policy.dart';
import 'package:trek/cache/read_cache.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';

import '../test_helpers.dart';

/// A scripted server: each fetch pops the next response (or throws it, if
/// it's an exception) and records the ETag it was sent.
class FakeServer {
  final List<Object> responses = [];
  final List<String?> sentEtags = [];
  Completer<void>? gate;

  Future<ConditionalResponse> fetch(String? etag) async {
    sentEtags.add(etag);
    if (gate != null) await gate!.future;
    final next = responses.removeAt(0);
    if (next is ConditionalResponse) return next;
    throw next;
  }
}

Modified tripsBody(List<String> titles, {String? etag}) => Modified({
  'trips': [
    for (final title in titles) {'title': title},
  ],
}, etag);

List<String> decodeTrips(Object? json) => [
  for (final trip in (json as Map<String, dynamic>)['trips'] as List)
    (trip as Map<String, dynamic>)['title'] as String,
];

Object? encodeTrips(List<String> titles) => {
  'trips': [
    for (final title in titles) {'title': title},
  ],
};

void main() {
  late InMemoryCacheStore store;
  late FakeServer server;
  late String? scope;
  late DateTime now;
  late ReadCache cache;

  CacheResource<List<String>> trips({
    String key = 'trips',
    CachePolicy policy = CachePolicy.standard,
  }) => CacheResource<List<String>>(
    key: key,
    fetch: server.fetch,
    decode: decodeTrips,
    encode: encodeTrips,
    policy: policy,
  );

  ReadCache newCache() =>
      ReadCache(store: store, scope: () async => scope, clock: () => now);

  setUp(() {
    store = InMemoryCacheStore();
    server = FakeServer();
    scope = 'https://trek.example.com#7';
    now = DateTime.utc(2026, 10, 9, 12);
    cache = newCache();
  });

  tearDown(() => cache.dispose());

  group('read', () {
    test('is a miss with nothing cached and never fetches', () async {
      final snapshot = await cache.read(trips());

      expect(snapshot.hasData, isFalse);
      expect(snapshot.source, CacheSource.none);
      expect(server.sentEtags, isEmpty);
    });

    test('serves entries persisted by an earlier session', () async {
      server.responses.add(tripsBody(['Japan'], etag: 'W/"1"'));
      await cache.refresh(trips());

      final later = newCache();
      final snapshot = await later.read(trips());
      later.dispose();

      expect(snapshot.data, ['Japan']);
      expect(snapshot.source, CacheSource.cache);
      expect(snapshot.fetchedAt, now);
    });

    test('discards an entry written under another schema version', () async {
      server.responses.add(tripsBody(['Japan']));
      await cache.refresh(trips());

      final snapshot = await cache.read(
        trips(policy: const CachePolicy(schemaVersion: 2)),
      );

      expect(snapshot.hasData, isFalse);
      expect(store.entries, isEmpty);
    });

    test('treats an undecodable cached entry as a miss', () async {
      store.entries['https://trek.example.com#7|trips'] = CacheEntry(
        data: 'not a trip list',
        fetchedAt: now,
        schemaVersion: 1,
      );

      expect((await cache.read(trips())).hasData, isFalse);
    });

    test('treats a storage read failure as a miss', () async {
      store.failReads = true;

      expect((await cache.read(trips())).hasData, isFalse);
    });

    test('is stale once maxAge has passed', () async {
      server.responses.add(tripsBody(['Japan']));
      final resource = trips(
        policy: const CachePolicy(maxAge: Duration(minutes: 10)),
      );
      await cache.refresh(resource);

      now = now.add(const Duration(minutes: 9));
      expect((await cache.read(resource)).isStale, isFalse);

      now = now.add(const Duration(minutes: 1));
      final stale = await cache.read(resource);
      expect(stale.isStale, isTrue);
      expect(stale.data, ['Japan']);
    });
  });

  group('refresh', () {
    test('caches a 200 body with its ETag', () async {
      server.responses.add(tripsBody(['Japan'], etag: 'W/"1"'));

      final snapshot = await cache.refresh(trips());

      expect(snapshot.data, ['Japan']);
      expect(snapshot.source, CacheSource.server);
      expect(snapshot.refreshError, isNull);
      final stored = store.entries['https://trek.example.com#7|trips']!;
      expect(stored.etag, 'W/"1"');
      expect(server.sentEtags, [null]);
    });

    test('revalidates with the stored ETag; a 304 keeps the data and '
        'resets its age', () async {
      server.responses.addAll([
        tripsBody(['Japan'], etag: 'W/"1"'),
        const NotModified(),
      ]);
      final resource = trips(
        policy: const CachePolicy(maxAge: Duration(minutes: 5)),
      );
      await cache.refresh(resource);
      await cache.invalidate('trips');
      now = now.add(const Duration(hours: 1));

      final snapshot = await cache.refresh(resource);

      expect(server.sentEtags, [null, 'W/"1"']);
      expect(snapshot.data, ['Japan']);
      expect(snapshot.fetchedAt, now);
      expect(snapshot.isStale, isFalse);
    });

    test('offline: keeps the cached data and reports the failure', () async {
      server.responses.addAll([
        tripsBody(['Japan']),
        const NetworkException(),
      ]);
      await cache.refresh(trips());

      final snapshot = await cache.refresh(trips());

      expect(snapshot.data, ['Japan']);
      expect(snapshot.isOffline, isTrue);
    });

    test('offline with nothing cached: an explicit offline state', () async {
      server.responses.add(const NetworkException());

      final snapshot = await cache.refresh(trips());

      expect(snapshot.hasData, isFalse);
      expect(snapshot.isOffline, isTrue);
    });

    test('a 401 keeps the cached data', () async {
      server.responses.addAll([
        tripsBody(['Japan']),
        const UnauthorizedException(),
      ]);
      await cache.refresh(trips());

      final snapshot = await cache.refresh(trips());

      expect(snapshot.data, ['Japan']);
      expect(snapshot.refreshError, isA<UnauthorizedException>());
    });

    test('a 5xx keeps the cached data', () async {
      server.responses.addAll([
        tripsBody(['Japan']),
        const ServerException(503, 'Unavailable'),
      ]);
      await cache.refresh(trips());

      expect((await cache.refresh(trips())).data, ['Japan']);
    });

    test('a 404 evicts the entry', () async {
      server.responses.addAll([
        tripsBody(['Japan']),
        const ServerException(404, 'Trip not found'),
      ]);
      await cache.refresh(trips());

      final snapshot = await cache.refresh(trips());

      expect(snapshot.hasData, isFalse);
      expect(snapshot.refreshError, isA<ServerException>());
      expect(store.entries, isEmpty);
    });

    test('a 403 evicts the entry', () async {
      server.responses.addAll([
        tripsBody(['Japan']),
        const ForbiddenException(),
      ]);
      await cache.refresh(trips());

      expect((await cache.refresh(trips())).hasData, isFalse);
    });

    test('an undecodable body never replaces good data', () async {
      server.responses.addAll([
        tripsBody(['Japan'], etag: 'W/"1"'),
        const Modified({'unexpected': true}, 'W/"2"'),
      ]);
      await cache.refresh(trips());

      final snapshot = await cache.refresh(trips());

      expect(snapshot.data, ['Japan']);
      expect(snapshot.refreshError, isNotNull);
      expect(store.entries.values.single.etag, 'W/"1"');
    });

    test('concurrent calls share one request', () async {
      server.gate = Completer<void>();
      server.responses.add(tripsBody(['Japan']));

      final first = cache.refresh(trips());
      final second = cache.refresh(trips());
      server.gate!.complete();

      expect((await first).data, ['Japan']);
      expect((await second).data, ['Japan']);
      expect(server.sentEtags, hasLength(1));
    });

    test('a failed storage write still serves the data this session', () async {
      store.failWrites = true;
      server.responses.add(tripsBody(['Japan']));

      final snapshot = await cache.refresh(trips());

      expect(snapshot.data, ['Japan']);
      expect((await cache.read(trips())).data, ['Japan']);
    });
  });

  group('scoping', () {
    test('accounts never see each other\'s entries', () async {
      server.responses.add(tripsBody(['Japan']));
      await cache.refresh(trips());

      scope = 'https://trek.example.com#8';

      expect((await cache.read(trips())).hasData, isFalse);
    });

    test('with no scope, entries live in memory only', () async {
      scope = null;
      server.responses.add(tripsBody(['Japan']));

      final snapshot = await cache.refresh(trips());

      expect(snapshot.data, ['Japan']);
      expect(store.entries, isEmpty);
    });
  });

  group('local edits and invalidation', () {
    test(
      'put stores a local edit, keeps fetchedAt and drops the ETag',
      () async {
        server.responses.addAll([
          tripsBody(['Japan'], etag: 'W/"1"'),
          tripsBody(['Japan', 'Peru'], etag: 'W/"2"'),
        ]);
        await cache.refresh(trips());
        final fetchedAt = now;
        now = now.add(const Duration(minutes: 1));

        await cache.update(trips(), (current) => [...?current, 'Peru']);

        final snapshot = await cache.read(trips());
        expect(snapshot.data, ['Japan', 'Peru']);
        expect(snapshot.fetchedAt, fetchedAt);

        await cache.refresh(trips());
        expect(server.sentEtags.last, isNull);
      },
    );

    test('put with nothing cached starts out stale', () async {
      await cache.put(trips(), ['Peru']);

      final snapshot = await cache.read(trips());
      expect(snapshot.data, ['Peru']);
      expect(snapshot.isStale, isTrue);
    });

    test(
      'invalidatePrefix marks matching entries stale, keeping data',
      () async {
        server.responses.addAll([
          tripsBody(['Day 1']),
          tripsBody(['Day 2']),
          tripsBody(['Japan']),
        ]);
        await cache.refresh(trips(key: 'trips/20/days'));
        await cache.refresh(trips(key: 'trips/20/places'));
        await cache.refresh(trips(key: 'trips'));

        await cache.invalidatePrefix('trips/20/');

        final days = await cache.read(trips(key: 'trips/20/days'));
        expect(days.isStale, isTrue);
        expect(days.data, ['Day 1']);
        expect(
          (await cache.read(trips(key: 'trips/20/places'))).isStale,
          isTrue,
        );
        expect((await cache.read(trips(key: 'trips'))).isStale, isFalse);
      },
    );

    test('evictPrefix removes only the current scope\'s entries', () async {
      server.responses.addAll([
        tripsBody(['A']),
        tripsBody(['B']),
      ]);
      await cache.refresh(trips(key: 'trips/20/days'));
      scope = 'https://other.example.com#1';
      await cache.refresh(trips(key: 'trips/20/days'));

      await cache.evictPrefix('trips/20/');

      expect((await cache.read(trips(key: 'trips/20/days'))).hasData, isFalse);
      scope = 'https://trek.example.com#7';
      expect((await cache.read(trips(key: 'trips/20/days'))).data, ['A']);
    });

    test('clearAll removes every scope\'s entries', () async {
      server.responses.addAll([
        tripsBody(['A']),
        tripsBody(['B']),
      ]);
      await cache.refresh(trips());
      scope = 'https://other.example.com#1';
      await cache.refresh(trips());

      await cache.clearAll();

      expect(store.entries, isEmpty);
      expect((await cache.read(trips())).hasData, isFalse);
      expect((await newCache().read(trips())).hasData, isFalse);
    });
  });

  group('watch', () {
    test('emits the cache, then revalidates a stale entry', () async {
      server.responses.addAll([
        tripsBody(['Japan'], etag: 'W/"1"'),
        tripsBody(['Japan', 'Peru'], etag: 'W/"2"'),
      ]);
      await cache.refresh(trips());
      await cache.invalidate('trips');
      final later = newCache();
      addTearDown(later.dispose);

      final snapshots = await later.watch(trips()).take(3).toList();

      expect(snapshots[0].data, ['Japan']);
      expect(snapshots[0].source, CacheSource.cache);
      expect(snapshots[1].isRefreshing, isTrue);
      expect(snapshots[2].data, ['Japan', 'Peru']);
      expect(snapshots[2].source, CacheSource.server);
      expect(snapshots[2].isRefreshing, isFalse);
    });

    test('does not fetch while the entry is fresh', () async {
      server.responses.add(tripsBody(['Japan']));
      await cache.refresh(trips());
      server.sentEtags.clear();

      final first = await cache.watch(trips()).first;
      await pumpEventQueue();

      expect(first.data, ['Japan']);
      expect(server.sentEtags, isEmpty);
    });

    test(
      'offline with nothing cached ends in an explicit offline state',
      () async {
        server.responses.add(const NetworkException());

        final snapshots = await cache.watch(trips()).take(3).toList();

        expect(snapshots.first.hasData, isFalse);
        expect(snapshots.last.hasData, isFalse);
        expect(snapshots.last.isRefreshing, isFalse);
        expect(snapshots.last.isOffline, isTrue);
      },
    );

    test('offline with a stale cache keeps showing it', () async {
      server.responses.addAll([
        tripsBody(['Japan']),
        const NetworkException(),
      ]);
      await cache.refresh(trips());
      await cache.invalidate('trips');

      final snapshots = await cache.watch(trips()).take(3).toList();

      expect(snapshots.last.data, ['Japan']);
      expect(snapshots.last.isOffline, isTrue);
      expect(snapshots.last.isStale, isTrue);
    });

    test('picks up local edits made elsewhere', () async {
      server.responses.add(tripsBody(['Japan']));
      await cache.refresh(trips());
      final received = <CacheSnapshot<List<String>>>[];
      final subscription = cache.watch(trips()).listen(received.add);
      await pumpEventQueue();

      await cache.put(trips(), ['Japan', 'Peru']);
      await pumpEventQueue();
      await subscription.cancel();

      expect(received.last.data, ['Japan', 'Peru']);
    });
  });
}
