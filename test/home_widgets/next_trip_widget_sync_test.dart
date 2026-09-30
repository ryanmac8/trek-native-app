import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/home_widgets/next_trip_widget_sync.dart';
import 'package:trek/home_widgets/widget_trip.dart';
import 'package:trek/home_widgets/widget_trip_api.dart';
import 'package:trek/network/api_client.dart';

import '../test_helpers.dart';

void main() {
  const scope = 'https://trek.example.com#5';
  final today = DateTime(2026, 9, 30);

  const upcoming = WidgetTrip(
    id: 20,
    title: 'New Zealand',
    startDate: '2026-11-02',
    endDate: '2026-11-20',
  );
  const past = WidgetTrip(
    id: 11,
    title: 'Iceland',
    startDate: '2026-06-01',
    endDate: '2026-06-08',
  );

  late InMemoryWidgetTripStore store;
  late RecordingHomeWidgetPublisher publisher;
  late List<http.Request> requests;

  setUp(() {
    store = InMemoryWidgetTripStore();
    publisher = RecordingHomeWidgetPublisher();
    requests = [];
  });

  NextTripWidgetSync build(
    Future<http.Response> Function(http.Request) handler, {
    String? cacheScope = scope,
    Future<bool> Function()? onUnauthorized,
  }) {
    final client = MockClient((request) {
      requests.add(request);
      return handler(request);
    });
    return NextTripWidgetSync(
      api: WidgetTripApi(
        apiClient: ApiClient(
          baseUrl: 'https://trek.example.com',
          httpClient: client,
          getAccessToken: () async => 'token',
          onUnauthorized: onUnauthorized,
        ),
      ),
      store: store,
      publisher: publisher,
      cacheScope: () async => cacheScope,
      clock: () => today,
    );
  }

  http.Response tripsResponse(List<WidgetTrip> trips) => http.Response(
    jsonEncode({
      'trips': [for (final t in trips) t.toJson()],
    }),
    200,
  );

  test('fetches, caches, and publishes the upcoming trips', () async {
    final sync = build((_) async => tripsResponse([past, upcoming]));

    expect(await sync.refresh(), NextTripWidgetSyncResult.fresh);

    expect(requests.single.url.path, '/api/trips');
    expect(requests.single.headers['Authorization'], 'Bearer token');
    expect(store.trips[scope], [past, upcoming]);
    expect(publisher.calls, [
      [upcoming],
    ]);
  });

  test('publishes the cached list first, then the fresh one', () async {
    store.trips[scope] = [upcoming];
    const next = WidgetTrip(id: 30, title: 'Oslo', startDate: '2026-10-03');
    final sync = build((_) async => tripsResponse([upcoming, next]));

    expect(await sync.refresh(), NextTripWidgetSyncResult.fresh);

    expect(publisher.calls, [
      [upcoming],
      [next, upcoming],
    ]);
  });

  group('offline', () {
    test('republishes the cached trips when the network is down', () async {
      store.trips[scope] = [past, upcoming];
      final sync = build((_) async => throw const SocketException('offline'));

      expect(await sync.refresh(), NextTripWidgetSyncResult.cached);

      expect(publisher.published, [upcoming]);
      expect(store.trips[scope], [past, upcoming]);
    });

    test('recomputes the candidates against today from the cache', () async {
      // Cached on an earlier day, when the Iceland trip was still ahead.
      store.trips[scope] = [past, upcoming];
      final sync = build((_) async => throw http.ClientException('offline'));

      await sync.refresh();

      expect(publisher.published, isNot(contains(past)));
    });

    test('leaves the widget alone with nothing cached', () async {
      final sync = build((_) async => throw const SocketException('offline'));

      expect(await sync.refresh(), NextTripWidgetSyncResult.unavailable);
      expect(publisher.calls, isEmpty);
    });

    test('keeps the cached publish on a server error', () async {
      store.trips[scope] = [upcoming];
      final sync = build((_) async => http.Response('{"error":"boom"}', 500));

      expect(await sync.refresh(), NextTripWidgetSyncResult.cached);
      expect(publisher.calls, [
        [upcoming],
      ]);
    });
  });

  test('clears the widget without a session and skips the network', () async {
    store.trips[scope] = [upcoming];
    final sync = build(
      (_) async => tripsResponse([upcoming]),
      cacheScope: null,
    );

    expect(await sync.refresh(), NextTripWidgetSyncResult.signedOut);
    expect(requests, isEmpty);
    expect(publisher.calls, [null]);
  });

  test('clears the widget when the server rejects the session', () async {
    store.trips[scope] = [upcoming];
    final sync = build(
      (_) async => http.Response('{"error":"Unauthorized"}', 401),
      onUnauthorized: () async => false,
    );

    expect(await sync.refresh(), NextTripWidgetSyncResult.signedOut);
    expect(publisher.calls, [
      [upcoming],
      null,
    ]);
  });

  test('shares one in-flight refresh between concurrent calls', () async {
    final sync = build((_) async => tripsResponse([upcoming]));

    final results = await Future.wait([sync.refresh(), sync.refresh()]);

    expect(results, everyElement(NextTripWidgetSyncResult.fresh));
    expect(requests, hasLength(1));
  });

  test('clear() clears the widget but keeps the cache', () async {
    store.trips[scope] = [upcoming];
    final sync = build((_) async => tripsResponse([upcoming]));

    await sync.clear();

    expect(publisher.calls, [null]);
    expect(store.trips[scope], [upcoming]);
  });
}
