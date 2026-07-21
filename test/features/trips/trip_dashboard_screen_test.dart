import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/days/day.dart';
import 'package:trek/design/place_category_colors.dart';
import 'package:trek/features/trips/trip_dashboard_screen.dart';
import 'package:trek/network/api_client.dart';

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
  required http.Client daysHttpClient,
  InMemoryDaysLocalStore? localStore,
  InMemoryTripDashboardNavLayoutStore? navLayoutStore,
  String tripId = 'trip-1',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(
            baseUrl: 'https://trek.example.com',
            httpClient: daysHttpClient,
          ),
        ),
        daysLocalStoreProvider.overrideWithValue(
          localStore ?? InMemoryDaysLocalStore(),
        ),
        tripDashboardNavLayoutStoreProvider.overrideWithValue(
          navLayoutStore ?? InMemoryTripDashboardNavLayoutStore(),
        ),
      ],
      child: MaterialApp(home: TripDashboardScreen(tripId: tripId)),
    ),
  );
  await tester.pumpAndSettle();
}

/// Simulates dragging the widget under [source] onto the widget under
/// [target] — a plain (non-delayed) `Draggable` starts on the first
/// pointer move past the touch slop, so a plain move-then-up is enough.
Future<void> _drag(WidgetTester tester, Finder source, Finder target) async {
  final gesture = await tester.startGesture(tester.getCenter(source));
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the trip id and the 4 default visible tabs', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      daysHttpClient: MockClient((request) async => _json({'days': []})),
    );

    expect(find.text('Trip trip-1'), findsOneWidget);
    for (final label in ['Days', 'Places', 'Budget', 'Packing']) {
      expect(find.text(label), findsOneWidget);
    }
    // Todos didn't fit in the collapsed bar — it's in the overflow panel.
    expect(find.text('Todos'), findsNothing);
  });

  testWidgets('switching tabs shows the corresponding placeholder', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      daysHttpClient: MockClient((request) async => _json({'days': []})),
    );

    await tester.tap(find.text('Budget'));
    await tester.pumpAndSettle();

    expect(find.text('Budget — coming soon'), findsOneWidget);
  });

  testWidgets('Places tab previews every default category color/icon', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      daysHttpClient: MockClient((request) async => _json({'days': []})),
    );

    await tester.tap(find.text('Places'));
    await tester.pumpAndSettle();

    for (final category in PlaceCategory.values) {
      expect(find.text(category.label), findsOneWidget);
    }
  });

  group('overflow panel', () {
    testWidgets('the hamburger button opens and closes the overflow panel', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        daysHttpClient: MockClient((request) async => _json({'days': []})),
      );

      expect(find.text('Todos'), findsNothing);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();

      for (final label in ['Todos', 'Book', 'Lists', 'Files', 'Collab']) {
        expect(find.text(label), findsOneWidget);
      }

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Todos'), findsNothing);
    });

    testWidgets(
      'tapping a tab in the overflow panel selects it and closes the panel',
      (tester) async {
        await _pumpDashboard(
          tester,
          daysHttpClient: MockClient((request) async => _json({'days': []})),
        );

        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Book'));
        await tester.pumpAndSettle();

        expect(find.text('Book — coming soon'), findsOneWidget);
        // The panel collapsed back — the hamburger reverted to "More".
        expect(find.byTooltip('More'), findsOneWidget);
        expect(find.byTooltip('Close'), findsNothing);
      },
    );
  });

  group('drag-and-drop customization', () {
    testWidgets(
      'dragging a tab from the overflow panel onto a bar slot swaps it in, '
      'and persists the new layout',
      (tester) async {
        final navLayoutStore = InMemoryTripDashboardNavLayoutStore();
        await _pumpDashboard(
          tester,
          daysHttpClient: MockClient((request) async => _json({'days': []})),
          navLayoutStore: navLayoutStore,
        );

        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();

        // Drag "Todos" (in the panel) onto the "Packing" slot in the bar.
        await _drag(
          tester,
          find.byIcon(Icons.task_alt),
          find.byIcon(Icons.checklist),
        );

        // Packing was displaced into the panel (still open); Todos took
        // its slot in the bar.
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();

        expect(find.text('Todos'), findsOneWidget);
        expect(find.text('Packing'), findsNothing);

        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        expect(find.text('Packing'), findsOneWidget);

        expect(await navLayoutStore.read(), [
          'days',
          'places',
          'budget',
          'todos',
        ]);
      },
    );

    testWidgets('dragging a bar tab onto the overflow panel removes it '
        'from the bar', (tester) async {
      await _pumpDashboard(
        tester,
        daysHttpClient: MockClient((request) async => _json({'days': []})),
      );

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();

      await _drag(
        tester,
        find.byIcon(Icons.checklist), // Packing, in the bar
        find.text('Drag to rearrange your bar'), // inside the panel
      );

      expect(find.text('Packing'), findsOneWidget); // now shown in the panel

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Packing'), findsNothing);
    });
  });

  testWidgets(
    'restores a previously customized layout from the nav layout store',
    (tester) async {
      final navLayoutStore = InMemoryTripDashboardNavLayoutStore(
        initial: ['todos', 'book', null, 'files'],
      );

      await _pumpDashboard(
        tester,
        daysHttpClient: MockClient((request) async => _json({'days': []})),
        navLayoutStore: navLayoutStore,
      );

      for (final label in ['Todos', 'Book', 'Files']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Days'), findsNothing);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();

      for (final label in [
        'Days',
        'Places',
        'Budget',
        'Packing',
        'Lists',
        'Collab',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    },
  );

  group('Days tab', () {
    testWidgets('shows an empty state when the trip has no days yet', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        daysHttpClient: MockClient((request) async => _json({'days': []})),
      );

      expect(find.text('No days yet.'), findsOneWidget);
    });

    testWidgets('renders days fetched from the real API shape', (tester) async {
      await _pumpDashboard(
        tester,
        tripId: '20',
        daysHttpClient: MockClient((request) async {
          expect(request.url.path, '/api/trips/20/days');
          return _json({
            'days': [
              {
                'id': 101,
                'trip_id': 20,
                'day_number': 1,
                'date': '2026-11-28',
                'notes': 'Arrival',
                'assignments': [
                  {'id': 1},
                  {'id': 2},
                ],
              },
            ],
          });
        }),
      );

      expect(find.text('Day 1'), findsOneWidget);
      expect(find.textContaining('Arrival'), findsOneWidget);
      expect(find.text('2 places'), findsOneWidget);
    });

    testWidgets('uses the day title instead of "Day N" when one is set', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        daysHttpClient: MockClient(
          (request) async => _json({
            'days': [
              {
                'id': 101,
                'trip_id': 20,
                'day_number': 2,
                'title': 'Queenstown',
              },
            ],
          }),
        ),
      );

      expect(find.text('Queenstown'), findsOneWidget);
      expect(find.text('Day 2'), findsNothing);
      expect(find.text('0 places'), findsOneWidget);
    });

    testWidgets(
      'shows cached days immediately, even though the network is unreachable',
      (tester) async {
        final localStore = InMemoryDaysLocalStore(
          initial: {
            'trip-1': [
              Day.fromJson({'id': 101, 'trip_id': 20, 'day_number': 1}),
            ],
          },
        );

        await _pumpDashboard(
          tester,
          daysHttpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: localStore,
        );

        // The cached day is shown, not an offline empty state, since
        // docs/offline-first.md treats the cache as the source of truth for
        // what's already been seen.
        expect(find.text('Day 1'), findsOneWidget);
        expect(find.textContaining("You're offline"), findsNothing);
      },
    );

    testWidgets(
      'shows an offline state with retry when there is nothing cached',
      (tester) async {
        var attempts = 0;
        await _pumpDashboard(
          tester,
          daysHttpClient: MockClient((request) async {
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
      await _pumpDashboard(
        tester,
        daysHttpClient: MockClient(
          (request) async => _json({'error': 'boom'}, 500),
        ),
      );

      expect(find.text("Couldn't load days."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
