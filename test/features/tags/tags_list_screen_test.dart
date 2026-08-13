import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

Future<void> _pumpTagsList(
  WidgetTester tester, {
  required AuthService authService,
  required http.Client tagsHttpClient,
  InMemoryTagsLocalStore? localStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        apiClientProvider.overrideWithValue(
          ApiClient(
            baseUrl: 'https://trek.example.com',
            httpClient: tagsHttpClient,
            getAccessToken: () => authService.currentAccessToken,
            onUnauthorized: authService.handleUnauthorized,
          ),
        ),
        serverConfigStorageProvider.overrideWithValue(
          InMemoryServerConfigStorage(
            initial: const ServerConfig(publicUrl: 'https://trek.example.com'),
          ),
        ),
        tagsLocalStoreProvider.overrideWithValue(
          localStore ?? InMemoryTagsLocalStore(),
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

void main() {
  testWidgets('shows an empty state when there are no tags', (tester) async {
    await _pumpTagsList(
      tester,
      authService: _authenticatedAuthService(),
      tagsHttpClient: MockClient((request) async {
        expect(request.url.path, '/api/tags');
        return _json({'tags': []});
      }),
    );
    await _navigateToTags(tester);

    expect(find.text('No tags yet.'), findsOneWidget);
  });

  testWidgets('renders tags fetched from the real API shape', (tester) async {
    await _pumpTagsList(
      tester,
      authService: _authenticatedAuthService(),
      tagsHttpClient: MockClient(
        (request) async => _json({
          'tags': [
            {'id': 1, 'user_id': 1, 'name': 'Foodie', 'color': '#ef4444'},
          ],
        }),
      ),
    );
    await _navigateToTags(tester);

    expect(find.text('Foodie'), findsOneWidget);
  });

  testWidgets('creating a tag adds it to the list immediately', (tester) async {
    await _pumpTagsList(
      tester,
      authService: _authenticatedAuthService(),
      tagsHttpClient: MockClient((request) async {
        if (request.method == 'POST') {
          return _json({
            'tag': {
              'id': 9,
              'user_id': 1,
              'name': 'Splurge',
              'color': '#10b981',
            },
          }, 201);
        }
        return _json({'tags': []});
      }),
    );
    await _navigateToTags(tester);
    expect(find.text('No tags yet.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Splurge');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Splurge'), findsOneWidget);
  });

  testWidgets(
    'a tag created while offline shows as syncing and stays in the list',
    (tester) async {
      await _pumpTagsList(
        tester,
        authService: _authenticatedAuthService(),
        tagsHttpClient: MockClient((request) async {
          if (request.method == 'POST') {
            throw http.ClientException('Connection refused');
          }
          return _json({'tags': []});
        }),
      );
      await _navigateToTags(tester);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Offline tag');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Offline tag'), findsOneWidget);
      expect(find.text('Syncing…'), findsOneWidget);
    },
  );
}

/// The router's initial location is `/trips`, not `/tags` — navigate there
/// directly the same way `CreateTripScreen`/`TripDashboardScreen` are
/// reached today, since there's no nav entry point to tags yet.
///
/// [GoRouter.of] needs a context *below* the router in the tree (e.g. a
/// routed page's own widgets), not [MaterialApp] itself, which sits above
/// it — [Scaffold] is the first one every route in this app renders.
Future<void> _navigateToTags(WidgetTester tester) async {
  final element = tester.element(find.byType(Scaffold).first);
  GoRouter.of(element).go('/tags');
  await tester.pumpAndSettle();
}
