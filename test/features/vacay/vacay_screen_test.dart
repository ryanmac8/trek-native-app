import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/features/vacay/vacay_screen.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/vacay/vacay_api.dart';
import 'package:trek/vacay/vacay_local_store.dart';
import 'package:trek/vacay/vacay_models.dart';
import 'package:trek/vacay/vacay_repository.dart';

import '../../vacay/vacay_fixtures.dart';

class _InMemoryVacayLocalStore implements VacayLocalStore {
  final _plans = <String, CachedVacay<VacayPlan>>{};
  final _years = <String, CachedVacay<VacayYear>>{};

  @override
  Future<CachedVacay<VacayPlan>?> readPlan(String scope) async => _plans[scope];

  @override
  Future<void> writePlan(String scope, CachedVacay<VacayPlan> plan) async =>
      _plans[scope] = plan;

  @override
  Future<CachedVacay<VacayYear>?> readYear(String scope, int year) async =>
      _years['$scope/$year'];

  @override
  Future<void> writeYear(String scope, CachedVacay<VacayYear> year) async =>
      _years['$scope/${year.value.year}'] = year;
}

void main() {
  late FakeVacayServer server;
  late _InMemoryVacayLocalStore store;

  setUp(() {
    server = FakeVacayServer();
    store = _InMemoryVacayLocalStore();
  });

  VacayRepository buildRepository() => VacayRepository(
    vacayApi: VacayApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: server.client,
      ),
    ),
    localStore: store,
    cacheScope: () async => 'scope',
    clock: () => DateTime.utc(2026, 9, 20, 12),
  );

  Future<void> pumpVacay(WidgetTester tester) async {
    // A phone-sized viewport tall enough to lay out every card.
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vacayRepositoryProvider.overrideWithValue(buildRepository()),
        ],
        child: MaterialApp(
          home: VacayScreen(clock: () => DateTime(2026, 9, 25, 10)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the current year\'s allowances, days off, and settings', (
    tester,
  ) async {
    await pumpVacay(tester);

    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '2026'),
    );
    expect(chip.selected, isTrue);

    expect(find.text('23.5 left'), findsOneWidget);
    expect(
      find.text('Used 4.5 of 28 · 3 carried over · 1 comp day'),
      findsOneWidget,
    );
    expect(find.text('2 over'), findsOneWidget);
    expect(find.text('Leave year Apr 6, 2026 – Apr 5, 2027'), findsOneWidget);

    expect(find.text('March 2026'), findsOneWidget);
    expect(find.text('Mon 2'), findsOneWidget);
    expect(find.text('Half day'), findsOneWidget);
    expect(find.text('Comp'), findsOneWidget);
    expect(find.text('December 2026'), findsOneWidget);
    expect(find.text('Company holiday · Office closed'), findsOneWidget);

    expect(find.text('Shared plan'), findsOneWidget);
    expect(find.text('1 pending invite'), findsOneWidget);
    expect(find.text('Sun, Sat'), findsOneWidget);
    expect(find.text('NZ Public Holidays'), findsOneWidget);
    expect(find.textContaining('Offline'), findsNothing);
  });

  testWidgets('switching years loads that year', (tester) async {
    await pumpVacay(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, '2025'));
    await tester.pumpAndSettle();

    expect(find.text('March 2025'), findsOneWidget);
    expect(find.text('March 2026'), findsNothing);
    expect(
      server.requests.map((r) => r.url.path),
      contains('/api/addons/vacay/entries/2025'),
    );
  });

  testWidgets('offline with a cache shows the cached plan marked stale', (
    tester,
  ) async {
    final repository = buildRepository();
    await repository.refreshPlan();
    await repository.refreshYear(2026);
    server.offline = true;

    await pumpVacay(tester);

    expect(find.text('23.5 left'), findsOneWidget);
    expect(
      find.textContaining('Offline — showing your plan from'),
      findsOneWidget,
    );
  });

  testWidgets('offline with a cached plan but an unloaded year says so', (
    tester,
  ) async {
    await buildRepository().refreshPlan();
    server.offline = true;

    await pumpVacay(tester);

    expect(find.text('Shared plan'), findsOneWidget);
    expect(
      find.text("You're offline, and 2026 hasn't been loaded yet."),
      findsOneWidget,
    );

    server.offline = false;
    await tester.tap(find.text('Retry').last);
    await tester.pumpAndSettle();

    expect(find.text('23.5 left'), findsOneWidget);
  });

  testWidgets('offline with no cache shows an explicit offline state', (
    tester,
  ) async {
    server.offline = true;

    await pumpVacay(tester);

    expect(
      find.text("You're offline, and your Vacay plan hasn't been loaded yet."),
      findsOneWidget,
    );

    server.offline = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('23.5 left'), findsOneWidget);
  });

  testWidgets('a year with nothing booked says so', (tester) async {
    server.entries = (_) => {
      'entries': <dynamic>[],
      'companyHolidays': <dynamic>[],
    };

    await pumpVacay(tester);

    expect(find.text('No days off booked in 2026.'), findsOneWidget);
  });

  testWidgets('a plan with no tracked years shows an empty state', (
    tester,
  ) async {
    server.years = {'years': <dynamic>[]};

    await pumpVacay(tester);

    expect(find.text('No years tracked yet.'), findsOneWidget);
  });
}
