import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/app/router.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/network/api_client.dart';

import '../test_helpers.dart';

void main() {
  late AuthService authService;
  late InMemoryServerConfigStorage serverConfigStorage;
  late InMemoryOnboardingStorage onboardingStorage;

  setUp(() {
    authService = AuthService(
      apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
      tokenStorage: InMemoryTokenStorage(),
    );
    serverConfigStorage = InMemoryServerConfigStorage();
    onboardingStorage = InMemoryOnboardingStorage(seen: true);
  });

  Future<void> pump(
    WidgetTester tester, {
    String initialLocation = '/trips',
  }) async {
    final router = buildAppRouter(
      authService: authService,
      serverConfigStorage: serverConfigStorage,
      onboardingStorage: onboardingStorage,
      initialLocation: initialLocation,
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('redirects a fresh install to the welcome screens', (
    tester,
  ) async {
    onboardingStorage.seen = false;

    await pump(tester);

    expect(find.text('Your trips. Your plan.'), findsOneWidget);
  });

  testWidgets(
    'skips the welcome for an existing install that already has a server',
    (tester) async {
      onboardingStorage.seen = false;
      await serverConfigStorage.write(
        const ServerConfig(publicUrl: 'https://trek.example.com'),
      );

      await pump(tester, initialLocation: '/welcome');

      expect(find.text('Log in'), findsWidgets);
    },
  );

  testWidgets('redirects an authenticated user away from /welcome', (
    tester,
  ) async {
    await serverConfigStorage.write(
      const ServerConfig(publicUrl: 'https://trek.example.com'),
    );
    authService.isAuthenticated.value = true;

    await pump(tester, initialLocation: '/welcome');

    expect(find.text('Trips'), findsOneWidget);
  });

  testWidgets('redirects to server setup once the welcome has been seen', (
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
