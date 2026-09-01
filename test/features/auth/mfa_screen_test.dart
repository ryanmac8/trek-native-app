import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/config/server_config.dart';
import 'package:trek/network/api_client.dart';

import '../../test_helpers.dart';

http.Response _json(Map<String, dynamic> body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  testWidgets('completing the MFA code logs in and reaches the trip list', (
    tester,
  ) async {
    final jwt = fakeJwt({
      'id': 1,
      'exp':
          DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch ~/
          1000,
    });
    final authService = AuthService(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/auth/login') {
            return _json({'mfa_required': true, 'mfa_token': 'short-lived'});
          }
          expect(request.url.path, '/api/auth/mfa/verify-login');
          expect(jsonDecode(request.body)['mfa_token'], 'short-lived');
          expect(jsonDecode(request.body)['code'], '123456');
          return _json({
            'token': jwt,
            'user': {'id': 1},
          });
        }),
      ),
      tokenStorage: InMemoryTokenStorage(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(authService),
          serverConfigStorageProvider.overrideWithValue(
            InMemoryServerConfigStorage(
              initial: const ServerConfig(
                publicUrl: 'https://trek.example.com',
              ),
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

    await tester.enterText(find.byType(TextFormField).first, 'a@trek.app');
    await tester.enterText(find.byType(TextFormField).last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Two-factor authentication'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
    await tester.pumpAndSettle();

    expect(find.text('Trips'), findsOneWidget);
    expect(authService.isAuthenticated.value, isTrue);
  });
}
