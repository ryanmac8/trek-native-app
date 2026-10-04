import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/app/trek_app.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/auth/session_token.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/network/api_client.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('starts on server setup when no server is configured yet', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverConfigStorageProvider.overrideWithValue(
            InMemoryServerConfigStorage(),
          ),
          // Avoids the flutter_secure_storage platform channel, which
          // isn't mocked in widget tests.
          authServiceProvider.overrideWithValue(
            AuthService(
              apiClient: ApiClient(baseUrl: 'https://placeholder.example.com'),
              tokenStorage: InMemoryTokenStorage(),
            ),
          ),
          // Avoids the local_auth platform channel, also unmocked here.
          biometricAuthServiceProvider.overrideWithValue(
            FakeBiometricAuthService(),
          ),
          appLockPreferenceStorageProvider.overrideWithValue(
            InMemoryAppLockPreferenceStorage(),
          ),
        ],
        child: const TrekApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect to your Trek server'), findsOneWidget);
  });

  testWidgets('fails closed to the login flow when session restore throws', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverConfigStorageProvider.overrideWithValue(
            InMemoryServerConfigStorage(
              initial: const ServerConfig(
                publicUrl: 'https://trek.example.com',
              ),
            ),
          ),
          authServiceProvider.overrideWithValue(
            AuthService(
              apiClient: ApiClient(baseUrl: 'https://placeholder.example.com'),
              tokenStorage: ThrowingTokenStorage(),
            ),
          ),
          biometricAuthServiceProvider.overrideWithValue(
            FakeBiometricAuthService(),
          ),
          appLockPreferenceStorageProvider.overrideWithValue(
            InMemoryAppLockPreferenceStorage(),
          ),
        ],
        child: const TrekApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Doesn't hang or crash — proceeds to login with isAuthenticated
    // left at its default false, and surfaces the failure.
    expect(find.text('Log in'), findsWidgets);
    expect(
      find.text('Could not restore your session. Please log in.'),
      findsOneWidget,
    );
  });

  group('app lock preference at startup', () {
    Future<void> pumpRestoredSession(
      WidgetTester tester, {
      required bool? storedLockEnabled,
    }) async {
      final tokenStorage = InMemoryTokenStorage();
      final expiry = DateTime.now().add(const Duration(days: 1));
      await tokenStorage.write(
        SessionToken.fromJwt(
          fakeJwt({'exp': expiry.millisecondsSinceEpoch ~/ 1000}),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverConfigStorageProvider.overrideWithValue(
              InMemoryServerConfigStorage(
                initial: const ServerConfig(
                  publicUrl: 'https://trek.example.com',
                ),
              ),
            ),
            authServiceProvider.overrideWithValue(
              AuthService(
                apiClient: ApiClient(
                  baseUrl: 'https://placeholder.example.com',
                ),
                tokenStorage: tokenStorage,
              ),
            ),
            biometricAuthServiceProvider.overrideWithValue(
              FakeBiometricAuthService(
                available: true,
                authenticateResult: false,
              ),
            ),
            appLockPreferenceStorageProvider.overrideWithValue(
              InMemoryAppLockPreferenceStorage(enabled: storedLockEnabled),
            ),
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
            tripsLocalStoreProvider.overrideWithValue(
              InMemoryTripsLocalStore(),
            ),
          ],
          child: const TrekApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('locks by default when nothing has been stored', (
      tester,
    ) async {
      await pumpRestoredSession(tester, storedLockEnabled: null);

      expect(find.text('Trek is locked'), findsOneWidget);
    });

    testWidgets('opens straight to the trip list when app lock is off', (
      tester,
    ) async {
      await pumpRestoredSession(tester, storedLockEnabled: false);

      expect(find.text('Trek is locked'), findsNothing);
      expect(find.text('Trips'), findsOneWidget);
    });
  });
}
