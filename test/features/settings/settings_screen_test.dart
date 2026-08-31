import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/account/account_api.dart';
import 'package:trek/account/account_models.dart';
import 'package:trek/account/account_repository.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/features/settings/settings_screen.dart';
import 'package:trek/network/api_client.dart';

import '../../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

AccountRepository _repo(http.Client client, InMemoryAccountLocalStore store) {
  return AccountRepository(
    accountApi: AccountApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: client,
      ),
    ),
    localStore: store,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required AccountRepository repository,
  ServerConfig? serverConfig,
  AuthService? authService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(repository),
        serverConfigStorageProvider.overrideWithValue(
          InMemoryServerConfigStorage(initial: serverConfig),
        ),
        if (authService != null)
          authServiceProvider.overrideWithValue(authService),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows account details from the server', (tester) async {
    await _pump(
      tester,
      repository: _repo(
        MockClient(
          (_) async => _json(
            fakeMeResponse(username: 'grace', email: 'grace@example.com'),
          ),
        ),
        InMemoryAccountLocalStore(),
      ),
    );

    expect(find.text('grace'), findsOneWidget);
    expect(find.text('grace@example.com'), findsOneWidget);
    expect(find.text('MFA off'), findsOneWidget);
  });

  testWidgets('shows the configured server URLs', (tester) async {
    await _pump(
      tester,
      repository: _repo(
        MockClient((_) async => _json(fakeMeResponse())),
        InMemoryAccountLocalStore(),
      ),
      serverConfig: const ServerConfig(
        publicUrl: 'https://trek.example.com',
        privateUrl: 'http://192.168.1.50:3000',
        trustedWifiNetworks: {'HomeNet'},
      ),
    );

    expect(find.text('https://trek.example.com'), findsOneWidget);
    expect(find.text('http://192.168.1.50:3000'), findsOneWidget);
    expect(find.text('HomeNet'), findsOneWidget);
  });

  testWidgets('offline with a cached account shows it with an offline notice', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _repo(
        MockClient((_) async => throw http.ClientException('offline')),
        InMemoryAccountLocalStore(
          initial: const TrekAccount(
            id: 1,
            username: 'cached-grace',
            email: 'grace@example.com',
          ),
        ),
      ),
    );

    expect(find.text('cached-grace'), findsOneWidget);
    expect(find.textContaining('you may be offline'), findsOneWidget);
  });

  testWidgets('offline with nothing cached shows a retry', (tester) async {
    await _pump(
      tester,
      repository: _repo(
        MockClient((_) async => throw http.ClientException('offline')),
        InMemoryAccountLocalStore(),
      ),
    );

    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('sign out clears the session and the cached account', (
    tester,
  ) async {
    final store = InMemoryAccountLocalStore(
      initial: const TrekAccount(id: 1, username: 'grace', email: 'g@e.com'),
    );
    final authService = AuthService(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient((_) async => _json({'success': true})),
      ),
      tokenStorage: InMemoryTokenStorage(),
    );
    authService.isAuthenticated.value = true;

    await _pump(
      tester,
      repository: _repo(
        MockClient((_) async => _json(fakeMeResponse(username: 'grace'))),
        store,
      ),
      authService: authService,
    );

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(authService.isAuthenticated.value, isFalse);
    expect(store.account, isNull);
  });
}
