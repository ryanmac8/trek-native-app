import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/auth/local_data.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/network/api_client.dart';

import '../../test_helpers.dart';

void main() {
  late FakeAccountScopedData cache;
  late AuthService authService;

  setUp(() {
    cache = FakeAccountScopedData(name: 'trips');
    authService = AuthService(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient(
          (request) async => http.Response(jsonEncode({}), 200),
        ),
      ),
      tokenStorage: InMemoryTokenStorage(),
      localData: LocalDataRegistry()..register(cache),
    );
    authService.isAuthenticated.value = true;
  });

  Future<void> pumpTripList(WidgetTester tester) async {
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
  }

  testWidgets('shows an empty state and logs out back to the login screen', (
    tester,
  ) async {
    await pumpTripList(tester);

    expect(find.text('No trips yet.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsWidgets);
    expect(authService.isAuthenticated.value, isFalse);
    expect(cache.wasCleared, isTrue);
  });

  testWidgets('asks before discarding unsynced changes; cancel keeps them', (
    tester,
  ) async {
    cache.unsynced = 2;
    await pumpTripList(tester);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.text('Discard unsynced changes?'), findsOneWidget);
    expect(find.textContaining('2 changes'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(authService.isAuthenticated.value, isTrue);
    expect(cache.wasCleared, isFalse);
    expect(find.text('No trips yet.'), findsOneWidget);
  });

  testWidgets('logs out and clears unsynced changes once confirmed', (
    tester,
  ) async {
    cache.unsynced = 1;
    await pumpTripList(tester);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 change made'), findsOneWidget);

    await tester.tap(find.text('Log out anyway'));
    await tester.pumpAndSettle();

    expect(authService.isAuthenticated.value, isFalse);
    expect(cache.wasCleared, isTrue);
    expect(find.text('Log in'), findsWidgets);
  });
}
