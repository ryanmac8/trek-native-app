import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/features/trip_invites/pending_invite_store.dart';
import 'package:trek/features/trip_invites/trip_invite_api.dart';
import 'package:trek/features/trip_invites/trip_invite_repository.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';

import '../../test_helpers.dart';

const _server = 'https://trek.example.com';

void main() {
  late InMemoryPendingInviteStore store;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) handler;
  String? currentServer;

  TripInviteRepository build() {
    return TripInviteRepository(
      api: TripInviteApi(
        apiClient: ApiClient(
          baseUrl: _server,
          httpClient: MockClient((request) {
            requests.add(request);
            return handler(request);
          }),
        ),
      ),
      store: store,
      currentServer: () async => currentServer,
    );
  }

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  Future<http.Response> offline(http.Request _) =>
      throw const SocketException('offline');

  setUp(() {
    store = InMemoryPendingInviteStore();
    requests = [];
    currentServer = _server;
    handler = (_) async => json({'error': 'unexpected'}, 500);
  });

  group('lookup', () {
    test(
      'returns the previewed trip from GET /api/trip-invites/:token',
      () async {
        handler = (_) async => json({'trip_id': 20, 'title': 'New Zealand'});

        final result = await build().lookup('tok');

        expect(result, isA<InviteFound>());
        final found = result as InviteFound;
        expect(found.tripId, 20);
        expect(found.title, 'New Zealand');
        expect(requests.single.method, 'GET');
        expect(requests.single.url.path, '/api/trip-invites/tok');
      },
    );

    test('refreshes the cached title of a remembered invite', () async {
      store.invites.add(const PendingInvite(token: 'tok', server: _server));
      handler = (_) async => json({'trip_id': 20, 'title': 'New Zealand'});

      await build().lookup('tok');

      expect(store.invites.single.tripTitle, 'New Zealand');
      expect(store.invites.single.tripId, 20);
    });

    test('does not remember an invite just because it was looked up', () async {
      handler = (_) async => json({'trip_id': 20, 'title': 'New Zealand'});

      await build().lookup('tok');

      expect(store.invites, isEmpty);
    });

    test('offline, returns the cached invite instead of throwing', () async {
      store.invites.add(
        const PendingInvite(token: 'tok', server: _server, tripTitle: 'NZ'),
      );
      handler = offline;

      final result = await build().lookup('tok');

      expect(result, isA<InviteOffline>());
      expect((result as InviteOffline).cached?.tripTitle, 'NZ');
    });

    test(
      'offline with nothing cached still degrades to InviteOffline',
      () async {
        handler = offline;

        final result = await build().lookup('tok');

        expect(result, isA<InviteOffline>());
        expect((result as InviteOffline).cached, isNull);
      },
    );

    test('a 404 is InviteInvalid and drops the remembered invite', () async {
      store.invites.add(const PendingInvite(token: 'tok', server: _server));
      handler = (_) async =>
          json({'error': 'Invalid or expired invite link'}, 404);

      final result = await build().lookup('tok');

      expect(result, isA<InviteInvalid>());
      expect(
        (result as InviteInvalid).message,
        'Invalid or expired invite link',
      );
      expect(store.invites, isEmpty);
    });

    test('a 429 is a retryable InviteLookupFailed', () async {
      handler = (_) async =>
          json({'error': 'Too many attempts. Please try again later.'}, 429);

      final result = await build().lookup('tok');

      expect(result, isA<InviteLookupFailed>());
    });

    test('a 401 remembers the invite for after login and rethrows', () async {
      handler = (_) async => json({'error': 'Unauthorized'}, 401);

      await expectLater(
        build().lookup('tok'),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(store.invites.single.token, 'tok');
      expect(store.invites.single.acceptQueued, isFalse);
    });
  });

  group('accept', () {
    test('POSTs the accept and drops the local entry', () async {
      store.invites.add(
        const PendingInvite(token: 'tok', server: _server, tripTitle: 'NZ'),
      );
      handler = (_) async => json({'trip_id': 20, 'joined': true});

      final outcome = await build().accept('tok');

      expect(outcome, isA<JoinCompleted>());
      final completed = outcome as JoinCompleted;
      expect(completed.tripId, 20);
      expect(completed.joined, isTrue);
      expect(completed.tripTitle, 'NZ');
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/trip-invites/tok/accept');
      expect(store.invites, isEmpty);
    });

    test('an already-member join is still a completion', () async {
      handler = (_) async => json({'trip_id': 20, 'joined': false});

      final outcome = await build().accept('tok');

      expect((outcome as JoinCompleted).joined, isFalse);
    });

    test('offline, queues the join locally instead of failing', () async {
      store.invites.add(
        const PendingInvite(token: 'tok', server: _server, tripTitle: 'NZ'),
      );
      handler = offline;

      final outcome = await build().accept('tok');

      expect(outcome, isA<JoinQueued>());
      final queued = store.invites.single;
      expect(queued.acceptQueued, isTrue);
      expect(queued.tripTitle, 'NZ');
    });

    test('offline, queues a never-seen invite too', () async {
      handler = offline;

      await build().accept('tok');

      expect(store.invites.single.token, 'tok');
      expect(store.invites.single.server, _server);
      expect(store.invites.single.acceptQueued, isTrue);
    });

    test('a 404 is JoinInvalid and drops the entry', () async {
      store.invites.add(
        const PendingInvite(token: 'tok', server: _server, acceptQueued: true),
      );
      handler = (_) async =>
          json({'error': 'Invalid or expired invite link'}, 404);

      final outcome = await build().accept('tok');

      expect(outcome, isA<JoinInvalid>());
      expect(store.invites, isEmpty);
    });

    test('a 5xx is JoinFailed and queues nothing', () async {
      handler = (_) async => json({'error': 'boom'}, 500);

      final outcome = await build().accept('tok');

      expect(outcome, isA<JoinFailed>());
      expect(store.invites, isEmpty);
    });
  });

  group('flushQueued', () {
    test('sends queued joins for the current server only', () async {
      store.invites.addAll(const [
        PendingInvite(token: 'a', server: _server, acceptQueued: true),
        PendingInvite(token: 'b', server: _server),
        PendingInvite(
          token: 'c',
          server: 'https://other.example.com',
          acceptQueued: true,
        ),
      ]);
      handler = (_) async => json({'trip_id': 1, 'joined': true});

      final outcomes = await build().flushQueued();

      expect(outcomes.map((o) => o.token), ['a']);
      expect(requests.map((r) => r.url.path), ['/api/trip-invites/a/accept']);
      expect(store.invites.map((e) => e.token), ['b', 'c']);
    });

    test('stops at the first network failure and keeps the rest', () async {
      store.invites.addAll(const [
        PendingInvite(token: 'a', server: _server, acceptQueued: true),
        PendingInvite(token: 'b', server: _server, acceptQueued: true),
      ]);
      handler = offline;

      final outcomes = await build().flushQueued();

      expect(outcomes, isEmpty);
      expect(requests, hasLength(1));
      expect(store.invites.map((e) => e.token), ['a', 'b']);
    });

    test('drops invalid invites and keeps failed ones queued', () async {
      store.invites.addAll(const [
        PendingInvite(token: 'gone', server: _server, acceptQueued: true),
        PendingInvite(token: 'busy', server: _server, acceptQueued: true),
      ]);
      handler = (request) async => request.url.path.contains('gone')
          ? json({'error': 'Invalid or expired invite link'}, 404)
          : json({'error': 'Too many attempts.'}, 429);

      final outcomes = await build().flushQueued();

      expect(outcomes[0], isA<JoinInvalid>());
      expect(outcomes[1], isA<JoinFailed>());
      expect(store.invites.single.token, 'busy');
      expect(store.invites.single.acceptQueued, isTrue);
    });

    test('a concurrent accept and flush send the invite once', () async {
      store.invites.add(
        const PendingInvite(token: 'a', server: _server, acceptQueued: true),
      );
      handler = (_) async => json({'trip_id': 1, 'joined': true});
      final repository = build();

      await Future.wait([repository.accept('a'), repository.flushQueued()]);

      expect(requests, hasLength(1));
      expect(store.invites, isEmpty);
    });
  });

  group('remember / firstUnconfirmed / discard', () {
    test('remembers once and surfaces it as unconfirmed', () async {
      final repository = build();

      await repository.remember('tok');
      await repository.remember('tok');

      expect(store.invites, hasLength(1));
      expect((await repository.firstUnconfirmed())?.token, 'tok');
    });

    test('does not downgrade a queued invite to unconfirmed', () async {
      store.invites.add(
        const PendingInvite(token: 'tok', server: _server, acceptQueued: true),
      );
      final repository = build();

      await repository.remember('tok');

      expect(store.invites.single.acceptQueued, isTrue);
      expect(await repository.firstUnconfirmed(), isNull);
      expect(await repository.queued(), hasLength(1));
    });

    test('ignores other servers\' invites', () async {
      store.invites.add(
        const PendingInvite(token: 'tok', server: 'https://other.example.com'),
      );

      expect(await build().firstUnconfirmed(), isNull);
    });

    test('is a no-op without a configured server', () async {
      currentServer = null;
      final repository = build();

      await repository.remember('tok');

      expect(store.invites, isEmpty);
      expect(await repository.firstUnconfirmed(), isNull);
      expect(await repository.flushQueued(), isEmpty);
    });

    test('discard drops the invite', () async {
      final repository = build();
      await repository.remember('tok');

      await repository.discard('tok');

      expect(store.invites, isEmpty);
    });
  });
}
