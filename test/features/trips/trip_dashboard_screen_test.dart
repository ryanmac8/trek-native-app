import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/features/trips/trip_dashboard_screen.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/places/place.dart';

import '../../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required http.Client httpClient,
  InMemoryPlacesLocalStore? localStore,
  String tripId = 'trip-1',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(
            baseUrl: 'https://trek.example.com',
            httpClient: httpClient,
          ),
        ),
        placesLocalStoreProvider.overrideWithValue(
          localStore ?? InMemoryPlacesLocalStore(),
        ),
      ],
      child: MaterialApp(home: TripDashboardScreen(tripId: tripId)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the trip id and all five section tabs', (tester) async {
    await _pumpDashboard(
      tester,
      httpClient: MockClient((request) async => _json({'places': []})),
    );

    expect(find.text('Trip trip-1'), findsOneWidget);
    for (final label in ['Days', 'Places', 'Budget', 'Packing', 'Todos']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('switching tabs shows the corresponding placeholder', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      httpClient: MockClient((request) async => _json({'places': []})),
    );
    expect(find.text('Days — coming soon'), findsOneWidget);

    await tester.tap(find.text('Budget'));
    await tester.pumpAndSettle();

    expect(find.text('Budget — coming soon'), findsOneWidget);
    expect(find.text('Days — coming soon'), findsNothing);
  });

  group('Places tab', () {
    testWidgets('shows an empty state when the trip has no places yet', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        httpClient: MockClient((request) async => _json({'places': []})),
      );

      await tester.tap(find.text('Places'));
      await tester.pumpAndSettle();

      expect(find.text('No places yet.'), findsOneWidget);
    });

    testWidgets('renders places fetched from the real API shape', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        tripId: '20',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/trips/20/places');
          return _json({
            'places': [
              {
                'id': 501,
                'trip_id': 20,
                'name': 'Fergburger',
                'category': {
                  'id': 2,
                  'name': 'Restaurant',
                  'color': '#ef4444',
                  'icon': '🍽️',
                },
                'price': 15,
                'currency': 'NZD',
                'notes': 'Try the Sweet Bambi',
              },
            ],
          });
        }),
      );

      await tester.tap(find.text('Places'));
      await tester.pumpAndSettle();

      expect(find.text('Fergburger'), findsOneWidget);
      expect(find.textContaining('NZD 15'), findsOneWidget);
      expect(find.textContaining('Try the Sweet Bambi'), findsOneWidget);
      expect(find.text('Restaurant'), findsOneWidget);
    });

    testWidgets('a place with no category shows no category badge', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        httpClient: MockClient(
          (request) async => _json({
            'places': [
              {'id': 1, 'trip_id': 20, 'name': 'Unsorted spot'},
            ],
          }),
        ),
      );

      await tester.tap(find.text('Places'));
      await tester.pumpAndSettle();

      expect(find.text('Unsorted spot'), findsOneWidget);
      expect(find.byType(Chip), findsNothing);
    });

    testWidgets(
      'shows cached places immediately, even though the network is unreachable',
      (tester) async {
        final localStore = InMemoryPlacesLocalStore(
          initial: {
            'trip-1': [
              Place.fromJson({'id': 501, 'trip_id': 20, 'name': 'Fergburger'}),
            ],
          },
        );

        await _pumpDashboard(
          tester,
          httpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: localStore,
        );

        await tester.tap(find.text('Places'));
        await tester.pumpAndSettle();

        // The cached place is shown, not an offline empty state, since
        // docs/offline-first.md treats the cache as the source of truth
        // for what's already been seen.
        expect(find.text('Fergburger'), findsOneWidget);
        expect(find.textContaining("You're offline"), findsNothing);
      },
    );

    testWidgets(
      'shows an offline state with retry when there is nothing cached',
      (tester) async {
        var attempts = 0;
        await _pumpDashboard(
          tester,
          httpClient: MockClient((request) async {
            attempts++;
            throw http.ClientException('Connection refused');
          }),
        );

        await tester.tap(find.text('Places'));
        await tester.pumpAndSettle();

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
      await _pumpDashboard(
        tester,
        httpClient: MockClient(
          (request) async => _json({'error': 'boom'}, 500),
        ),
      );

      await tester.tap(find.text('Places'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load places."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('adding a place offline shows it at once as waiting to sync', (
      tester,
    ) async {
      final localStore = InMemoryPlacesLocalStore();
      await _pumpDashboard(
        tester,
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );
      await tester.tap(find.text('Places'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add place'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Fergburger',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Fergburger'), findsOneWidget);
      expect(find.byTooltip('Waiting to sync'), findsOneWidget);
      expect(await localStore.readPending('trip-1'), hasLength(1));
    });

    testWidgets('the place form requires a name', (tester) async {
      await _pumpDashboard(
        tester,
        httpClient: MockClient((request) async => _json({'places': []})),
      );
      await tester.tap(find.text('Places'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add place'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a name.'), findsOneWidget);
      expect(find.text('New place'), findsOneWidget);
    });

    testWidgets('editing a place syncs only the changed field', (tester) async {
      final requests = <http.Request>[];
      final place = {
        'id': 501,
        'trip_id': 20,
        'name': 'Fergburger',
        'notes': 'Old note',
        'updated_at': '2026-10-01 10:00:00',
      };
      await _pumpDashboard(
        tester,
        tripId: '20',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'PUT') {
            return _json({
              'place': {
                ...place,
                'notes': 'Sweet Bambi',
                'updated_at': '2026-10-13 09:00:00',
              },
            });
          }
          return _json({
            'places': [place],
          });
        }),
      );
      await tester.tap(find.text('Places'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fergburger'));
      await tester.pumpAndSettle();
      expect(find.text('Edit place'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Old note'),
        'Sweet Bambi',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final put = requests.singleWhere((r) => r.method == 'PUT');
      expect(put.url.path, '/api/trips/20/places/501');
      expect(put.headers['X-Base-Updated-At'], '2026-10-01 10:00:00');
      expect(jsonDecode(put.body), {'notes': 'Sweet Bambi'});
      expect(find.textContaining('Sweet Bambi'), findsOneWidget);
      expect(find.byTooltip('Waiting to sync'), findsNothing);
    });

    testWidgets('deleting a place asks first, then removes it', (tester) async {
      final requests = <http.Request>[];
      await _pumpDashboard(
        tester,
        tripId: '20',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'DELETE') return _json({'success': true});
          return _json({
            'places': [
              {'id': 501, 'trip_id': 20, 'name': 'Fergburger'},
            ],
          });
        }),
      );
      await tester.tap(find.text('Places'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fergburger'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete place'));
      await tester.pumpAndSettle();
      expect(find.text('Delete place?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Fergburger'), findsNothing);
      expect(
        requests.where((r) => r.method == 'DELETE').single.url.path,
        '/api/trips/20/places/501',
      );
    });

    testWidgets('a conflicted place offers keep mine / use theirs', (
      tester,
    ) async {
      final theirs = {
        'id': 501,
        'trip_id': 20,
        'name': 'Fergburger',
        'notes': 'Their note',
        'updated_at': '2026-10-05 12:00:00',
      };
      await _pumpDashboard(
        tester,
        tripId: '20',
        httpClient: MockClient((request) async {
          if (request.method == 'PUT') {
            return _json({'error': 'conflict', 'server': theirs}, 409);
          }
          return _json({
            'places': [
              {
                'id': 501,
                'trip_id': 20,
                'name': 'Fergburger',
                'notes': 'Old note',
                'updated_at': '2026-10-01 10:00:00',
              },
            ],
          });
        }),
      );
      await tester.tap(find.text('Places'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fergburger'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Old note'),
        'My note',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Edit conflict — tap to resolve'), findsOneWidget);
      expect(find.textContaining('My note'), findsOneWidget);

      await tester.tap(find.text('Fergburger'));
      await tester.pumpAndSettle();
      expect(find.text('Edit conflict'), findsOneWidget);
      await tester.tap(find.text('Use theirs'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Their note'), findsOneWidget);
      expect(find.byTooltip('Edit conflict — tap to resolve'), findsNothing);
    });
  });
}
