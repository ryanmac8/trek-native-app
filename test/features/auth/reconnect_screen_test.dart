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

/// Pumps the app with `needsReconnect` already set (so it lands on /trips
/// showing the sync-status banner, per real behavior — a rejected token
/// doesn't sign the user out), then taps the banner's "Reconnect" action
/// to reach [ReconnectScreen] the same way a real user would.
Future<void> _pumpAtReconnect(
  WidgetTester tester, {
  required AuthService authService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        apiClientProvider.overrideWithValue(
          ApiClient(
            baseUrl: 'https://trek.example.com',
            httpClient: MockClient((request) async => _json({'trips': []})),
          ),
        ),
        serverConfigStorageProvider.overrideWithValue(
          InMemoryServerConfigStorage(
            initial: const ServerConfig(publicUrl: 'https://trek.example.com'),
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

  expect(find.text('Reconnect'), findsOneWidget);
  await tester.tap(find.text('Reconnect'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'reconnecting with a password clears needsReconnect and returns to '
    'the app without signing the user out',
    (tester) async {
      final jwt = fakeJwt({
        'id': 1,
        'exp':
            DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
      });
      final authService = AuthService(
        apiClient: ApiClient(
          baseUrl: 'https://trek.example.com',
          httpClient: MockClient(
            (request) async => _json({
              'token': jwt,
              'user': {'id': 1},
            }),
          ),
        ),
        tokenStorage: InMemoryTokenStorage(),
      );
      authService.isAuthenticated.value = true;
      authService.needsReconnect.value = true;

      await _pumpAtReconnect(tester, authService: authService);
      expect(find.text('Reconnect to Trek'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'a@trek.app');
      await tester.enterText(find.byType(TextFormField).last, 'hunter2');
      await tester.tap(find.widgetWithText(FilledButton, 'Reconnect'));
      await tester.pumpAndSettle();

      expect(authService.needsReconnect.value, isFalse);
      expect(authService.isAuthenticated.value, isTrue);
      expect(find.text('Trips'), findsOneWidget);
    },
  );

  testWidgets('an MFA-enabled account completes the code step inline', (
    tester,
  ) async {
    final jwt = fakeJwt({
      'id': 1,
      'exp':
          DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch ~/
          1000,
    });
    final authService = AuthService(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/auth/login') {
            return _json({'mfa_required': true, 'mfa_token': 'short-lived'});
          }
          return _json({
            'token': jwt,
            'user': {'id': 1},
          });
        }),
      ),
      tokenStorage: InMemoryTokenStorage(),
    );
    authService.isAuthenticated.value = true;
    authService.needsReconnect.value = true;

    await _pumpAtReconnect(tester, authService: authService);

    await tester.enterText(find.byType(TextFormField).first, 'a@trek.app');
    await tester.enterText(find.byType(TextFormField).last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Reconnect'));
    await tester.pumpAndSettle();

    // Stays on the same route/screen — no navigation to /login/mfa, which
    // would just bounce back (the router's "not authenticated" gate for
    // /login doesn't apply — this user never stopped being authenticated).
    expect(find.text('Reconnect to Trek'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
    await tester.pumpAndSettle();

    expect(authService.needsReconnect.value, isFalse);
    expect(find.text('Trips'), findsOneWidget);
  });
}
