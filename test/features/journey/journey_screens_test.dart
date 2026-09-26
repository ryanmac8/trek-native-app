import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/features/journey/journey_detail_screen.dart';
import 'package:trek/features/journey/journey_list_screen.dart';
import 'package:trek/journey/journey_api.dart';
import 'package:trek/journey/journey_repository.dart';
import 'package:trek/network/api_client.dart';

import '../../journey/journey_fixtures.dart';

void main() {
  late FakeJourneyServer server;
  late MemoryJourneyLocalStore store;

  JourneyRepository buildRepository() => JourneyRepository(
    journeyApi: JourneyApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: server.client,
      ),
    ),
    localStore: store,
    cacheScope: () async => 'scope',
    clock: () => DateTime(2026, 9, 20, 8, 5),
  );

  Future<void> pumpApp(WidgetTester tester, {String initial = '/journeys'}) {
    // Tall enough that the whole journey detail is laid out at once.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/journeys',
          builder: (context, state) => const JourneyListScreen(),
        ),
        GoRoute(
          path: '/journeys/:id',
          builder: (context, state) => JourneyDetailScreen(
            journeyId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ],
    );
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          journeyRepositoryProvider.overrideWithValue(buildRepository()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  setUp(() {
    server = FakeJourneyServer();
    store = MemoryJourneyLocalStore();
  });

  group('JourneyListScreen', () {
    testWidgets('lists journeys with dates, counts, and status', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.pumpAndSettle();

      expect(find.text('South Island loop'), findsOneWidget);
      expect(find.text('Two weeks in a campervan'), findsOneWidget);
      expect(find.text('Feb 1, 2026 – Feb 14, 2026'), findsOneWidget);
      expect(find.text('3 entries · 1 photo · 2 places'), findsOneWidget);
      expect(find.text('Lisbon weekend'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.textContaining('Offline'), findsNothing);
    });

    testWidgets('tapping a journey opens its detail', (tester) async {
      await pumpApp(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('South Island loop'));
      await tester.pumpAndSettle();

      expect(find.text('Arrival in Christchurch'), findsOneWidget);
    });

    testWidgets('offline with a cache shows the snapshot and a banner', (
      tester,
    ) async {
      await buildRepository().refreshList();
      server.offline = true;

      await pumpApp(tester);
      await tester.pumpAndSettle();

      expect(find.text('South Island loop'), findsOneWidget);
      expect(
        find.text('Offline — showing your journeys from 2026-09-20 08:05.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'offline with no cache shows an offline state; Retry recovers',
      (tester) async {
        server.offline = true;
        await pumpApp(tester);
        await tester.pumpAndSettle();

        expect(
          find.text(
            "You're offline, and there's no saved copy of your journeys yet.",
          ),
          findsOneWidget,
        );

        server.offline = false;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(find.text('South Island loop'), findsOneWidget);
      },
    );

    testWidgets('an empty list shows an empty state', (tester) async {
      server.list = {'journeys': []};
      await pumpApp(tester);
      await tester.pumpAndSettle();

      expect(find.text('No journeys yet.'), findsOneWidget);
    });

    testWidgets('the addon gate replaces even a cached list', (tester) async {
      await buildRepository().refreshList();
      server.addonDisabled = true;

      await pumpApp(tester);
      await tester.pumpAndSettle();

      expect(
        find.text("The Journey addon isn't enabled on this server."),
        findsOneWidget,
      );
      expect(find.text('South Island loop'), findsNothing);
    });
  });

  group('JourneyDetailScreen', () {
    testWidgets('shows stats, trips, contributors, and entries by date', (
      tester,
    ) async {
      await pumpApp(tester, initial: '/journeys/7');
      await tester.pumpAndSettle();

      expect(find.text('South Island loop'), findsOneWidget); // app bar
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Entries'), findsOneWidget);
      expect(find.text('New Zealand'), findsOneWidget);
      expect(find.text('Feb 1, 2026 – Feb 14, 2026 · 12 places'), findsOne);
      expect(find.text('sam · Editor'), findsOneWidget);

      expect(find.text('Feb 1, 2026'), findsOneWidget);
      expect(find.text('Arrival in Christchurch'), findsOneWidget);
      expect(find.text('14:30 · Christchurch · happy · sunny'), findsOneWidget);
      expect(find.text('+ Easy pickup'), findsOneWidget);
      expect(find.text('roadtrip'), findsOneWidget);
      expect(find.text('Sumner Beach'), findsOneWidget);

      expect(find.text('Lake Tekapo'), findsOneWidget);
      expect(find.text('Suggested from New Zealand'), findsOneWidget);
    });

    testWidgets('hides skeleton suggestions when the viewer opted out', (
      tester,
    ) async {
      server.journey = (id) => journeyJson(hideSkeletons: true);
      await pumpApp(tester, initial: '/journeys/7');
      await tester.pumpAndSettle();

      expect(find.text('Arrival in Christchurch'), findsOneWidget);
      expect(find.text('Lake Tekapo'), findsNothing);
    });

    testWidgets('offline with a cache shows the snapshot and a banner', (
      tester,
    ) async {
      await buildRepository().refreshJourney(7);
      server.offline = true;

      await pumpApp(tester, initial: '/journeys/7');
      await tester.pumpAndSettle();

      expect(find.text('Arrival in Christchurch'), findsOneWidget);
      expect(
        find.text('Offline — showing this journey from 2026-09-20 08:05.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'offline with no cache shows an offline state; Retry recovers',
      (tester) async {
        server.offline = true;
        await pumpApp(tester, initial: '/journeys/7');
        await tester.pumpAndSettle();

        expect(
          find.text(
            "You're offline, and there's no saved copy of this journey yet.",
          ),
          findsOneWidget,
        );

        server.offline = false;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(find.text('Arrival in Christchurch'), findsOneWidget);
      },
    );

    testWidgets('a deleted or unshared journey replaces the cached copy', (
      tester,
    ) async {
      await buildRepository().refreshJourney(7);
      server.journey = (id) => null;

      await pumpApp(tester, initial: '/journeys/7');
      await tester.pumpAndSettle();

      expect(
        find.text('This journey no longer exists or was unshared.'),
        findsOneWidget,
      );
      expect(find.text('Arrival in Christchurch'), findsNothing);
    });

    testWidgets('a journey with no entries shows an empty state', (
      tester,
    ) async {
      server.journey = (id) => journeyJson()
        ..['entries'] = []
        ..['trips'] = []
        ..['contributors'] = [];
      await pumpApp(tester, initial: '/journeys/7');
      await tester.pumpAndSettle();

      expect(find.text('No entries yet.'), findsOneWidget);
    });
  });
}
