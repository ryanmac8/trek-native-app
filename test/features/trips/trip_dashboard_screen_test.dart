import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/accommodations/accommodations_api.dart';
import 'package:trek/accommodations/accommodations_repository.dart';
import 'package:trek/app/providers.dart';
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

/// The Stays tab is built (offstage) inside the dashboard's [IndexedStack]
/// on every test, whichever tab is selected — it needs an
/// [AccommodationsRepository] via [accommodationsRepositoryProvider]
/// regardless. Overriding the repository directly (rather than the
/// underlying [ApiClient]) keeps tests that aren't exercising Stays from
/// having to stand up an `AuthService`.
Future<void> _pumpDashboard(
  WidgetTester tester, {
  http.Client? staysHttpClient,
  InMemoryAccommodationsLocalStore? localStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accommodationsRepositoryProvider.overrideWithValue(
          AccommodationsRepository(
            accommodationsApi: AccommodationsApi(
              apiClient: ApiClient(
                baseUrl: 'https://trek.example.com',
                httpClient:
                    staysHttpClient ??
                    MockClient(
                      (request) async => _json({'accommodations': []}),
                    ),
              ),
            ),
            localStore: localStore ?? InMemoryAccommodationsLocalStore(),
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
      'Stays',
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

  testWidgets('Stays tab lists a trip\'s accommodations from the server', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      staysHttpClient: MockClient((request) async {
        expect(request.url.path, '/api/trips/trip-1/accommodations');
        return _json({
          'accommodations': [
            {
              'id': 7,
              'trip_id': 1,
              'place_id': 501,
              'start_day_id': 1,
              'end_day_id': 2,
              'check_in': '2026-03-04',
              'check_out': '2026-03-07',
              'place_name': 'Sofitel Queenstown',
            },
          ],
        });
      }),
    );

    await tester.tap(find.text('Stays'));
    await tester.pumpAndSettle();

    expect(find.text('Sofitel Queenstown'), findsOneWidget);
    expect(find.text('2026-03-04 → 2026-03-07'), findsOneWidget);
  });

  testWidgets('Stays tab shows an offline state when nothing is cached', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      staysHttpClient: MockClient((request) async {
        throw http.ClientException('Connection refused');
      }),
    );

    await tester.tap(find.text('Stays'));
    await tester.pumpAndSettle();

    expect(find.textContaining("You're offline"), findsOneWidget);
  });

  testWidgets('Stays tab shows the empty state for a trip with no stays', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    await tester.tap(find.text('Stays'));
    await tester.pumpAndSettle();

    expect(find.text('No accommodations yet.'), findsOneWidget);
  });
}
