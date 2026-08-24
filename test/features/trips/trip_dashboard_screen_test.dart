import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/collab/collab_api.dart';
import 'package:trek/collab/collab_note.dart';
import 'package:trek/collab/collab_repository.dart';
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

/// The Notes tab is built (offstage) inside the dashboard's [IndexedStack]
/// on every test, whichever tab is selected — it needs a [CollabRepository]
/// available via [collabRepositoryProvider] regardless. Overriding the
/// repository directly (rather than the underlying [ApiClient]) keeps
/// tests that aren't exercising Notes from having to stand up an
/// `AuthService`.
Future<void> _pumpDashboard(
  WidgetTester tester, {
  http.Client? collabHttpClient,
  InMemoryCollabLocalStore? localStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collabRepositoryProvider.overrideWithValue(
          CollabRepository(
            collabApi: CollabApi(
              apiClient: ApiClient(
                baseUrl: 'https://trek.example.com',
                httpClient:
                    collabHttpClient ??
                    MockClient((request) async => _json({'notes': []})),
              ),
            ),
            localStore: localStore ?? InMemoryCollabLocalStore(),
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
      'Notes',
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

  group('Notes tab', () {
    testWidgets('shows an empty state when the trip has no notes', (
      tester,
    ) async {
      await _pumpDashboard(tester);

      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();

      expect(find.text('No notes yet.'), findsOneWidget);
    });

    testWidgets('renders notes fetched from the real API shape', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        collabHttpClient: MockClient(
          (request) async => _json({
            'notes': [
              {
                'id': 1,
                'trip_id': 'trip-1',
                'title': 'Packing reminders',
                'category': 'Logistics',
                'pinned': 0,
              },
            ],
          }),
        ),
      );

      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();

      expect(find.text('Packing reminders'), findsOneWidget);
      expect(find.textContaining('Logistics'), findsOneWidget);
    });

    testWidgets('a pinned note shows a pin icon', (tester) async {
      await _pumpDashboard(
        tester,
        collabHttpClient: MockClient(
          (request) async => _json({
            'notes': [
              {
                'id': 1,
                'trip_id': 'trip-1',
                'title': 'Packing reminders',
                'pinned': 1,
              },
            ],
          }),
        ),
      );

      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.push_pin), findsOneWidget);
    });

    testWidgets(
      'shows an explicit offline state instead of a spinner when there is '
      'nothing cached and the network is unreachable',
      (tester) async {
        await _pumpDashboard(
          tester,
          collabHttpClient: MockClient((request) async {
            throw http.ClientException('Connection refused');
          }),
        );

        await tester.tap(find.text('Notes'));
        await tester.pumpAndSettle();

        expect(find.textContaining("You're offline"), findsOneWidget);
      },
    );

    testWidgets('a cached note still shows when the network is unreachable', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        collabHttpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: InMemoryCollabLocalStore(
          initial: {
            'trip-1': [
              CollabNote.fromJson({
                'id': 1,
                'trip_id': 'trip-1',
                'title': 'Cached note',
              }, tripId: 'trip-1'),
            ],
          },
        ),
      );

      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();

      expect(find.text('Cached note'), findsOneWidget);
    });

    testWidgets('creating a note adds it to the list immediately', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        collabHttpClient: MockClient((request) async {
          if (request.method == 'POST') {
            return _json({
              'note': {
                'id': 9,
                'trip_id': 'trip-1',
                'title': 'Bring sunscreen',
              },
            }, 201);
          }
          return _json({'notes': []});
        }),
      );
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      expect(find.text('No notes yet.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Bring sunscreen',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Bring sunscreen'), findsOneWidget);
    });

    testWidgets(
      'a note created while offline shows as syncing and stays in the list',
      (tester) async {
        await _pumpDashboard(
          tester,
          collabHttpClient: MockClient((request) async {
            if (request.method == 'POST') {
              throw http.ClientException('Connection refused');
            }
            return _json({'notes': []});
          }),
        );
        await tester.tap(find.text('Notes'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).first,
          'Offline note',
        );
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();

        expect(find.text('Offline note'), findsOneWidget);
        expect(find.text('Syncing…'), findsOneWidget);
      },
    );

    testWidgets('a blank title is rejected before hitting the network', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        collabHttpClient: MockClient((request) async {
          if (request.method == 'POST') {
            fail('should not create with a blank title');
          }
          return _json({'notes': []});
        }),
      );
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('A title is required.'), findsOneWidget);
    });

    testWidgets('editing a note updates it in place', (tester) async {
      await _pumpDashboard(
        tester,
        collabHttpClient: MockClient((request) async {
          if (request.method == 'PUT') {
            return _json({
              'note': {
                'id': 1,
                'trip_id': 'trip-1',
                'title': 'Bring sunscreen and a hat',
              },
            });
          }
          return _json({
            'notes': [
              {'id': 1, 'trip_id': 'trip-1', 'title': 'Bring sunscreen'},
            ],
          });
        }),
      );
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      expect(find.text('Bring sunscreen'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit note'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Bring sunscreen and a hat',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Bring sunscreen and a hat'), findsOneWidget);
      expect(find.text('Bring sunscreen'), findsNothing);
    });

    testWidgets(
      'a note edited while offline shows as syncing and keeps the edit',
      (tester) async {
        await _pumpDashboard(
          tester,
          collabHttpClient: MockClient((request) async {
            if (request.method == 'PUT') {
              throw http.ClientException('Connection refused');
            }
            return _json({
              'notes': [
                {'id': 1, 'trip_id': 'trip-1', 'title': 'Bring sunscreen'},
              ],
            });
          }),
        );
        await tester.tap(find.text('Notes'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).first,
          'Edited offline',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(find.text('Edited offline'), findsOneWidget);
        expect(find.text('Syncing…'), findsOneWidget);
      },
    );

    testWidgets('deleting a note (after confirming) removes it from the list', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        collabHttpClient: MockClient((request) async {
          if (request.method == 'DELETE') {
            return _json({'success': true});
          }
          return _json({
            'notes': [
              {'id': 1, 'trip_id': 'trip-1', 'title': 'Bring sunscreen'},
            ],
          });
        }),
      );
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      expect(find.text('Bring sunscreen'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete note?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Bring sunscreen'), findsNothing);
      expect(find.text('No notes yet.'), findsOneWidget);
    });

    testWidgets('canceling the delete confirmation keeps the note', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        collabHttpClient: MockClient(
          (request) async => _json({
            'notes': [
              {'id': 1, 'trip_id': 'trip-1', 'title': 'Bring sunscreen'},
            ],
          }),
        ),
      );
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Bring sunscreen'), findsOneWidget);
    });

    testWidgets(
      'a note deleted while offline disappears immediately and stays queued',
      (tester) async {
        await _pumpDashboard(
          tester,
          collabHttpClient: MockClient((request) async {
            if (request.method == 'DELETE') {
              throw http.ClientException('Connection refused');
            }
            return _json({
              'notes': [
                {'id': 1, 'trip_id': 'trip-1', 'title': 'Bring sunscreen'},
              ],
            });
          }),
        );
        await tester.tap(find.text('Notes'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        expect(find.text('Bring sunscreen'), findsNothing);
        expect(find.text('No notes yet.'), findsOneWidget);
      },
    );
  });
}
