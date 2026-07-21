import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/app/trek_app.dart';
import 'package:trek/auth/auth_service.dart';
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
        ],
        child: const TrekApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect to your Trek server'), findsOneWidget);
  });
}
