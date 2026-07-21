import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/config/server_health_check.dart';
import 'package:trek/config/wifi_network_info.dart';
import 'package:trek/network/api_client.dart';

import '../../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

class _FakeWifiNetworkInfo implements WifiNetworkInfo {
  _FakeWifiNetworkInfo(this.ssid);

  String? ssid;

  @override
  Future<String?> currentSsid() async => ssid;
}

/// Navigates trip list -> Settings hub -> Networking, mirroring the real
/// user path now that settings is a hub of sub-pages (see SettingsScreen).
/// The screen's own "Save" button stays in the tree (just visually covered)
/// while the add-endpoint dialog is open, so `find.text('Save')` alone is
/// ambiguous — scope to the dialog.
Finder _dialogButton(String text) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(FilledButton, text),
);

Future<InMemoryServerConfigStorage> _pumpAtNetworkingSettings(
  WidgetTester tester, {
  required InMemoryServerConfigStorage storage,
  WifiNetworkInfo? wifiInfo,
  http.Client? healthCheckHttpClient,
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
        serverConfigStorageProvider.overrideWithValue(storage),
        apiClientProvider.overrideWithValue(
          ApiClient(
            baseUrl: 'https://trek.example.com',
            httpClient: MockClient((request) async => _json({'trips': []})),
          ),
        ),
        // Avoids the shared_preferences platform channel — the trip list
        // this settings screen is pushed from needs it too.
        tripsLocalStoreProvider.overrideWithValue(InMemoryTripsLocalStore()),
        if (wifiInfo != null)
          wifiNetworkInfoProvider.overrideWithValue(wifiInfo),
        serverHealthCheckProvider.overrideWithValue(
          ServerHealthCheck(httpClient: healthCheckHttpClient),
        ),
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
  await tester.tap(find.text('Networking'));
  await tester.pumpAndSettle();

  return storage;
}

void main() {
  testWidgets('pre-fills the public URL and lists private endpoints', (
    tester,
  ) async {
    // Deliberately distinct from the public URL field's hint text (itself
    // "https://trek.example.com") — Flutter keeps a hint's Text widget in
    // the tree even while covered by a value, so a same-string fixture
    // would make find.text() match both.
    await _pumpAtNetworkingSettings(
      tester,
      storage: InMemoryServerConfigStorage(
        initial: const ServerConfig(
          publicUrl: 'https://mytrek.example.org',
          privateEndpoints: [
            PrivateEndpoint(
              url: 'http://10.0.0.5:3000',
              wifiNetwork: 'Home Wifi',
            ),
          ],
        ),
      ),
    );

    expect(find.text('https://mytrek.example.org'), findsOneWidget);
    expect(find.text('Home Wifi'), findsOneWidget);
    expect(find.text('http://10.0.0.5:3000'), findsOneWidget);
  });

  testWidgets('adding a reachable endpoint adds it to the list', (
    tester,
  ) async {
    await _pumpAtNetworkingSettings(
      tester,
      storage: InMemoryServerConfigStorage(
        initial: const ServerConfig(publicUrl: 'https://trek.example.com'),
      ),
      healthCheckHttpClient: MockClient((request) async {
        expect(request.url.path, '/api/health');
        return _json({'status': 'ok'});
      }),
    );

    expect(find.text('No private endpoints added.'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Add endpoint'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Private (LAN) URL'),
      'http://192.168.1.50:3000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Wi-Fi network name'),
      'Home Wifi',
    );
    await tester.tap(_dialogButton('Save'));
    await tester.pumpAndSettle();

    // Dialog closed, endpoint now in the list.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('No private endpoints added.'), findsNothing);
    expect(find.text('Home Wifi'), findsOneWidget);
    expect(find.text('http://192.168.1.50:3000'), findsOneWidget);
  });

  testWidgets('"Use current Wi-Fi network" fills in the current SSID', (
    tester,
  ) async {
    await _pumpAtNetworkingSettings(
      tester,
      storage: InMemoryServerConfigStorage(
        initial: const ServerConfig(publicUrl: 'https://trek.example.com'),
      ),
      wifiInfo: _FakeWifiNetworkInfo('Kitchen Wifi'),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Add endpoint'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use current Wi-Fi network'));
    await tester.pumpAndSettle();

    expect(find.text('Kitchen Wifi'), findsOneWidget);
  });

  testWidgets(
    'an unreachable endpoint shows a warning and can be saved anyway',
    (tester) async {
      await _pumpAtNetworkingSettings(
        tester,
        storage: InMemoryServerConfigStorage(
          initial: const ServerConfig(publicUrl: 'https://trek.example.com'),
        ),
        healthCheckHttpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Add endpoint'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Private (LAN) URL'),
        'http://192.168.1.50:3000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Wi-Fi network name'),
        'Home Wifi',
      );
      await tester.tap(_dialogButton('Save'));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't reach this address from here."),
        findsOneWidget,
      );
      // Still open — not added to the list yet.
      expect(find.text('No private endpoints added.'), findsOneWidget);

      await tester.tap(_dialogButton('Save anyway'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Home Wifi'), findsOneWidget);
    },
  );

  testWidgets('removing an endpoint takes it out of the list', (tester) async {
    await _pumpAtNetworkingSettings(
      tester,
      storage: InMemoryServerConfigStorage(
        initial: const ServerConfig(
          publicUrl: 'https://trek.example.com',
          privateEndpoints: [
            PrivateEndpoint(
              url: 'http://10.0.0.5:3000',
              wifiNetwork: 'Home Wifi',
            ),
          ],
        ),
      ),
    );

    expect(find.text('Home Wifi'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove endpoint'));
    await tester.pumpAndSettle();

    expect(find.text('Home Wifi'), findsNothing);
    expect(find.text('No private endpoints added.'), findsOneWidget);
  });

  testWidgets('saving persists added private endpoints and returns to the '
      'settings hub', (tester) async {
    final storage = await _pumpAtNetworkingSettings(
      tester,
      storage: InMemoryServerConfigStorage(
        initial: const ServerConfig(publicUrl: 'https://trek.example.com'),
      ),
      healthCheckHttpClient: MockClient((request) async => _json({})),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Add endpoint'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Private (LAN) URL'),
      'http://192.168.1.50:3000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Wi-Fi network name'),
      'Home Wifi',
    );
    await tester.tap(_dialogButton('Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final saved = await storage.read();
    expect(saved?.publicUrl, 'https://trek.example.com');
    expect(saved?.privateEndpoints, [
      const PrivateEndpoint(
        url: 'http://192.168.1.50:3000',
        wifiNetwork: 'Home Wifi',
      ),
    ]);
    // context.pop() from Networking returns one level, to the Settings
    // hub — not all the way back to the trip list.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Networking'), findsOneWidget);
  });

  testWidgets('rejects clearing the public URL', (tester) async {
    await _pumpAtNetworkingSettings(
      tester,
      storage: InMemoryServerConfigStorage(
        initial: const ServerConfig(publicUrl: 'https://trek.example.com'),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('A public server URL is required.'), findsOneWidget);
  });
}
