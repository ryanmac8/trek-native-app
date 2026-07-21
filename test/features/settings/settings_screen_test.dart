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

import '../../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

Future<AuthService> _pumpAtSettingsHub(WidgetTester tester) async {
  final authService = AuthService(
    apiClient: ApiClient(
      baseUrl: 'https://trek.example.com',
      httpClient: MockClient((request) async => _json({})),
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
            initial: const ServerConfig(publicUrl: 'https://trek.example.com'),
          ),
        ),
        apiClientProvider.overrideWithValue(
          ApiClient(
            baseUrl: 'https://trek.example.com',
            httpClient: MockClient((request) async => _json({'trips': []})),
          ),
        ),
        tripsLocalStoreProvider.overrideWithValue(InMemoryTripsLocalStore()),
      ],
      child: Consumer(
        builder: (context, ref, _) =>
            MaterialApp.router(routerConfig: ref.watch(appRouterProvider)),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();

  return authService;
}

void main() {
  testWidgets('lists Networking as a sub-page', (tester) async {
    await _pumpAtSettingsHub(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Networking'), findsOneWidget);
  });

  testWidgets('tapping Networking pushes the networking settings screen', (
    tester,
  ) async {
    await _pumpAtSettingsHub(tester);

    await tester.tap(find.text('Networking'));
    await tester.pumpAndSettle();

    expect(find.text('Public server URL'), findsOneWidget);
    // Pushed (not go/replaced) — there's a way back to the hub.
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('logging out from the settings hub returns to login', (
    tester,
  ) async {
    final authService = await _pumpAtSettingsHub(tester);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsWidgets);
    expect(authService.isAuthenticated.value, isFalse);
  });
}
