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
import 'package:trek/packing/packing_api.dart';
import 'package:trek/packing/packing_item.dart';
import 'package:trek/packing/packing_repository.dart';

import '../../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

/// The Packing tab is built (offstage) inside the dashboard's
/// [IndexedStack] on every test, whichever tab is selected — it needs a
/// [PackingRepository] available via [packingRepositoryProvider]
/// regardless. Overriding the repository directly (rather than the
/// underlying [ApiClient]) keeps tests that aren't exercising Packing from
/// having to stand up an [AuthService].
Future<void> _pumpDashboard(
  WidgetTester tester, {
  http.Client? packingHttpClient,
  InMemoryPackingLocalStore? localStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        packingRepositoryProvider.overrideWithValue(
          PackingRepository(
            packingApi: PackingApi(
              apiClient: ApiClient(
                baseUrl: 'https://trek.example.com',
                httpClient:
                    packingHttpClient ??
                    MockClient((request) async => _json({'items': []})),
              ),
            ),
            localStore: localStore ?? InMemoryPackingLocalStore(),
          ),
        ),
      ],
      child: const MaterialApp(home: TripDashboardScreen(tripId: 'trip-1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the trip id and all five section tabs', (tester) async {
    await _pumpDashboard(tester);

    expect(find.text('Trip trip-1'), findsOneWidget);
    for (final label in ['Days', 'Places', 'Budget', 'Packing', 'Todos']) {
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

  group('Packing tab', () {
    testWidgets('shows an empty state when the trip has no packing items', (
      tester,
    ) async {
      await _pumpDashboard(tester);

      await tester.tap(find.text('Packing'));
      await tester.pumpAndSettle();

      expect(find.text('No packing items yet.'), findsOneWidget);
    });

    testWidgets('renders packing items fetched from the real API shape', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        packingHttpClient: MockClient(
          (request) async => _json({
            'items': [
              {
                'id': 1,
                'trip_id': 'trip-1',
                'name': 'Hiking boots',
                'category': 'Footwear',
                'checked': 1,
              },
            ],
          }),
        ),
      );

      await tester.tap(find.text('Packing'));
      await tester.pumpAndSettle();

      expect(find.text('Hiking boots'), findsOneWidget);
      expect(find.text('Footwear'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets(
      'shows an explicit offline state instead of a spinner when there is '
      'nothing cached and the network is unreachable',
      (tester) async {
        await _pumpDashboard(
          tester,
          packingHttpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
        );

        await tester.tap(find.text('Packing'));
        await tester.pumpAndSettle();

        expect(find.textContaining("You're offline"), findsOneWidget);
      },
    );

    testWidgets(
      'a cached packing item still shows when the network is unreachable',
      (tester) async {
        await _pumpDashboard(
          tester,
          packingHttpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
          localStore: InMemoryPackingLocalStore(
            initial: {
              'trip-1': [
                PackingItem.fromJson({
                  'id': 1,
                  'trip_id': 'trip-1',
                  'name': 'Cached item',
                }, tripId: 'trip-1'),
              ],
            },
          ),
        );

        await tester.tap(find.text('Packing'));
        await tester.pumpAndSettle();

        expect(find.text('Cached item'), findsOneWidget);
      },
    );

    testWidgets('creating a packing item adds it to the list immediately', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        packingHttpClient: MockClient((request) async {
          if (request.method == 'POST') {
            return _json({
              'item': {'id': 9, 'trip_id': 'trip-1', 'name': 'Sunscreen'},
            }, 201);
          }
          return _json({'items': []});
        }),
      );
      await tester.tap(find.text('Packing'));
      await tester.pumpAndSettle();
      expect(find.text('No packing items yet.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Sunscreen');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Sunscreen'), findsOneWidget);
    });

    testWidgets(
      'a packing item created while offline shows as syncing and stays in '
      'the list',
      (tester) async {
        await _pumpDashboard(
          tester,
          packingHttpClient: MockClient((request) async {
            if (request.method == 'POST') {
              throw http.ClientException('Connection refused');
            }
            return _json({'items': []});
          }),
        );
        await tester.tap(find.text('Packing'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).first,
          'Offline item',
        );
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();

        expect(find.text('Offline item'), findsOneWidget);
        expect(find.text('Syncing…'), findsOneWidget);
      },
    );

    testWidgets('a blank name is rejected before hitting the network', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        packingHttpClient: MockClient((request) async {
          if (request.method == 'POST') {
            fail('should not create with a blank name');
          }
          return _json({'items': []});
        }),
      );
      await tester.tap(find.text('Packing'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('A name is required.'), findsOneWidget);
    });
  });
}
