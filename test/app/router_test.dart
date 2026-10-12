import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/app/router.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/features/share_import/share_import_api.dart';
import 'package:trek/features/share_import/share_import_repository.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/share_intake/shared_map_link.dart';

import '../test_helpers.dart';

void main() {
  late AuthService authService;
  late InMemoryServerConfigStorage serverConfigStorage;

  setUp(() {
    authService = AuthService(
      apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
      tokenStorage: InMemoryTokenStorage(),
    );
    serverConfigStorage = InMemoryServerConfigStorage();
  });

  Future<void> pump(
    WidgetTester tester, {
    String initialLocation = '/trips',
  }) async {
    final router = buildAppRouter(
      authService: authService,
      serverConfigStorage: serverConfigStorage,
      initialLocation: initialLocation,
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
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

  group('shared map link', () {
    late ValueNotifier<SharedMapLink?> incoming;

    setUp(() {
      incoming = ValueNotifier(null);
    });

    Future<void> pumpWithShare(
      WidgetTester tester, {
      String initialLocation = '/trips',
    }) async {
      final router = buildAppRouter(
        authService: authService,
        serverConfigStorage: serverConfigStorage,
        incomingShare: incoming,
        initialLocation: initialLocation,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            incomingShareProvider.overrideWithValue(incoming),
            // Offline, so the share screen renders without real network.
            shareImportRepositoryProvider.overrideWithValue(
              ShareImportRepository(
                api: ShareImportApi(
                  apiClient: ApiClient(
                    baseUrl: 'https://trek.example.com',
                    httpClient: MockClient(
                      (_) async => throw const SocketException('offline'),
                    ),
                  ),
                ),
                store: InMemoryShareImportStore(),
                currentServer: () async => 'https://trek.example.com',
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    final link = SharedMapLink.parse('https://maps.app.goo.gl/abc')!;

    testWidgets('a share while signed in opens /share-import', (tester) async {
      await serverConfigStorage.write(
        const ServerConfig(publicUrl: 'https://trek.example.com'),
      );
      authService.isAuthenticated.value = true;
      await pumpWithShare(tester);
      expect(find.text('Trips'), findsOneWidget);

      incoming.value = link;
      await tester.pumpAndSettle();

      expect(find.text('Add to a trip'), findsOneWidget);
    });

    testWidgets('a share while signed out goes through login first', (
      tester,
    ) async {
      await serverConfigStorage.write(
        const ServerConfig(publicUrl: 'https://trek.example.com'),
      );
      incoming.value = link;

      await pumpWithShare(tester);
      expect(find.text('Log in'), findsWidgets);

      authService.isAuthenticated.value = true;
      await tester.pumpAndSettle();

      expect(find.text('Add to a trip'), findsOneWidget);
    });

    testWidgets('/share-import with nothing shared goes to /trips', (
      tester,
    ) async {
      await serverConfigStorage.write(
        const ServerConfig(publicUrl: 'https://trek.example.com'),
      );
      authService.isAuthenticated.value = true;

      await pumpWithShare(tester, initialLocation: '/share-import');

      expect(find.text('Trips'), findsOneWidget);
    });
  });
}
