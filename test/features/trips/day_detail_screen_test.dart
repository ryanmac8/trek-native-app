import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/app_messenger.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/days/day.dart';
import 'package:trek/days/day_note.dart';
import 'package:trek/features/trips/day_detail_screen.dart';
import 'package:trek/network/api_client.dart';

import '../../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

const _day = Day(id: 1, tripId: 20, dayNumber: 1);

Future<InMemoryDaysLocalStore> _pump(
  WidgetTester tester, {
  required http.Client httpClient,
  List<DayNote> notes = const [],
  InMemoryDayNoteOutbox? outbox,
}) async {
  final localStore = InMemoryDaysLocalStore(
    initial: {
      '20': [_day.withNoteItems(notes)],
    },
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(
            baseUrl: 'https://trek.example.com',
            httpClient: httpClient,
          ),
        ),
        daysLocalStoreProvider.overrideWithValue(localStore),
        dayNoteOutboxProvider.overrideWithValue(
          outbox ?? InMemoryDayNoteOutbox(),
        ),
      ],
      child: MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: DayDetailScreen(tripId: '20', day: _day.withNoteItems(notes)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return localStore;
}

Future<void> _fillAndSave(WidgetTester tester, String title) async {
  await tester.enterText(find.byKey(const Key('dayNoteText')), title);
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an empty state when the day has no notes', (tester) async {
    await _pump(
      tester,
      httpClient: MockClient((request) async => _json({'days': []})),
    );

    expect(find.text('Day 1'), findsOneWidget);
    expect(find.text('No notes for this day yet.'), findsOneWidget);
  });

  testWidgets('lists the day\'s notes with their details', (tester) async {
    await _pump(
      tester,
      httpClient: MockClient((request) async => _json({'days': []})),
      notes: const [
        DayNote(id: 7, dayId: 1, text: 'Museum closes early', time: '4pm'),
      ],
    );

    expect(find.text('Museum closes early'), findsOneWidget);
    expect(find.text('4pm'), findsOneWidget);
    expect(find.byKey(const Key('dayNotePending')), findsNothing);
  });

  testWidgets('adding a note online posts it and shows it synced', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await _pump(
      tester,
      httpClient: MockClient((request) async {
        requests.add(request);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({
          'note': {
            'id': 55,
            'day_id': 1,
            'text': body['text'],
            'time': body['time'],
            'icon': body['icon'],
            'color': body['color'],
            'sort_order': 9999,
          },
        }, 201);
      }),
    );

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dayNoteIcon-Plane')));
    await tester.tap(find.byKey(const Key('dayNoteColor-#2563eb')));
    await _fillAndSave(tester, 'Flight at 9');

    expect(requests.single.url.path, '/api/trips/20/days/1/notes');
    expect(jsonDecode(requests.single.body), {
      'text': 'Flight at 9',
      'time': null,
      'icon': 'Plane',
      'color': '#2563eb',
    });
    expect(find.text('Flight at 9'), findsOneWidget);
    expect(find.byKey(const Key('dayNotePending')), findsNothing);
  });

  testWidgets('adding a note offline keeps it, marked as not yet synced', (
    tester,
  ) async {
    final outbox = InMemoryDayNoteOutbox();
    await _pump(
      tester,
      httpClient: MockClient((request) async {
        throw http.ClientException('Connection refused');
      }),
      outbox: outbox,
    );

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    await _fillAndSave(tester, 'Pack the charger');

    expect(find.text('Pack the charger'), findsOneWidget);
    expect(find.byKey(const Key('dayNotePending')), findsOneWidget);
    expect(find.textContaining('sync when you'), findsOneWidget);
    expect(await outbox.read('20'), hasLength(1));
  });

  testWidgets('the title is required', (tester) async {
    await _pump(
      tester,
      httpClient: MockClient((request) async => _json({'days': []})),
    );

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a title for the note.'), findsOneWidget);
  });

  testWidgets('editing and deleting a note', (tester) async {
    final requests = <http.Request>[];
    final localStore = await _pump(
      tester,
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'DELETE') return _json({'success': true});
        return _json({
          'note': {'id': 7, 'day_id': 1, 'text': 'Renamed', 'sort_order': 1},
        });
      }),
      notes: const [DayNote(id: 7, dayId: 1, text: 'Original')],
    );

    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    await _fillAndSave(tester, 'Renamed');

    expect(requests.last.method, 'PUT');
    expect(requests.last.url.path, '/api/trips/20/days/1/notes/7');
    expect(find.text('Renamed'), findsOneWidget);

    await tester.tap(find.text('Renamed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    // Confirmation dialog.
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(requests.last.method, 'DELETE');
    expect(find.text('Renamed'), findsNothing);
    expect((await localStore.read('20')).single.noteItems, isEmpty);
  });

  testWidgets('a rejected write shows an error and is undone', (tester) async {
    await _pump(
      tester,
      httpClient: MockClient((request) async {
        if (request.method == 'GET') {
          return _json({
            'days': [
              {'id': 1, 'trip_id': 20, 'day_number': 1, 'notes_items': []},
            ],
          });
        }
        return _json({'error': 'No permission'}, 403);
      }),
    );

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    await _fillAndSave(tester, 'Not allowed');

    expect(find.textContaining("Couldn't save the note"), findsOneWidget);
    expect(find.text('Not allowed'), findsNothing);
  });
}
