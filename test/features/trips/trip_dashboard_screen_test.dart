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
import 'package:trek/todos/todo_api.dart';
import 'package:trek/todos/todo_item.dart';
import 'package:trek/todos/todo_repository.dart';

import '../../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

/// The Todos tab is built (offstage) inside the dashboard's [IndexedStack]
/// on every test, whichever tab is selected — it needs a [TodoRepository]
/// available via [todoRepositoryProvider] regardless. Overriding the
/// repository directly (rather than the underlying [ApiClient]) keeps tests
/// that aren't exercising Todos from having to stand up an [AuthService].
Future<void> _pumpDashboard(
  WidgetTester tester, {
  http.Client? todoHttpClient,
  InMemoryTodoLocalStore? localStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        todoRepositoryProvider.overrideWithValue(
          TodoRepository(
            todoApi: TodoApi(
              apiClient: ApiClient(
                baseUrl: 'https://trek.example.com',
                httpClient:
                    todoHttpClient ??
                    MockClient((request) async => _json({'items': []})),
              ),
            ),
            localStore: localStore ?? InMemoryTodoLocalStore(),
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

  group('Todos tab', () {
    testWidgets('shows an empty state when the trip has no todos', (
      tester,
    ) async {
      await _pumpDashboard(tester);

      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();

      expect(find.text('No todos yet.'), findsOneWidget);
    });

    testWidgets('renders todos fetched from the real API shape', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        todoHttpClient: MockClient(
          (request) async => _json({
            'items': [
              {
                'id': 1,
                'trip_id': 'trip-1',
                'name': 'Book campsite',
                'category': 'Logistics',
                'checked': 1,
              },
            ],
          }),
        ),
      );

      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();

      expect(find.text('Book campsite'), findsOneWidget);
      expect(find.text('Logistics'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets(
      'shows an explicit offline state instead of a spinner when there is '
      'nothing cached and the network is unreachable',
      (tester) async {
        await _pumpDashboard(
          tester,
          todoHttpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
        );

        await tester.tap(find.text('Todos'));
        await tester.pumpAndSettle();

        expect(find.textContaining("You're offline"), findsOneWidget);
      },
    );

    testWidgets('a cached todo still shows when the network is unreachable', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        todoHttpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: InMemoryTodoLocalStore(
          initial: {
            'trip-1': [
              TodoItem.fromJson({
                'id': 1,
                'trip_id': 'trip-1',
                'name': 'Cached item',
              }, tripId: 'trip-1'),
            ],
          },
        ),
      );

      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();

      expect(find.text('Cached item'), findsOneWidget);
    });

    testWidgets('creating a todo adds it to the list immediately', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        todoHttpClient: MockClient((request) async {
          if (request.method == 'POST') {
            return _json({
              'item': {'id': 9, 'trip_id': 'trip-1', 'name': 'Buy sunscreen'},
            }, 201);
          }
          return _json({'items': []});
        }),
      );
      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();
      expect(find.text('No todos yet.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Buy sunscreen');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Buy sunscreen'), findsOneWidget);
    });

    testWidgets(
      'a todo created while offline shows as syncing and stays in the list',
      (tester) async {
        await _pumpDashboard(
          tester,
          todoHttpClient: MockClient((request) async {
            if (request.method == 'POST') {
              throw http.ClientException('Connection refused');
            }
            return _json({'items': []});
          }),
        );
        await tester.tap(find.text('Todos'));
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

    testWidgets('tapping a synced todo toggles its checked state', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        todoHttpClient: MockClient((request) async {
          if (request.method == 'PUT') {
            return _json({
              'item': {
                'id': 1,
                'trip_id': 'trip-1',
                'name': 'Book campsite',
                'checked': 1,
              },
            });
          }
          return _json({
            'items': [
              {
                'id': 1,
                'trip_id': 'trip-1',
                'name': 'Book campsite',
                'checked': 0,
              },
            ],
          });
        }),
      );
      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);

      await tester.tap(find.text('Book campsite'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    });

    testWidgets(
      'toggling while offline keeps the checked state and does not error',
      (tester) async {
        await _pumpDashboard(
          tester,
          todoHttpClient: MockClient((request) async {
            if (request.method == 'PUT') {
              throw http.ClientException('Connection refused');
            }
            return _json({
              'items': [
                {
                  'id': 1,
                  'trip_id': 'trip-1',
                  'name': 'Book campsite',
                  'checked': 0,
                },
              ],
            });
          }),
        );
        await tester.tap(find.text('Todos'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Book campsite'));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.check_circle), findsOneWidget);
      },
    );

    testWidgets('a still-pending (unsynced) todo is not tappable', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        todoHttpClient: MockClient((request) async {
          if (request.method == 'PUT') {
            fail('should not attempt to toggle a not-yet-synced item');
          }
          return _json({'items': []});
        }),
        localStore: InMemoryTodoLocalStore(
          initial: {
            'trip-1': [
              const TodoItem(
                localId: 'local-1',
                tripId: 'trip-1',
                name: 'Draft item',
              ),
            ],
          },
        ),
      );
      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.sync), findsOneWidget);

      await tester.tap(find.text('Draft item'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.sync), findsOneWidget);
    });

    testWidgets('a blank name is rejected before hitting the network', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        todoHttpClient: MockClient((request) async {
          if (request.method == 'POST') {
            fail('should not create with a blank name');
          }
          return _json({'items': []});
        }),
      );
      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('A name is required.'), findsOneWidget);
    });
  });
}
