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
      daysHttpClient: MockClient((request) async => _json({'days': []})),
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
