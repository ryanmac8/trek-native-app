import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/features/onboarding/welcome_screen.dart';
import 'package:trek/network/api_client.dart';

import '../../test_helpers.dart';

void main() {
  late InMemoryOnboardingStorage onboardingStorage;

  Future<void> pumpApp(WidgetTester tester) async {
    onboardingStorage = InMemoryOnboardingStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverConfigStorageProvider.overrideWithValue(
            InMemoryServerConfigStorage(),
          ),
          onboardingStorageProvider.overrideWithValue(onboardingStorage),
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
  }

  testWidgets('shows the first welcome page on a fresh install', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text(welcomePages.first.title), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('Next walks through every page to Get started', (tester) async {
    await pumpApp(tester);

    for (final page in welcomePages.skip(1)) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text(page.title), findsOneWidget);
    }

    expect(find.text('Next'), findsNothing);
    expect(find.text('Skip').hitTestable(), findsNothing);
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('swiping also advances the pages', (tester) async {
    await pumpApp(tester);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text(welcomePages[1].title), findsOneWidget);
  });

  testWidgets('Get started records the welcome as seen and opens server '
      'setup', (tester) async {
    await pumpApp(tester);

    for (var i = 1; i < welcomePages.length; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(onboardingStorage.seen, isTrue);
    expect(find.text('Connect to your Trek server'), findsOneWidget);
  });

  testWidgets('Skip records the welcome as seen and opens server setup', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(onboardingStorage.seen, isTrue);
    expect(find.text('Connect to your Trek server'), findsOneWidget);
  });
}
