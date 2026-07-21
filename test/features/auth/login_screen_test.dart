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

http.Response _json(Map<String, dynamic> body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

Future<void> _pumpLoggedOutApp(
  WidgetTester tester,
  AuthService authService,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        serverConfigStorageProvider.overrideWithValue(
          InMemoryServerConfigStorage(
            initial: const ServerConfig(publicUrl: 'https://trek.example.com'),
          ),
        ),
        // The trip list fetches on mount once login lands there.
        apiClientProvider.overrideWithValue(
          ApiClient(
            baseUrl: 'https://trek.example.com',
            httpClient: MockClient((request) async => _json({'trips': []})),
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

void main() {
  testWidgets('successful login lands on the trip list', (tester) async {
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
    await _pumpLoggedOutApp(tester, authService);

    await tester.enterText(find.byType(TextFormField).first, 'a@trek.app');
    await tester.enterText(find.byType(TextFormField).last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Trips'), findsOneWidget);
  });

  testWidgets('MFA-required login navigates to the code screen', (
    tester,
  ) async {
    final authService = AuthService(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient(
          (request) async =>
              _json({'mfa_required': true, 'mfa_token': 'short-lived'}),
        ),
      ),
      tokenStorage: InMemoryTokenStorage(),
    );
    await _pumpLoggedOutApp(tester, authService);

    await tester.enterText(find.byType(TextFormField).first, 'a@trek.app');
    await tester.enterText(find.byType(TextFormField).last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Two-factor authentication'), findsOneWidget);
  });

  testWidgets('shows an error and stays on the login screen when offline', (
    tester,
  ) async {
    final authService = AuthService(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
      ),
      tokenStorage: InMemoryTokenStorage(),
    );
    await _pumpLoggedOutApp(tester, authService);

    await tester.enterText(find.byType(TextFormField).first, 'a@trek.app');
    await tester.enterText(find.byType(TextFormField).last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    // Still on the login screen — no crash, no silent failure.
    expect(find.text('Log in'), findsWidgets);
    expect(find.text('Unable to reach the server.'), findsOneWidget);
    expect(authService.isAuthenticated.value, isFalse);
  });
}
