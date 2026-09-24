import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/atlas/atlas_api.dart';
import 'package:trek/atlas/atlas_local_store.dart';
import 'package:trek/atlas/atlas_models.dart';
import 'package:trek/atlas/atlas_repository.dart';
import 'package:trek/features/atlas/atlas_screen.dart';
import 'package:trek/network/api_client.dart';

import '../../atlas/atlas_fixtures.dart';

class _InMemoryAtlasLocalStore implements AtlasLocalStore {
  final _entries = <String, CachedAtlasStats>{};

  @override
  Future<CachedAtlasStats?> read(String scope) async => _entries[scope];

  @override
  Future<void> write(String scope, CachedAtlasStats stats) async =>
      _entries[scope] = stats;
}

void main() {
  late bool offline;
  late Map<String, dynamic> body;
  late _InMemoryAtlasLocalStore store;

  setUp(() {
    offline = false;
    body = fullStatsJson();
    store = _InMemoryAtlasLocalStore();
  });

  AtlasRepository buildRepository() => AtlasRepository(
    atlasApi: AtlasApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient((request) async {
          if (offline) throw const SocketException('Network is unreachable');
          return http.Response(jsonEncode(body), 200);
        }),
      ),
    ),
    localStore: store,
    cacheScope: () async => 'scope',
    clock: () => DateTime.utc(2026, 9, 20, 12),
  );

  Future<void> pumpAtlas(WidgetTester tester) async {
    // A phone-sized viewport tall enough to lay out every card.
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          atlasRepositoryProvider.overrideWithValue(buildRepository()),
        ],
        child: MaterialApp(
          home: AtlasScreen(clock: () => DateTime(2026, 9, 24, 10)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows fresh stats with countdowns computed on device', (
    tester,
  ) async {
    await pumpAtlas(tester);

    expect(find.text('Japan'), findsOneWidget);
    expect(find.text('In 10 days'), findsOneWidget);
    expect(find.textContaining('New Zealand'), findsOneWidget);
    expect(find.text('Countries'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    expect(find.text('3 years'), findsOneWidget);
    expect(find.text('Oceania'), findsOneWidget);
    expect(find.textContaining('Offline'), findsNothing);
  });

  testWidgets('hides a next trip whose start date has already passed', (
    tester,
  ) async {
    body = fullStatsJson()
      ..['nextTrip'] = {'id': 21, 'title': 'Japan', 'start_date': '2026-09-01'};

    await pumpAtlas(tester);

    expect(find.text('Next trip'), findsNothing);
  });

  testWidgets('offline with a cache shows the cached stats marked stale', (
    tester,
  ) async {
    await buildRepository().refreshStats();
    offline = true;

    await pumpAtlas(tester);

    expect(find.text('Japan'), findsOneWidget);
    expect(find.textContaining('Offline — showing stats from'), findsOneWidget);
  });

  testWidgets('offline with no cache shows an explicit offline state', (
    tester,
  ) async {
    offline = true;

    await pumpAtlas(tester);

    expect(
      find.text("You're offline, and your Atlas hasn't been loaded yet."),
      findsOneWidget,
    );

    offline = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Japan'), findsOneWidget);
  });

  testWidgets('shows an empty state when there is nothing to show', (
    tester,
  ) async {
    body = {
      'countries': <dynamic>[],
      'trips': <dynamic>[],
      'stats': {'totalTrips': 0, 'totalPlaces': 0, 'totalCountries': 0},
    };

    await pumpAtlas(tester);

    expect(find.textContaining('No travels yet.'), findsOneWidget);
  });
}
