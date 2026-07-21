import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/design/widgets/app_list_row.dart';
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
        // The dashboard the trip-tap test navigates to reads the Days tab's
        // cache on initState — override so that doesn't hit the real
        // shared_preferences platform channel (unmocked here) and hang.
        daysLocalStoreProvider.overrideWithValue(InMemoryDaysLocalStore()),
        // Same reason — the dashboard's nav bar reads its customization
        // layout on build.
        tripDashboardNavLayoutStoreProvider.overrideWithValue(
          InMemoryTripDashboardNavLayoutStore(),
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
    'defaults to Upcoming Trips, hiding past trips until that tab is tapped',
    (tester) async {
      await _pumpTripList(
        tester,
        authService: _authenticatedAuthService(),
        tripsHttpClient: MockClient(
          (request) async => _json({
            'trips': [
              {
                'id': 1,
                'title': 'Old Adventure',
                'start_date': '2020-01-01',
                'end_date': '2020-01-05',
              },
              {
                'id': 2,
                'title': 'Next Adventure',
                'start_date': '2030-01-01',
                'end_date': '2030-01-05',
              },
            ],
          }),
        ),
      );

      // Defaults to Upcoming Trips — the past trip is filtered out.
      expect(find.text('Next Adventure'), findsOneWidget);
      expect(find.text('Old Adventure'), findsNothing);

      await tester.tap(find.text('Past Trips'));
      await tester.pumpAndSettle();

      expect(find.text('Old Adventure'), findsOneWidget);
      expect(find.text('Next Adventure'), findsNothing);
    },
  );

  testWidgets('an undated trip counts as upcoming, not past', (tester) async {
    await _pumpTripList(
      tester,
      authService: _authenticatedAuthService(),
      tripsHttpClient: MockClient(
        (request) async => _json({
          'trips': [
            {'id': 5, 'title': 'Someday Trip'},
          ],
        }),
      ),
    );

    expect(find.text('Someday Trip'), findsOneWidget);

    await tester.tap(find.text('Past Trips'));
    await tester.pumpAndSettle();

    expect(find.text('No past trips.'), findsOneWidget);
  });

  testWidgets(
    'sorts Upcoming Trips soonest-first, Past Trips most-recent-first',
    (tester) async {
      await _pumpTripList(
        tester,
        authService: _authenticatedAuthService(),
        tripsHttpClient: MockClient(
          (request) async => _json({
            'trips': [
              {
                'id': 1,
                'title': 'Far Future',
                'start_date': '2030-06-01',
                'end_date': '2030-06-10',
              },
              {
                'id': 2,
                'title': 'Near Future',
                'start_date': '2026-08-01',
                'end_date': '2026-08-10',
              },
              {
                'id': 3,
                'title': 'Recent Past',
                'start_date': '2025-01-01',
                'end_date': '2025-01-10',
              },
              {
                'id': 4,
                'title': 'Older Past',
                'start_date': '2020-01-01',
                'end_date': '2020-01-10',
              },
            ],
          }),
        ),
      );

      List<String> visibleTitles() => tester
          .widgetList<AppListRow>(find.byType(AppListRow))
          .map((row) => row.title)
          .toList();

      expect(visibleTitles(), ['Near Future', 'Far Future']);

      await tester.tap(find.text('Past Trips'));
      await tester.pumpAndSettle();

      expect(visibleTitles(), ['Recent Past', 'Older Past']);
    },
  );

  testWidgets('an undated trip sorts after every dated upcoming trip', (
    tester,
  ) async {
    await _pumpTripList(
      tester,
      authService: _authenticatedAuthService(),
      tripsHttpClient: MockClient(
        (request) async => _json({
          'trips': [
            {'id': 5, 'title': 'Someday Trip'},
            {
              'id': 6,
              'title': 'Booked Trip',
              'start_date': '2026-08-01',
              'end_date': '2026-08-10',
            },
          ],
        }),
      ),
    );

    final titles = tester
        .widgetList<AppListRow>(find.byType(AppListRow))
        .map((row) => row.title)
        .toList();

    expect(titles, ['Booked Trip', 'Someday Trip']);
  });

  testWidgets(
    'tapping a trip pushes the dashboard, and back returns to the trip list',
    (tester) async {
      await _pumpTripList(
        tester,
        authService: _authenticatedAuthService(),
        tripsHttpClient: MockClient(
          (request) async => _json({
            'trips': [
              {'id': 20, 'title': 'New Zealand'},
            ],
          }),
        ),
      );

      await tester.tap(find.text('New Zealand'));
      await tester.pumpAndSettle();

      expect(find.text('Trip 20'), findsOneWidget);
      // Pushed (not `go`), so there's something to pop back to — a plain
      // `go` would leave no back stack entry and no back button at all.
      final backButton = find.byTooltip('Back');
      expect(backButton, findsOneWidget);

      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(find.text('New Zealand'), findsOneWidget);
      expect(find.text('Trips'), findsOneWidget);
    },
  );

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

  // Logout moved to SettingsScreen's AppBar — see settings_screen_test.dart.
  // TripListScreen's AppBar only has the Settings gear now.

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
