import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/trips/trip.dart';

import '../../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

Future<void> _pumpTripList(
  WidgetTester tester, {
  required AuthService authService,
  required http.Client tripsHttpClient,
  InMemoryTripsLocalStore? localStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        // Mirrors apiClientProvider's real wiring (getAccessToken +
        // onUnauthorized) so a 401 here actually reaches
        // AuthService.handleUnauthorized, same as production.
        apiClientProvider.overrideWithValue(
          ApiClient(
            baseUrl: 'https://trek.example.com',
            httpClient: tripsHttpClient,
            getAccessToken: () => authService.currentAccessToken,
            onUnauthorized: authService.handleUnauthorized,
          ),
        ),
        serverConfigStorageProvider.overrideWithValue(
          InMemoryServerConfigStorage(
            initial: const ServerConfig(publicUrl: 'https://trek.example.com'),
          ),
        ),
        tripsLocalStoreProvider.overrideWithValue(
          localStore ?? InMemoryTripsLocalStore(),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) =>
            MaterialApp.router(routerConfig: ref.watch(appRouterProvider)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AuthService _authenticatedAuthService() {
  final authService = AuthService(
    apiClient: ApiClient(
      baseUrl: 'https://trek.example.com',
      httpClient: MockClient((request) async => _json({})),
    ),
    tokenStorage: InMemoryTokenStorage(),
  );
  authService.isAuthenticated.value = true;
  return authService;
}

void main() {
  testWidgets('shows an empty state when there are no trips', (tester) async {
    await _pumpTripList(
      tester,
      authService: _authenticatedAuthService(),
      tripsHttpClient: MockClient((request) async {
        expect(request.url.path, '/api/trips');
        return _json({'trips': []});
      }),
    );

    expect(find.text('No trips yet.'), findsOneWidget);
  });

  testWidgets('renders trips fetched from the real API shape', (tester) async {
    await _pumpTripList(
      tester,
      authService: _authenticatedAuthService(),
      tripsHttpClient: MockClient(
        (request) async => _json({
          'trips': [
            {
              'id': 20,
              'title': 'New Zealand',
              'start_date': '2026-11-28',
              'end_date': '2026-12-13',
              'day_count': 16,
              'place_count': 17,
            },
          ],
        }),
      ),
    );

    expect(find.text('New Zealand'), findsOneWidget);
    expect(find.textContaining('16 days'), findsOneWidget);
  });

  testWidgets(
    'shows an offline state with retry when the network is unreachable',
    (tester) async {
      var attempts = 0;
      await _pumpTripList(
        tester,
        authService: _authenticatedAuthService(),
        tripsHttpClient: MockClient((request) async {
          attempts++;
          throw http.ClientException('Connection refused');
        }),
      );

      expect(find.textContaining("You're offline"), findsOneWidget);
      expect(attempts, 1);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
    },
  );

  testWidgets('shows a generic error with retry on a server failure', (
    tester,
  ) async {
    await _pumpTripList(
      tester,
      authService: _authenticatedAuthService(),
      tripsHttpClient: MockClient(
        (request) async => _json({'error': 'boom'}, 500),
      ),
    );

    expect(find.text("Couldn't load trips."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'a 401 falls back to the empty state without a scary error, and flags '
    'needsReconnect',
    (tester) async {
      final authService = _authenticatedAuthService();
      await _pumpTripList(
        tester,
        authService: authService,
        tripsHttpClient: MockClient(
          (request) async => _json({
            'error': 'Invalid or expired token',
            'code': 'AUTH_REQUIRED',
          }, 401),
        ),
      );

      expect(find.text('No trips yet.'), findsOneWidget);
      expect(authService.needsReconnect.value, isTrue);
      // Still authenticated — a 401 doesn't sign the user out.
      expect(authService.isAuthenticated.value, isTrue);
    },
  );

  testWidgets('shows an empty state and logs out back to the login screen', (
    tester,
  ) async {
    final authService = _authenticatedAuthService();
    await _pumpTripList(
      tester,
      authService: authService,
      tripsHttpClient: MockClient((request) async => _json({'trips': []})),
    );

    expect(find.text('No trips yet.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsWidgets);
    expect(authService.isAuthenticated.value, isFalse);
  });

  testWidgets(
    'shows cached trips immediately, even though the network is unreachable',
    (tester) async {
      final localStore = InMemoryTripsLocalStore(
        initial: [
          Trip.fromJson({'id': 20, 'title': 'New Zealand', 'day_count': 16}),
        ],
      );

      await _pumpTripList(
        tester,
        authService: _authenticatedAuthService(),
        tripsHttpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      // The cached trip is shown, not an offline empty state, since
      // docs/offline-first.md treats the cache as the source of truth for
      // what's already been seen.
      expect(find.text('New Zealand'), findsOneWidget);
      expect(find.textContaining("You're offline"), findsNothing);
    },
  );

  testWidgets(
    'shows a pending (offline-created) trip with a syncing indicator and '
    "doesn't navigate to it",
    (tester) async {
      final localStore = InMemoryTripsLocalStore(
        initial: [const Trip(localId: 'local-1', title: 'Draft trip')],
      );

      await _pumpTripList(
        tester,
        authService: _authenticatedAuthService(),
        tripsHttpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      expect(find.text('Draft trip'), findsOneWidget);
      expect(find.text('Syncing…'), findsOneWidget);

      await tester.tap(find.text('Draft trip'));
      await tester.pumpAndSettle();

      // No server id to navigate to yet — still on the trip list.
      expect(find.text('Trips'), findsOneWidget);
    },
  );

  testWidgets('creating a trip while online adds the synced trip to the list', (
    tester,
  ) async {
    await _pumpTripList(
      tester,
      authService: _authenticatedAuthService(),
      tripsHttpClient: MockClient((request) async {
        if (request.method == 'POST') {
          expect(jsonDecode(request.body)['title'], 'Iceland');
          return _json({
            'trip': {'id': 7, 'title': 'Iceland'},
          }, 201);
        }
        return _json({'trips': []});
      }),
    );

    expect(find.text('No trips yet.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('New trip'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Iceland',
    );
    await tester.tap(find.text('Create trip'));
    await tester.pumpAndSettle();

    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Iceland'), findsOneWidget);
    expect(find.text('Syncing…'), findsNothing);
  });

  testWidgets(
    'creating a trip while offline shows it as a pending, syncing entry',
    (tester) async {
      await _pumpTripList(
        tester,
        authService: _authenticatedAuthService(),
        tripsHttpClient: MockClient((request) async {
          if (request.method == 'POST') {
            throw http.ClientException('Connection refused');
          }
          return _json({'trips': []});
        }),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Iceland',
      );
      await tester.tap(find.text('Create trip'));
      await tester.pumpAndSettle();

      expect(find.text('Trips'), findsOneWidget);
      expect(find.text('Iceland'), findsOneWidget);
      expect(find.text('Syncing…'), findsOneWidget);
    },
  );
}
