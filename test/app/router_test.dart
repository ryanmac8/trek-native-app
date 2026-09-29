import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/app/router.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/features/trip_invites/pending_invite_store.dart';
import 'package:trek/features/trip_invites/trip_invite_api.dart';
import 'package:trek/features/trip_invites/trip_invite_repository.dart';
import 'package:trek/network/api_client.dart';

import '../test_helpers.dart';

void main() {
  late AuthService authService;
  late InMemoryServerConfigStorage serverConfigStorage;
  late InMemoryPendingInviteStore inviteStore;
  late TripInviteRepository tripInvites;

  setUp(() {
    inviteStore = InMemoryPendingInviteStore();
    tripInvites = TripInviteRepository(
      api: TripInviteApi(
        apiClient: ApiClient(
          baseUrl: 'https://trek.example.com',
          httpClient: MockClient(
            (request) async => http.Response(
              jsonEncode({'trip_id': 20, 'title': 'New Zealand'}),
              200,
            ),
          ),
        ),
      ),
      store: inviteStore,
      currentServer: () async => (await serverConfigStorage.read())?.publicUrl,
    );
    authService = AuthService(
      apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
      tokenStorage: InMemoryTokenStorage(),
    );
    serverConfigStorage = InMemoryServerConfigStorage();
  });

  Future<GoRouter> pump(
    WidgetTester tester, {
    String initialLocation = '/trips',
  }) async {
    final router = buildAppRouter(
      authService: authService,
      serverConfigStorage: serverConfigStorage,
      tripInvites: tripInvites,
      initialLocation: initialLocation,
    );
    // The trip list and join screens read the invite repository.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripInviteRepositoryProvider.overrideWithValue(tripInvites),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('redirects to server setup when no server is configured', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Connect to your Trek server'), findsOneWidget);
  });

  testWidgets('redirects to login once a server is configured', (tester) async {
    await serverConfigStorage.write(
      const ServerConfig(publicUrl: 'https://trek.example.com'),
    );

    await pump(tester);

    expect(find.text('Log in'), findsWidgets);
  });

  testWidgets(
    'redirects an authenticated user away from /server-setup and /login',
    (tester) async {
      await serverConfigStorage.write(
        const ServerConfig(publicUrl: 'https://trek.example.com'),
      );
      authService.isAuthenticated.value = true;

      await pump(tester, initialLocation: '/login');

      expect(find.text('Trips'), findsOneWidget);
    },
  );

  testWidgets('lets an authenticated user reach the trip list directly', (
    tester,
  ) async {
    await serverConfigStorage.write(
      const ServerConfig(publicUrl: 'https://trek.example.com'),
    );
    authService.isAuthenticated.value = true;

    await pump(tester);

    expect(find.text('Trips'), findsOneWidget);
  });

  testWidgets('re-evaluates the redirect when isAuthenticated changes', (
    tester,
  ) async {
    await serverConfigStorage.write(
      const ServerConfig(publicUrl: 'https://trek.example.com'),
    );

    await pump(tester);
    expect(find.text('Log in'), findsWidgets);

    authService.isAuthenticated.value = true;
    await tester.pumpAndSettle();

    expect(find.text('Trips'), findsOneWidget);
  });

  group('deep links', () {
    setUp(() async {
      await serverConfigStorage.write(
        const ServerConfig(publicUrl: 'https://trek.example.com'),
      );
    });

    testWidgets('normalizes a trek:// invite link to the join screen', (
      tester,
    ) async {
      authService.isAuthenticated.value = true;

      await pump(tester, initialLocation: 'trek://join/tok');

      expect(find.text('Join trip'), findsWidgets);
      expect(find.text('New Zealand'), findsOneWidget);
    });

    testWidgets('normalizes a trek:// trip link to the trip dashboard', (
      tester,
    ) async {
      authService.isAuthenticated.value = true;

      await pump(tester, initialLocation: 'trek://trips/20');

      expect(find.text('Trip 20'), findsOneWidget);
    });

    testWidgets('sends an unrecognized trek:// link to the trip list', (
      tester,
    ) async {
      authService.isAuthenticated.value = true;

      await pump(tester, initialLocation: 'trek://nowhere');

      expect(find.text('Trips'), findsOneWidget);
    });

    testWidgets('a signed-out invite link resumes right after login', (
      tester,
    ) async {
      await pump(tester, initialLocation: '/join/tok');

      expect(find.text('Log in'), findsWidgets);
      expect(inviteStore.invites.single.token, 'tok');
      expect(inviteStore.invites.single.acceptQueued, isFalse);

      authService.isAuthenticated.value = true;
      await tester.pumpAndSettle();

      expect(find.text('New Zealand'), findsOneWidget);
    });

    testWidgets('login goes to the trip list when no invite is waiting', (
      tester,
    ) async {
      inviteStore.invites.add(
        const PendingInvite(
          token: 'queued',
          server: 'https://trek.example.com',
          acceptQueued: true,
        ),
      );
      await pump(tester, initialLocation: '/login');

      authService.isAuthenticated.value = true;
      await tester.pumpAndSettle();

      expect(find.text('Trips'), findsOneWidget);
    });
  });
}
