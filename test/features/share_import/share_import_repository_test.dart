import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/features/share_import/share_import_api.dart';
import 'package:trek/features/share_import/share_import_repository.dart';
import 'package:trek/features/share_import/share_import_store.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/share_intake/shared_map_link.dart';

import '../../test_helpers.dart';

const _server = 'https://trek.example.com';
const _trip = ShareTargetTrip(id: 20, title: 'New Zealand');

/// A fake Trek server. Each handler returns a response, or throws
/// [SocketException] to simulate being offline.
class _FakeServer {
  bool offline = false;
  http.Response Function(Map<String, dynamic> body) resolve = (_) =>
      _json(200, {
        'lat': -36.8485,
        'lng': 174.7622,
        'name': 'Sky Tower',
        'address': 'Victoria St W, Auckland',
        'google_ftid': '0x6d0d:0x1',
      });
  http.Response Function(int tripId, Map<String, dynamic> body) create =
      (_, body) => _json(201, {
        'place': {'id': 501, 'name': body['name']},
      });
  http.Response Function() trips = () => _json(200, {
    'trips': [
      {
        'id': 20,
        'title': 'New Zealand',
        'start_date': '2026-11-01',
        'end_date': '2026-11-14',
        'place_count': 3,
      },
    ],
  });

  final resolveCalls = <Map<String, dynamic>>[];
  final createCalls = <(int, Map<String, dynamic>)>[];

  late final client = MockClient((request) async {
    if (offline) throw const SocketException('offline');
    final path = request.url.path;
    if (request.method == 'GET' && path == '/api/trips') return trips();
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (path == '/api/maps/resolve-url') {
      resolveCalls.add(body);
      return resolve(body);
    }
    final match = RegExp(r'^/api/trips/(\d+)/places$').firstMatch(path);
    if (request.method == 'POST' && match != null) {
      final tripId = int.parse(match.group(1)!);
      createCalls.add((tripId, body));
      return create(tripId, body);
    }
    return _json(404, {'error': 'Not found'});
  });
}

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late _FakeServer server;
  late InMemoryShareImportStore store;
  late String? currentServer;
  late ShareImportRepository repository;
  var nextId = 0;

  setUp(() {
    server = _FakeServer();
    store = InMemoryShareImportStore();
    currentServer = _server;
    repository = ShareImportRepository(
      api: ShareImportApi(
        apiClient: ApiClient(baseUrl: _server, httpClient: server.client),
      ),
      store: store,
      currentServer: () async => currentServer,
      newId: () => 'id-${nextId++}',
    );
  });

  final shortLink = SharedMapLink.parse(
    'Sky Tower\nhttps://maps.app.goo.gl/abc',
  )!;
  final longLink = SharedMapLink.parse(
    'https://www.google.com/maps/place/Sky+Tower/@-36.8484,174.7621,17z',
  )!;

  group('trips', () {
    test('refreshTrips fetches and caches per server', () async {
      final trips = await repository.refreshTrips();

      expect(trips.single.title, 'New Zealand');
      expect(trips.single.startDate, '2026-11-01');
      expect((await repository.cachedTrips())!.single.id, 20);
      expect(store.trips.keys, [_server]);
    });

    test(
      'offline: refresh throws NetworkException, cache still reads',
      () async {
        await repository.refreshTrips();
        server.offline = true;

        await expectLater(
          repository.refreshTrips(),
          throwsA(isA<NetworkException>()),
        );
        expect((await repository.cachedTrips())!.single.title, 'New Zealand');
      },
    );

    test('the cache is scoped to the configured server', () async {
      await repository.refreshTrips();
      currentServer = 'https://other.example.com';

      expect(await repository.cachedTrips(), isNull);
    });
  });

  group('importLink', () {
    test('online: resolves on the server and creates the place', () async {
      final outcome = await repository.importLink(
        trip: _trip,
        link: shortLink,
        name: '',
      );

      expect(outcome, isA<PlaceAdded>());
      expect((outcome as PlaceAdded).placeId, 501);
      expect(outcome.name, 'Sky Tower');
      expect(server.resolveCalls.single, {
        'url': 'https://maps.app.goo.gl/abc',
      });
      final (tripId, body) = server.createCalls.single;
      expect(tripId, 20);
      expect(body, {
        'name': 'Sky Tower',
        'lat': -36.8485,
        'lng': 174.7622,
        'address': 'Victoria St W, Auckland',
        'google_ftid': '0x6d0d:0x1',
      });
      expect(store.pending, isEmpty);
    });

    test('a name the user entered wins over the resolved one', () async {
      final outcome = await repository.importLink(
        trip: _trip,
        link: shortLink,
        name: '  The tall one  ',
      );

      expect((outcome as PlaceAdded).name, 'The tall one');
      expect(server.createCalls.single.$2['name'], 'The tall one');
    });

    test('offline: queued locally with locally-parsed data', () async {
      server.offline = true;

      final outcome = await repository.importLink(
        trip: _trip,
        link: longLink,
        name: 'Sky Tower',
      );

      expect(outcome, isA<ImportQueued>());
      final queued = store.pending.single;
      expect(queued.serverUrl, _server);
      expect(queued.tripId, 20);
      expect(queued.tripTitle, 'New Zealand');
      expect(queued.url, longLink.url);
      expect(queued.lat, -36.8484);
      expect(queued.lng, 174.7621);
      expect(await repository.pendingCount(), 1);
    });

    test('unresolvable link falls back to local coordinates', () async {
      server.resolve = (_) =>
          _json(400, {'error': 'Could not extract coordinates from URL'});

      final outcome = await repository.importLink(trip: _trip, link: longLink);

      expect(outcome, isA<PlaceAdded>());
      expect(server.createCalls.single.$2, {
        'name': 'Sky Tower',
        'lat': -36.8484,
        'lng': 174.7621,
      });
    });

    test('no coordinates anywhere: created without a location, link in '
        'notes, fallback name', () async {
      server.resolve = (_) =>
          _json(400, {'error': 'Could not extract coordinates from URL'});
      final bare = SharedMapLink.parse('https://maps.app.goo.gl/zzz')!;

      final outcome = await repository.importLink(trip: _trip, link: bare);

      expect((outcome as PlaceAdded).name, fallbackPlaceName);
      expect(server.createCalls.single.$2, {
        'name': fallbackPlaceName,
        'notes': 'https://maps.app.goo.gl/zzz',
      });
    });

    test('trip gone (404) fails and is not queued', () async {
      server.create = (_, _) => _json(404, {'error': 'Trip not found'});

      final outcome = await repository.importLink(trip: _trip, link: shortLink);

      expect((outcome as ImportFailed).message, 'Trip not found');
      expect(store.pending, isEmpty);
    });

    test('no permission (403) fails and is not queued', () async {
      server.create = (_, _) => _json(403, {'error': 'No permission'});

      final outcome = await repository.importLink(trip: _trip, link: shortLink);

      expect((outcome as ImportFailed).message, 'No permission');
      expect(store.pending, isEmpty);
    });

    test('a transient server error (503) keeps it queued', () async {
      server.create = (_, _) => _json(503, {'error': 'Unavailable'});

      final outcome = await repository.importLink(trip: _trip, link: shortLink);

      expect(outcome, isA<ImportQueued>());
      expect(store.pending, hasLength(1));
    });

    test('no server configured fails without touching the queue', () async {
      currentServer = null;

      final outcome = await repository.importLink(trip: _trip, link: shortLink);

      expect(outcome, isA<ImportFailed>());
      expect(store.pending, isEmpty);
    });
  });

  group('flushPending', () {
    test('sends queued imports once back online', () async {
      server.offline = true;
      await repository.importLink(trip: _trip, link: shortLink);
      await repository.importLink(trip: _trip, link: longLink, name: 'Two');
      server.offline = false;

      final report = await repository.flushPending();

      expect(report.added, ['Sky Tower', 'Two']);
      expect(report.rejected, isEmpty);
      expect(report.remaining, 0);
      expect(store.pending, isEmpty);
      expect(server.createCalls, hasLength(2));
    });

    test('still offline: stops at the first failure, nothing lost', () async {
      server.offline = true;
      await repository.importLink(trip: _trip, link: shortLink);
      await repository.importLink(trip: _trip, link: longLink);

      final report = await repository.flushPending();

      expect(report.added, isEmpty);
      expect(report.remaining, 2);
      expect(store.pending, hasLength(2));
    });

    test('drops refused imports and reports them', () async {
      server.offline = true;
      await repository.importLink(trip: _trip, link: shortLink);
      server.offline = false;
      server.create = (_, _) => _json(404, {'error': 'Trip not found'});

      final report = await repository.flushPending();

      expect(report.rejected.single, contains('New Zealand'));
      expect(report.rejected.single, contains('Trip not found'));
      expect(store.pending, isEmpty);
    });

    test('only sends imports made against the current server', () async {
      store.pending = [
        const PendingPlaceImport(
          id: 'other',
          serverUrl: 'https://other.example.com',
          tripId: 9,
          tripTitle: 'Elsewhere',
          url: 'https://maps.app.goo.gl/other',
          provider: MapLinkProvider.google,
        ),
      ];

      final report = await repository.flushPending();

      expect(report.added, isEmpty);
      expect(server.createCalls, isEmpty);
      expect(store.pending.single.id, 'other');
    });

    test('concurrent flushes never send the same import twice', () async {
      server.offline = true;
      await repository.importLink(trip: _trip, link: shortLink);
      server.offline = false;

      await Future.wait([repository.flushPending(), repository.flushPending()]);

      expect(server.createCalls, hasLength(1));
      expect(store.pending, isEmpty);
    });
  });
}
