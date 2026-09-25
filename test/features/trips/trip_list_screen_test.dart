import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/vacay/vacay_api.dart';
import 'package:trek/vacay/vacay_local_store.dart';
import 'package:trek/vacay/vacay_models.dart';
import 'package:trek/vacay/vacay_repository.dart';

import '../../test_helpers.dart';
import '../../vacay/vacay_fixtures.dart';

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

  testWidgets('the Vacay action opens the Vacay screen', (tester) async {
    final authService = AuthService(
      apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
      tokenStorage: InMemoryTokenStorage(),
    );
    authService.isAuthenticated.value = true;
    final vacayRepository = VacayRepository(
      vacayApi: VacayApi(
        apiClient: ApiClient(
          baseUrl: 'https://trek.example.com',
          httpClient: FakeVacayServer().client,
        ),
      ),
      localStore: _NoopVacayLocalStore(),
      cacheScope: () async => null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(authService),
          vacayRepositoryProvider.overrideWithValue(vacayRepository),
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

    await tester.tap(find.byTooltip('Vacay'));
    await tester.pumpAndSettle();

    expect(find.text('Vacay'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '2026'), findsOneWidget);
  });
}

class _NoopVacayLocalStore implements VacayLocalStore {
  @override
  Future<CachedVacay<VacayPlan>?> readPlan(String scope) async => null;

  @override
  Future<void> writePlan(String scope, CachedVacay<VacayPlan> plan) async {}

  @override
  Future<CachedVacay<VacayYear>?> readYear(String scope, int year) async =>
      null;

  @override
  Future<void> writeYear(String scope, CachedVacay<VacayYear> year) async {}
}
