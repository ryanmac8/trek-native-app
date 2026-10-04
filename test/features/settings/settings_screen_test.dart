import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/app_lock_state.dart';
import 'package:trek/app/app_messenger.dart';
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

Future<AuthService> _pumpAtSettingsHub(
  WidgetTester tester, {
  AppLockState? appLockState,
  FakeBiometricAuthService? biometricAuthService,
  InMemoryAppLockPreferenceStorage? appLockPreferenceStorage,
}) async {
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
        appLockStateProvider.overrideWithValue(appLockState ?? AppLockState()),
        biometricAuthServiceProvider.overrideWithValue(
          biometricAuthService ?? FakeBiometricAuthService(),
        ),
        appLockPreferenceStorageProvider.overrideWithValue(
          appLockPreferenceStorage ?? InMemoryAppLockPreferenceStorage(),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          scaffoldMessengerKey: scaffoldMessengerKey,
          routerConfig: ref.watch(appRouterProvider),
        ),
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

  group('app lock switch', () {
    // Already inside the app (unlocked this run) with biometrics set up.
    AppLockState unlockedState({bool lockEnabled = true}) => AppLockState()
      ..biometricsAvailable = true
      ..lockEnabled.value = lockEnabled
      ..isUnlocked.value = true;

    bool switchValue(WidgetTester tester) => tester
        .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'App lock'))
        .value;

    testWidgets('is disabled when the device has no biometrics', (
      tester,
    ) async {
      await _pumpAtSettingsHub(tester);

      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'App lock'),
      );
      expect(tile.onChanged, isNull);
      expect(tile.value, isFalse);
    });

    testWidgets('turning it off persists locally without a prompt', (
      tester,
    ) async {
      final appLockState = unlockedState();
      final storage = InMemoryAppLockPreferenceStorage();
      final biometrics = FakeBiometricAuthService(available: true);
      await _pumpAtSettingsHub(
        tester,
        appLockState: appLockState,
        biometricAuthService: biometrics,
        appLockPreferenceStorage: storage,
      );
      expect(switchValue(tester), isTrue);

      await tester.tap(find.text('App lock'));
      await tester.pumpAndSettle();

      expect(switchValue(tester), isFalse);
      expect(storage.enabled, isFalse);
      expect(appLockState.lockEnabled.value, isFalse);
      expect(biometrics.authenticateCalls, 0);
    });

    testWidgets('turning it on requires a successful prompt first', (
      tester,
    ) async {
      final appLockState = unlockedState(lockEnabled: false);
      final storage = InMemoryAppLockPreferenceStorage(enabled: false);
      final biometrics = FakeBiometricAuthService(available: true);
      await _pumpAtSettingsHub(
        tester,
        appLockState: appLockState,
        biometricAuthService: biometrics,
        appLockPreferenceStorage: storage,
      );

      await tester.tap(find.text('App lock'));
      await tester.pumpAndSettle();

      expect(biometrics.authenticateCalls, 1);
      expect(switchValue(tester), isTrue);
      expect(storage.enabled, isTrue);
      // Stays in Settings rather than bouncing to /lock.
      expect(find.text('Trek is locked'), findsNothing);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('a failed prompt leaves it off', (tester) async {
      final appLockState = unlockedState(lockEnabled: false);
      final storage = InMemoryAppLockPreferenceStorage(enabled: false);
      await _pumpAtSettingsHub(
        tester,
        appLockState: appLockState,
        biometricAuthService: FakeBiometricAuthService(
          available: true,
          authenticateResult: false,
        ),
        appLockPreferenceStorage: storage,
      );

      await tester.tap(find.text('App lock'));
      await tester.pumpAndSettle();

      expect(switchValue(tester), isFalse);
      expect(storage.enabled, isFalse);
      expect(appLockState.lockEnabled.value, isFalse);
      expect(
        find.text('Could not verify. App lock is still off.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed save keeps the previous value', (tester) async {
      final appLockState = unlockedState();
      await _pumpAtSettingsHub(
        tester,
        appLockState: appLockState,
        biometricAuthService: FakeBiometricAuthService(available: true),
        appLockPreferenceStorage: InMemoryAppLockPreferenceStorage(
          failWrites: true,
        ),
      );

      await tester.tap(find.text('App lock'));
      await tester.pumpAndSettle();

      expect(switchValue(tester), isTrue);
      expect(appLockState.lockEnabled.value, isTrue);
      expect(find.text('Could not save the app lock setting.'), findsOneWidget);
    });
  });
}
