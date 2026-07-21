import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/app/sync_status_shell.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/network/api_client.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('hides the banner when needsReconnect is false', (tester) async {
    final authService = AuthService(
      apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
      tokenStorage: InMemoryTokenStorage(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SyncStatusShell(
          authService: authService,
          child: const Text('Screen content'),
        ),
      ),
    );

    expect(find.text('Screen content'), findsOneWidget);
    expect(find.textContaining("Can't sync"), findsNothing);
  });

  testWidgets(
    'shows the banner when needsReconnect is true, without hiding the child',
    (tester) async {
      final authService = AuthService(
        apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
        tokenStorage: InMemoryTokenStorage(),
      );
      authService.needsReconnect.value = true;

      await tester.pumpWidget(
        MaterialApp(
          home: SyncStatusShell(
            authService: authService,
            child: const Text('Screen content'),
          ),
        ),
      );

      expect(find.text('Screen content'), findsOneWidget);
      expect(find.textContaining("Can't sync"), findsOneWidget);
    },
  );

  testWidgets('the banner reacts live to needsReconnect changing', (
    tester,
  ) async {
    final authService = AuthService(
      apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
      tokenStorage: InMemoryTokenStorage(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SyncStatusShell(
          authService: authService,
          child: const Text('Screen content'),
        ),
      ),
    );
    expect(find.textContaining("Can't sync"), findsNothing);

    authService.needsReconnect.value = true;
    await tester.pump();
    expect(find.textContaining("Can't sync"), findsOneWidget);

    authService.needsReconnect.value = false;
    await tester.pump();
    expect(find.textContaining("Can't sync"), findsNothing);
  });
}
