import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/app_lock_state.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/network/api_client.dart';

import '../../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(jsonEncode(body), statusCode);
}

AuthService _authenticatedAuthService() {
  final authService = AuthService(
    apiClient: ApiClient(
      baseUrl: 'https://trek.example.com',
      httpClient: MockClient((request) async => _json({})),
    ),
    tokenStorage: InMemoryTokenStorage(),
  );
  authService.isAuthenticated.value = true;
  return authService;
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required AuthService authService,
  required bool biometricsAvailable,
  FakeBiometricAuthService? biometricAuthService,
}) async {
  final appLockState = AppLockState()
    ..biometricsAvailable = biometricsAvailable;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        appLockStateProvider.overrideWithValue(appLockState),
        biometricAuthServiceProvider.overrideWithValue(
          biometricAuthService ?? FakeBiometricAuthService(),
        ),
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
  testWidgets(
    'unlocks into the trip list automatically on successful biometrics',
    (tester) async {
      await _pumpApp(
        tester,
        authService: _authenticatedAuthService(),
        biometricsAvailable: true,
        biometricAuthService: FakeBiometricAuthService(
          authenticateResult: true,
        ),
      );

      expect(find.text('Trips'), findsOneWidget);
      expect(find.text('Trek is locked'), findsNothing);
    },
  );

  testWidgets('shows a retry option when biometrics fail', (tester) async {
    await _pumpApp(
      tester,
      authService: _authenticatedAuthService(),
      biometricsAvailable: true,
      biometricAuthService: FakeBiometricAuthService(authenticateResult: false),
    );

    expect(find.text('Trek is locked'), findsOneWidget);
    expect(
      find.text('Authentication failed or was cancelled.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Unlock'), findsOneWidget);
  });

  testWidgets(
    'skips the lock screen entirely when biometrics are unavailable',
    (tester) async {
      await _pumpApp(
        tester,
        authService: _authenticatedAuthService(),
        biometricsAvailable: false,
      );

      expect(find.text('Trek is locked'), findsNothing);
      expect(find.text('Trips'), findsOneWidget);
    },
  );

  testWidgets('log out instead returns to the login screen', (tester) async {
    final authService = _authenticatedAuthService();
    await _pumpApp(
      tester,
      authService: authService,
      biometricsAvailable: true,
      biometricAuthService: FakeBiometricAuthService(authenticateResult: false),
    );
    expect(find.text('Trek is locked'), findsOneWidget);

    await tester.tap(find.text('Log out instead'));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsWidgets);
    expect(authService.isAuthenticated.value, isFalse);
  });
}
