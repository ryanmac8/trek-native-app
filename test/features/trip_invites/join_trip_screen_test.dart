import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/app_messenger.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/features/trip_invites/join_trip_screen.dart';
import 'package:trek/features/trip_invites/pending_invite_store.dart';
import 'package:trek/network/api_client.dart';

import '../../test_helpers.dart';

const _server = 'https://trek.example.com';

void main() {
  late InMemoryPendingInviteStore store;
  late Future<http.Response> Function(http.Request) handler;
  late List<http.Request> requests;

  setUp(() {
    store = InMemoryPendingInviteStore();
    requests = [];
  });

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  Future<http.Response> offline(http.Request _) =>
      throw const SocketException('offline');

  Future<void> pump(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/join/tok',
      routes: [
        GoRoute(
          path: '/join/:token',
          builder: (context, state) =>
              JoinTripScreen(token: state.pathParameters['token']!),
        ),
        GoRoute(
          path: '/trips',
          builder: (context, state) => const Scaffold(body: Text('trip list')),
        ),
        GoRoute(
          path: '/trips/:id',
          builder: (context, state) =>
              Scaffold(body: Text('trip ${state.pathParameters['id']}')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverConfigStorageProvider.overrideWithValue(
            InMemoryServerConfigStorage(
              initial: const ServerConfig(publicUrl: _server),
            ),
          ),
          apiClientProvider.overrideWithValue(
            ApiClient(
              baseUrl: _server,
              httpClient: MockClient((request) {
                requests.add(request);
                return handler(request);
              }),
            ),
          ),
          pendingInviteStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          scaffoldMessengerKey: scaffoldMessengerKey,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the trip title and joins it', (tester) async {
    handler = (request) async => request.method == 'GET'
        ? json({'trip_id': 20, 'title': 'New Zealand'})
        : json({'trip_id': 20, 'joined': true});

    await pump(tester);
    expect(find.text('New Zealand'), findsOneWidget);

    await tester.tap(find.text('Join trip'));
    await tester.pumpAndSettle();

    expect(requests.last.url.path, '/api/trip-invites/tok/accept');
    expect(find.text('trip 20'), findsOneWidget);
    expect(find.text('You joined the trip.'), findsOneWidget);
  });

  testWidgets('offline: shows the cached title and queues the join', (
    tester,
  ) async {
    store.invites.add(
      const PendingInvite(token: 'tok', server: _server, tripTitle: 'NZ'),
    );
    handler = offline;

    await pump(tester);
    expect(find.textContaining("You're offline"), findsOneWidget);
    expect(find.text('NZ'), findsOneWidget);

    await tester.tap(find.text('Join trip'));
    await tester.pumpAndSettle();

    expect(find.text('trip list'), findsOneWidget);
    expect(store.invites.single.acceptQueued, isTrue);
  });

  testWidgets('offline with nothing cached still offers to queue', (
    tester,
  ) async {
    handler = offline;

    await pump(tester);

    expect(find.text('Join trip'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
  });

  testWidgets('an invalid invite shows the server message', (tester) async {
    handler = (_) async =>
        json({'error': 'Invalid or expired invite link'}, 404);

    await pump(tester);

    expect(find.text('Invalid or expired invite link'), findsOneWidget);
    expect(find.text('Join trip'), findsNothing);
  });

  testWidgets('declining drops the remembered invite', (tester) async {
    store.invites.add(const PendingInvite(token: 'tok', server: _server));
    handler = (_) async => json({'trip_id': 20, 'title': 'New Zealand'});

    await pump(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.text('trip list'), findsOneWidget);
    expect(store.invites, isEmpty);
  });
}
