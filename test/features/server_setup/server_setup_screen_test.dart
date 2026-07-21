import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/network/api_client.dart';

import '../../test_helpers.dart';

void main() {
  Future<InMemoryServerConfigStorage> pumpApp(WidgetTester tester) async {
    final storage = InMemoryServerConfigStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverConfigStorageProvider.overrideWithValue(storage),
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
    // Only the public URL is collected here — private endpoints are a
    // power-user setting edited later from NetworkingSettingsScreen, not
    // asked for during first-run onboarding.
    expect(saved?.privateEndpoints, isEmpty);
  });

  testWidgets('has exactly one field (the public URL)', (tester) async {
    await pumpApp(tester);

    expect(find.byType(TextFormField), findsOneWidget);
  });
}
