import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/design/place_category_colors.dart';
import 'package:trek/features/trips/trip_dashboard_screen.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/reservations/reservation.dart';
import 'package:trek/reservations/reservations_api.dart';
import 'package:trek/reservations/reservations_repository.dart';

import '../../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

/// The Bookings tab is built (offstage) inside the dashboard's
/// [IndexedStack] on every test, whichever tab is selected — it needs a
/// [ReservationsRepository] via [reservationsRepositoryProvider]
/// regardless. Overriding the repository directly (rather than the
/// underlying [ApiClient]) keeps tests that aren't exercising Bookings from
/// having to stand up an `AuthService`.
Future<void> _pumpDashboard(
  WidgetTester tester, {
  http.Client? bookingsHttpClient,
  InMemoryReservationsLocalStore? localStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reservationsRepositoryProvider.overrideWithValue(
          ReservationsRepository(
            reservationsApi: ReservationsApi(
              apiClient: ApiClient(
                baseUrl: 'https://trek.example.com',
                httpClient:
                    bookingsHttpClient ??
                    MockClient((request) async => _json({'reservations': []})),
              ),
            ),
            localStore: localStore ?? InMemoryReservationsLocalStore(),
          ),
        ),
      ],
      child: const MaterialApp(home: TripDashboardScreen(tripId: 'trip-1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the trip id and all six section tabs', (tester) async {
    await _pumpDashboard(tester);

    expect(find.text('Trip trip-1'), findsOneWidget);
    for (final label in [
      'Days',
      'Places',
      'Budget',
      'Packing',
      'Todos',
      'Bookings',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('switching tabs shows the corresponding placeholder', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    expect(find.text('Days — coming soon'), findsOneWidget);

    await tester.tap(find.text('Budget'));
    await tester.pumpAndSettle();

    expect(find.text('Budget — coming soon'), findsOneWidget);
    expect(find.text('Days — coming soon'), findsNothing);
  });

  testWidgets('Places tab previews every default category color/icon', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    await tester.tap(find.text('Places'));
    await tester.pumpAndSettle();

    for (final category in PlaceCategory.values) {
      expect(find.text(category.label), findsOneWidget);
    }
  });

  testWidgets("Bookings tab lists a trip's reservations from the server", (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      bookingsHttpClient: MockClient((request) async {
        expect(request.url.path, '/api/trips/trip-1/reservations');
        return _json({
          'reservations': [
            {
              'id': 7,
              'trip_id': 1,
              'title': 'NZ201 AKL → ZQN',
              'type': 'flight',
              'status': 'confirmed',
              'reservation_time': '2026-03-04 07:30',
            },
          ],
        });
      }),
    );

    await tester.tap(find.text('Bookings'));
    await tester.pumpAndSettle();

    expect(find.text('NZ201 AKL → ZQN'), findsOneWidget);
    expect(find.text('2026-03-04 07:30'), findsOneWidget);
  });

  testWidgets('Bookings tab marks a cancelled booking in its subtitle', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      bookingsHttpClient: MockClient((request) async {
        return _json({
          'reservations': [
            {
              'id': 8,
              'trip_id': 1,
              'title': 'Cooking class',
              'type': 'activity',
              'status': 'cancelled',
              'location': 'Ponsonby',
            },
          ],
        });
      }),
    );

    await tester.tap(find.text('Bookings'));
    await tester.pumpAndSettle();

    expect(find.text('Cancelled · Ponsonby'), findsOneWidget);
  });

  testWidgets('Bookings tab shows an offline state when nothing is cached', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      bookingsHttpClient: MockClient((request) async {
        throw http.ClientException('Connection refused');
      }),
    );

    await tester.tap(find.text('Bookings'));
    await tester.pumpAndSettle();

    expect(find.textContaining("You're offline"), findsOneWidget);
  });

  testWidgets('Bookings tab shows cached bookings when the refresh fails', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      bookingsHttpClient: MockClient((request) async {
        throw http.ClientException('Connection refused');
      }),
      localStore: InMemoryReservationsLocalStore(
        initial: {
          'trip-1': [
            Reservation.fromJson({
              'id': 5,
              'trip_id': 1,
              'title': 'Cached ferry',
              'type': 'ferry',
              'status': 'confirmed',
            }),
          ],
        },
      ),
    );

    await tester.tap(find.text('Bookings'));
    await tester.pumpAndSettle();

    expect(find.text('Cached ferry'), findsOneWidget);
    expect(find.textContaining("You're offline"), findsNothing);
  });

  testWidgets(
    'Bookings tab shows the empty state for a trip with no bookings',
    (tester) async {
      await _pumpDashboard(tester);

      await tester.tap(find.text('Bookings'));
      await tester.pumpAndSettle();

      expect(find.text('No reservations yet.'), findsOneWidget);
    },
  );
}
