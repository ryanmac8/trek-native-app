import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/journey/journey_api.dart';
import 'package:trek/journey/journey_repository.dart';
import 'package:trek/network/api_client.dart';

import '../../journey/journey_fixtures.dart';
import '../../test_helpers.dart';

void main() {
  testWidgets('shows an empty state and logs out back to the login screen', (
    tester,
  ) async {
    final authService = AuthService(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient(
          (request) async => http.Response(jsonEncode({}), 200),
        ),
      ),
      tokenStorage: InMemoryTokenStorage(),
    );
    authService.isAuthenticated.value = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(authService),
          serverConfigStorageProvider.overrideWithValue(
            InMemoryServerConfigStorage(
              initial: const ServerConfig(
                publicUrl: 'https://trek.example.com',
              ),
            ),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) =>
              MaterialApp.router(routerConfig: ref.watch(appRouterProvider)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No trips yet.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsWidgets);
    expect(authService.isAuthenticated.value, isFalse);
  });

  testWidgets('the Journeys action opens the journey list', (tester) async {
    final authService = AuthService(
      apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
      tokenStorage: InMemoryTokenStorage(),
    );
    authService.isAuthenticated.value = true;
    final journeyRepository = JourneyRepository(
      journeyApi: JourneyApi(
        apiClient: ApiClient(
          baseUrl: 'https://trek.example.com',
          httpClient: FakeJourneyServer().client,
        ),
      ),
      localStore: MemoryJourneyLocalStore(),
      cacheScope: () async => null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(authService),
          journeyRepositoryProvider.overrideWithValue(journeyRepository),
          serverConfigStorageProvider.overrideWithValue(
            InMemoryServerConfigStorage(
              initial: const ServerConfig(
                publicUrl: 'https://trek.example.com',
              ),
            ),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) =>
              MaterialApp.router(routerConfig: ref.watch(appRouterProvider)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Journeys'));
    await tester.pumpAndSettle();

    expect(find.text('Journeys'), findsOneWidget);
    expect(find.text('South Island loop'), findsOneWidget);

    await tester.tap(find.text('South Island loop'));
    await tester.pumpAndSettle();

    expect(find.text('Two weeks in a campervan'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
  });
}
