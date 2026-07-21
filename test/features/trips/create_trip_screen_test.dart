import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/features/trips/create_trip_screen.dart';
import 'package:trek/network/api_client.dart';

import '../../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

Future<void> _pumpCreateTripScreen(
  WidgetTester tester, {
  required http.Client httpClient,
  InMemoryTripsLocalStore? localStore,
}) async {
  // A minimal GoRouter, matching how TripListScreen actually navigates
  // here (`context.push('/trips/new')`) — CreateTripScreen calls
  // `context.pop()` on success, which needs a real GoRouter ancestor, not
  // just a plain Navigator.
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => context.push('/new'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/new',
        builder: (context, state) => const CreateTripScreen(),
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
          localStore ?? InMemoryTripsLocalStore(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('requires a title before submitting', (tester) async {
    await _pumpCreateTripScreen(
      tester,
      httpClient: MockClient((request) async {
        fail('should not hit the network when validation fails');
      }),
    );

    await tester.tap(find.text('Create trip'));
    await tester.pump();

    expect(find.text('A title is required.'), findsOneWidget);
  });

  testWidgets('submitting a valid form creates the trip and pops the screen', (
    tester,
  ) async {
    final localStore = InMemoryTripsLocalStore();
    await _pumpCreateTripScreen(
      tester,
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['title'], 'Iceland');
        return _json({
          'trip': {'id': 7, 'title': 'Iceland'},
        }, 201);
      }),
      localStore: localStore,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Iceland',
    );
    await tester.tap(find.text('Create trip'));
    await tester.pumpAndSettle();

    expect(find.byType(CreateTripScreen), findsNothing);
    final cached = await localStore.read();
    expect(cached.single.id, 7);
  });

  testWidgets('a validation rejection from the server is shown inline, without '
      'popping the screen', (tester) async {
    final localStore = InMemoryTripsLocalStore();
    await _pumpCreateTripScreen(
      tester,
      httpClient: MockClient(
        (request) async =>
            _json({'error': 'End date must be after start date'}, 400),
      ),
      localStore: localStore,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Iceland',
    );
    await tester.tap(find.text('Create trip'));
    await tester.pumpAndSettle();

    expect(find.text('End date must be after start date'), findsOneWidget);
    expect(find.byType(CreateTripScreen), findsOneWidget);
    expect(await localStore.read(), isEmpty);
  });

  testWidgets(
    'submitting while offline still pops the screen and queues the trip '
    'locally, rather than blocking or failing',
    (tester) async {
      final localStore = InMemoryTripsLocalStore();
      await _pumpCreateTripScreen(
        tester,
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
        localStore: localStore,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Iceland',
      );
      await tester.tap(find.text('Create trip'));
      await tester.pumpAndSettle();

      expect(find.byType(CreateTripScreen), findsNothing);
      final cached = await localStore.read();
      expect(cached.single.isPending, isTrue);
      expect(cached.single.title, 'Iceland');
    },
  );
}
