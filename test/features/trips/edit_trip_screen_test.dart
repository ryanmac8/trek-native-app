import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/features/trips/edit_trip_screen.dart';
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

final _nzTrip = Trip.fromJson({
  'id': 20,
  'title': 'New Zealand',
  'description': 'ATL to Auckland',
  'start_date': '2026-11-28',
  'end_date': '2026-12-13',
  'currency': 'USD',
});

Future<void> _pumpEditTripScreen(
  WidgetTester tester, {
  required http.Client httpClient,
  InMemoryTripsLocalStore? localStore,
  Trip? trip,
}) async {
  // Matches how TripDashboardScreen actually navigates here
  // (`context.push('/trips/:id/edit', extra: trip)`) — EditTripScreen calls
  // `context.pop(trip)` on success, which needs a real GoRouter ancestor.
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => context.push('/edit', extra: trip ?? _nzTrip),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/edit',
        builder: (context, state) => EditTripScreen(trip: state.extra! as Trip),
      ),
    ],
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
        tripsLocalStoreProvider.overrideWithValue(
          localStore ?? InMemoryTripsLocalStore(initial: [trip ?? _nzTrip]),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('prefills the form with the trip\'s current values', (
    tester,
  ) async {
    await _pumpEditTripScreen(
      tester,
      httpClient: MockClient((request) async {
        fail('should not hit the network before saving');
      }),
    );

    expect(find.text('New Zealand'), findsOneWidget);
    expect(find.text('ATL to Auckland'), findsOneWidget);
    // Not a text finder — the currency field's hint text is also literally
    // "USD", so that would ambiguously match both it and the prefilled
    // value. Read the controller directly instead.
    final currencyField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Currency — optional'),
    );
    expect(currencyField.controller?.text, 'USD');
  });

  testWidgets('requires a title before submitting', (tester) async {
    await _pumpEditTripScreen(
      tester,
      httpClient: MockClient((request) async {
        fail('should not hit the network when validation fails');
      }),
    );

    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), '');
    await tester.tap(find.text('Save changes'));
    await tester.pump();

    expect(find.text('A title is required.'), findsOneWidget);
  });

  testWidgets('submitting a valid edit saves it and pops the screen', (
    tester,
  ) async {
    final localStore = InMemoryTripsLocalStore(initial: [_nzTrip]);
    await _pumpEditTripScreen(
      tester,
      localStore: localStore,
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['title'], 'Aotearoa');
        return _json({
          'trip': {'id': 20, 'title': 'Aotearoa'},
        });
      }),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Aotearoa',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.byType(EditTripScreen), findsNothing);
    expect((await localStore.read()).single.title, 'Aotearoa');
  });

  testWidgets('a validation rejection from the server is shown inline, without '
      'popping the screen', (tester) async {
    await _pumpEditTripScreen(
      tester,
      httpClient: MockClient(
        (request) async =>
            _json({'error': 'End date must be after start date'}, 400),
      ),
    );

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('End date must be after start date'), findsOneWidget);
    expect(find.byType(EditTripScreen), findsOneWidget);
  });

  testWidgets('saving while offline still pops the screen and applies the edit '
      'locally, rather than blocking or failing', (tester) async {
    final localStore = InMemoryTripsLocalStore(initial: [_nzTrip]);
    await _pumpEditTripScreen(
      tester,
      localStore: localStore,
      httpClient: MockClient((request) async {
        throw http.ClientException('Connection refused');
      }),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Aotearoa',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.byType(EditTripScreen), findsNothing);
    final cached = await localStore.read();
    expect(cached.single.title, 'Aotearoa');
    expect(cached.single.hasPendingEdit, isTrue);
  });
}
