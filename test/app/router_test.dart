import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/app_lock_state.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/app/router.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/network/api_client.dart';

import '../test_helpers.dart';

void main() {
  late AuthService authService;
  late InMemoryServerConfigStorage serverConfigStorage;
  late AppLockState appLockState;

  setUp(() {
    authService = AuthService(
      apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
      tokenStorage: InMemoryTokenStorage(),
    );
    serverConfigStorage = InMemoryServerConfigStorage();
    appLockState = AppLockState();
  });

  Future<void> pump(
    WidgetTester tester, {
    String initialLocation = '/trips',
  }) async {
    final router = buildAppRouter(
      authService: authService,
      serverConfigStorage: serverConfigStorage,
      appLockState: appLockState,
      initialLocation: initialLocation,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The trip list now fetches on mount — this test cares about
          // routing, not trip data, so a bare empty response is enough.
          apiClientProvider.overrideWithValue(
            ApiClient(
              baseUrl: 'https://trek.example.com',
              httpClient: MockClient(
                (request) async => http.Response(
                  jsonEncode({'trips': []}),
                  200,
                  headers: {'content-type': 'application/json'},
                ),
              ),
            ),
          ),
          tripsLocalStoreProvider.overrideWithValue(InMemoryTripsLocalStore()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('redirects to server setup when no server is configured', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Connect to your Trek server'), findsOneWidget);
  });

  testWidgets('redirects to login once a server is configured', (tester) async {
    await serverConfigStorage.write(
      const ServerConfig(publicUrl: 'https://trek.example.com'),
    );

    await pump(tester);

    expect(find.text('Log in'), findsWidgets);
  });

  testWidgets(
    'redirects an authenticated user away from /server-setup and /login',
    (tester) async {
      await serverConfigStorage.write(
        const ServerConfig(publicUrl: 'https://trek.example.com'),
      );
      authService.isAuthenticated.value = true;

      await pump(tester, initialLocation: '/login');

      expect(find.text('Trips'), findsOneWidget);
    },
  );

  testWidgets('lets an authenticated user reach the trip list directly', (
    tester,
  ) async {
    await serverConfigStorage.write(
      const ServerConfig(publicUrl: 'https://trek.example.com'),
    );
    authService.isAuthenticated.value = true;

    await pump(tester);

    expect(find.text('Trips'), findsOneWidget);
  });

  testWidgets('re-evaluates the redirect when isAuthenticated changes', (
    tester,
  ) async {
    await serverConfigStorage.write(
      const ServerConfig(publicUrl: 'https://trek.example.com'),
    );

    await pump(tester);
    expect(find.text('Log in'), findsWidgets);

    authService.isAuthenticated.value = true;
    await tester.pumpAndSettle();

    expect(find.text('Trips'), findsOneWidget);
  });
}
