import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/permissions/app_permission.dart';
import 'package:trek/permissions/permission_gateway.dart';

import '../../test_helpers.dart';

void main() {
  late FakePermissionGateway gateway;

  setUp(() => gateway = FakePermissionGateway());

  Future<InMemoryServerConfigStorage> pumpApp(WidgetTester tester) async {
    final storage = InMemoryServerConfigStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverConfigStorageProvider.overrideWithValue(storage),
          permissionGatewayProvider.overrideWithValue(gateway),
          primingStorageProvider.overrideWithValue(InMemoryPrimingStorage()),
          authServiceProvider.overrideWithValue(
            AuthService(
              apiClient: ApiClient(baseUrl: 'https://placeholder.example.com'),
              tokenStorage: InMemoryTokenStorage(),
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
    return storage;
  }

  testWidgets('rejects an empty public URL', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('A public server URL is required.'), findsOneWidget);
  });

  testWidgets('rejects a malformed public URL', (tester) async {
    await pumpApp(tester);

    await tester.enterText(find.byType(TextFormField).first, 'not-a-url');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter a full server address, e.g. https://trek.example.com'),
      findsOneWidget,
    );
  });

  testWidgets('saves a valid config and proceeds to login', (tester) async {
    final storage = await pumpApp(tester);

    await tester.enterText(
      find.byType(TextFormField).first,
      'https://trek.example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsWidgets);
    final saved = await storage.read();
    expect(saved?.publicUrl, 'https://trek.example.com');
  });

  testWidgets('saves an optional private URL and trusted networks', (
    tester,
  ) async {
    final storage = await pumpApp(tester);
    final fields = find.byType(TextFormField);

    await tester.enterText(fields.at(0), 'https://trek.example.com');
    await tester.enterText(fields.at(1), 'http://192.168.1.50:3000');
    await tester.enterText(fields.at(2), 'Home Wifi, Office');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    // Location priming for Wi-Fi detection — decline it.
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    final saved = await storage.read();
    expect(saved?.privateUrl, 'http://192.168.1.50:3000');
    expect(saved?.trustedWifiNetworks, {'Home Wifi', 'Office'});
  });

  group('location priming for trusted Wi-Fi', () {
    Future<void> submitWithTrustedNetwork(
      WidgetTester tester, {
      String privateUrl = 'http://192.168.1.50:3000',
      String networks = 'Home Wifi',
    }) async {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'https://trek.example.com');
      await tester.enterText(fields.at(1), privateUrl);
      await tester.enterText(fields.at(2), networks);
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
    }

    testWidgets('primes location, then requests it on Continue', (
      tester,
    ) async {
      gateway.requestResults[AppPermission.location] =
          AppPermissionStatus.granted;
      await pumpApp(tester);

      await submitWithTrustedNetwork(tester);
      expect(find.text(AppPermission.location.title), findsOneWidget);
      expect(gateway.requested, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Continue').last);
      await tester.pumpAndSettle();

      expect(gateway.requested, [AppPermission.location]);
      expect(find.text('Log in'), findsWidgets);
    });

    testWidgets('declining still saves and proceeds to login', (tester) async {
      final storage = await pumpApp(tester);

      await submitWithTrustedNetwork(tester);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(gateway.requested, isEmpty);
      expect(find.text('Log in'), findsWidgets);
      expect((await storage.read())?.privateUrl, 'http://192.168.1.50:3000');
    });

    testWidgets('already granted: no sheet', (tester) async {
      gateway.statuses[AppPermission.location] = AppPermissionStatus.granted;
      await pumpApp(tester);

      await submitWithTrustedNetwork(tester);

      expect(find.text(AppPermission.location.title), findsNothing);
      expect(find.text('Log in'), findsWidgets);
    });

    testWidgets('no trusted networks: location is never asked for', (
      tester,
    ) async {
      await pumpApp(tester);

      await submitWithTrustedNetwork(tester, networks: '');

      expect(find.text(AppPermission.location.title), findsNothing);
      expect(find.text('Log in'), findsWidgets);
    });

    testWidgets('no private URL: location is never asked for', (tester) async {
      await pumpApp(tester);

      await submitWithTrustedNetwork(tester, privateUrl: '');

      expect(find.text(AppPermission.location.title), findsNothing);
      expect(find.text('Log in'), findsWidgets);
    });
  });
}
