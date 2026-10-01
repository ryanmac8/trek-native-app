import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/calendar_feed/calendar_feed.dart';
import 'package:trek/calendar_feed/calendar_feed_api.dart';
import 'package:trek/calendar_feed/calendar_feed_repository.dart';
import 'package:trek/network/api_client.dart';

import '../test_helpers.dart';

const _account = 'https://trek.example.com#7';
const _url = 'https://trek.example.com/api/feed/user/tok-1.ics';
const _url2 = 'https://trek.example.com/api/feed/user/tok-2.ics';

void main() {
  late InMemoryCalendarFeedStore store;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) handler;
  String? account;

  CalendarFeedRepository buildRepository() => CalendarFeedRepository(
    api: CalendarFeedApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient((request) {
          requests.add(request);
          return handler(request);
        }),
      ),
    ),
    store: store,
    account: () async => account,
    clock: () => DateTime.utc(2026, 10, 1),
  );

  http.Response feed(String? url) =>
      http.Response(jsonEncode({'feed_url': url}), 200);

  Never offline(http.Request _) => throw const SocketException('offline');

  setUp(() {
    store = InMemoryCalendarFeedStore();
    requests = [];
    account = _account;
    handler = (_) async => feed(null);
  });

  const scope = AllTripsFeedScope();

  group('refresh', () {
    test('fetches and caches the feed URL', () async {
      handler = (_) async => feed(_url);
      final result = await buildRepository().refresh(scope);

      expect(result.status, CalendarFeedSyncStatus.synced);
      expect(result.snapshot.feedUrl, _url);
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/feed/user/token');
      final cached = await buildRepository().readCached(scope);
      expect(cached!.feedUrl, _url);
      expect(cached.syncedAt, DateTime.utc(2026, 10, 1));
    });

    test('uses the trip-scoped endpoint for a trip feed', () async {
      handler = (_) async => feed(_url);
      await buildRepository().refresh(const TripFeedScope('20'));
      expect(requests.single.url.path, '/api/trips/20/feed/token');
    });

    test('keeps the cached state when offline', () async {
      await store.write(
        _account,
        scope,
        const CalendarFeedSnapshot(feedUrl: _url),
      );
      handler = offline;

      final result = await buildRepository().refresh(scope);

      expect(result.status, CalendarFeedSyncStatus.offline);
      expect(result.snapshot.feedUrl, _url);
      expect(result.snapshot.subscribableUrl, _url);
    });

    test('keeps the cached state on a 5xx', () async {
      await store.write(
        _account,
        scope,
        const CalendarFeedSnapshot(feedUrl: _url),
      );
      handler = (_) async => http.Response('{"error":"boom"}', 503);

      final result = await buildRepository().refresh(scope);
      expect(result.status, CalendarFeedSyncStatus.offline);
      expect(result.snapshot.feedUrl, _url);
    });

    test('reports forbidden and clears the cache on 403', () async {
      const tripScope = TripFeedScope('20');
      await store.write(
        _account,
        tripScope,
        const CalendarFeedSnapshot(feedUrl: _url),
      );
      handler = (_) async =>
          http.Response(jsonEncode({'error': 'No permission'}), 403);

      final result = await buildRepository().refresh(tripScope);

      expect(result.status, CalendarFeedSyncStatus.forbidden);
      expect(result.snapshot.feedUrl, isNull);
      expect((await store.read(_account, tripScope))!.feedUrl, isNull);
    });

    test('reports failure and clears the cache on 404', () async {
      const tripScope = TripFeedScope('99');
      await store.write(
        _account,
        tripScope,
        const CalendarFeedSnapshot(
          feedUrl: _url,
          pending: CalendarFeedAction.rotate,
        ),
      );
      handler = (_) async =>
          http.Response(jsonEncode({'error': 'Trip not found'}), 404);

      final result = await buildRepository().refresh(tripScope);

      expect(result.status, CalendarFeedSyncStatus.failed);
      expect(result.message, 'Trip not found');
      final cached = await store.read(_account, tripScope);
      expect(cached!.pending, isNull);
      expect(cached.feedUrl, isNull);
    });

    test('sends a pending action instead of a plain fetch', () async {
      await store.write(
        _account,
        scope,
        const CalendarFeedSnapshot(pending: CalendarFeedAction.enable),
      );
      handler = (_) async => feed(_url);

      final result = await buildRepository().refresh(scope);

      expect(requests.single.method, 'POST');
      expect(result.status, CalendarFeedSyncStatus.synced);
      expect(result.snapshot.pending, isNull);
      expect(result.snapshot.feedUrl, _url);
    });

    test('is signedOut without an account and never calls the API', () async {
      account = null;
      final result = await buildRepository().refresh(scope);
      expect(result.status, CalendarFeedSyncStatus.signedOut);
      expect(requests, isEmpty);
      expect(await buildRepository().readCached(scope), isNull);
    });

    test('scopes the cache per account', () async {
      handler = (_) async => feed(_url);
      await buildRepository().refresh(scope);

      account = 'https://trek.example.com#8';
      expect(await buildRepository().readCached(scope), isNull);
    });
  });

  group('request', () {
    test('enable POSTs and stores the minted URL', () async {
      handler = (_) async => feed(_url);
      final result = await buildRepository().request(
        scope,
        CalendarFeedAction.enable,
      );

      expect(requests.single.method, 'POST');
      expect(result.status, CalendarFeedSyncStatus.synced);
      expect(result.snapshot.subscribableUrl, _url);
    });

    test('rotate PUTs and replaces the URL', () async {
      await store.write(
        _account,
        scope,
        const CalendarFeedSnapshot(feedUrl: _url),
      );
      handler = (_) async => feed(_url2);

      final result = await buildRepository().request(
        scope,
        CalendarFeedAction.rotate,
      );

      expect(requests.single.method, 'PUT');
      expect(result.snapshot.feedUrl, _url2);
    });

    test('disable DELETEs and clears the URL', () async {
      await store.write(
        _account,
        scope,
        const CalendarFeedSnapshot(feedUrl: _url),
      );
      final result = await buildRepository().request(
        scope,
        CalendarFeedAction.disable,
      );

      expect(requests.single.method, 'DELETE');
      expect(result.snapshot.isEnabled, isFalse);
      expect(result.snapshot.feedUrl, isNull);
    });

    test(
      'offline enable is queued locally and sent on the next refresh',
      () async {
        handler = offline;
        final repository = buildRepository();

        final queued = await repository.request(
          scope,
          CalendarFeedAction.enable,
        );

        expect(queued.status, CalendarFeedSyncStatus.offline);
        expect(queued.snapshot.isEnabled, isTrue);
        expect(queued.snapshot.subscribableUrl, isNull);
        expect(
          (await repository.readCached(scope))!.pending,
          CalendarFeedAction.enable,
        );

        handler = (_) async => feed(_url);
        final synced = await repository.refresh(scope);

        expect(synced.status, CalendarFeedSyncStatus.synced);
        expect(synced.snapshot.subscribableUrl, _url);
        expect(requests.last.method, 'POST');
      },
    );

    test('offline disable clears the URL locally straight away', () async {
      await store.write(
        _account,
        scope,
        const CalendarFeedSnapshot(feedUrl: _url),
      );
      handler = offline;

      final result = await buildRepository().request(
        scope,
        CalendarFeedAction.disable,
      );

      expect(result.status, CalendarFeedSyncStatus.offline);
      expect(result.snapshot.isEnabled, isFalse);
      expect(result.snapshot.feedUrl, isNull);
    });

    test('offline rotate hides the soon-invalid URL', () async {
      await store.write(
        _account,
        scope,
        const CalendarFeedSnapshot(feedUrl: _url),
      );
      handler = offline;

      final result = await buildRepository().request(
        scope,
        CalendarFeedAction.rotate,
      );

      expect(result.snapshot.isEnabled, isTrue);
      expect(result.snapshot.subscribableUrl, isNull);
    });

    test('a newer request replaces an older pending one', () async {
      handler = offline;
      final repository = buildRepository();
      await repository.request(scope, CalendarFeedAction.enable);
      await repository.request(scope, CalendarFeedAction.disable);

      handler = (_) async => feed(null);
      await repository.refresh(scope);

      expect(requests.last.method, 'DELETE');
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
    });

    test('a 403 drops the pending action', () async {
      const tripScope = TripFeedScope('20');
      handler = (_) async =>
          http.Response(jsonEncode({'error': 'No permission'}), 403);

      final result = await buildRepository().request(
        tripScope,
        CalendarFeedAction.enable,
      );

      expect(result.status, CalendarFeedSyncStatus.forbidden);
      expect((await store.read(_account, tripScope))!.pending, isNull);
    });

    test('concurrent calls are serialized', () async {
      handler = (request) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return feed(request.method == 'DELETE' ? null : _url);
      };
      final repository = buildRepository();

      await Future.wait([
        repository.request(scope, CalendarFeedAction.enable),
        repository.request(scope, CalendarFeedAction.disable),
      ]);

      expect(requests.map((r) => r.method), ['POST', 'DELETE']);
      expect((await repository.readCached(scope))!.feedUrl, isNull);
    });
  });

  group('CalendarFeedSnapshot', () {
    test('round-trips through JSON', () {
      final snapshot = CalendarFeedSnapshot(
        feedUrl: _url,
        pending: CalendarFeedAction.rotate,
        syncedAt: DateTime.utc(2026, 10, 1),
      );
      final restored = CalendarFeedSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
      );
      expect(restored.feedUrl, _url);
      expect(restored.pending, CalendarFeedAction.rotate);
      expect(restored.syncedAt, DateTime.utc(2026, 10, 1));
    });

    test('ignores an unknown pending action', () {
      final restored = CalendarFeedSnapshot.fromJson({
        'feed_url': _url,
        'pending': 'explode',
      });
      expect(restored.pending, isNull);
      expect(restored.subscribableUrl, _url);
    });
  });
}
