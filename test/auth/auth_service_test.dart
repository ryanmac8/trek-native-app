import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/auth/session_token.dart';
import 'package:trek/auth/token_storage.dart';
import 'package:trek/network/api_client.dart';

import '../test_helpers.dart';

/// Simple in-memory [TokenStorage] fake — no platform channel involved, so
/// tests can focus purely on [AuthService]'s orchestration logic.
class _InMemoryTokenStorage implements TokenStorage {
  SessionToken? _token;

  @override
  Future<SessionToken?> read() async => _token;

  @override
  Future<void> write(SessionToken token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

http.Response _json(Map<String, dynamic> body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

String _futureJwt() => fakeJwt({
  'id': 1,
  'exp':
      DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch ~/
      1000,
});

String _expiredJwt() => fakeJwt({
  'id': 1,
  'exp':
      DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch ~/
      1000,
});

void main() {
  late _InMemoryTokenStorage storage;

  setUp(() {
    storage = _InMemoryTokenStorage();
  });

  group('AuthService.login', () {
    test(
      'posts to /api/auth/login, stores the token, and marks the session active',
      () async {
        final jwt = _futureJwt();
        final client = ApiClient(
          baseUrl: 'https://trek.example.com',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/auth/login');
            expect(jsonDecode(request.body), {
              'email': 'a@trek.app',
              'password': 'hunter2',
              'remember_me': false,
            });
            return _json({
              'token': jwt,
              'user': {'id': 1, 'email': 'a@trek.app'},
            });
          }),
        );
        final auth = AuthService(apiClient: client, tokenStorage: storage);

        final result = await auth.login(
          email: 'a@trek.app',
          password: 'hunter2',
        );

        expect(result, isA<LoggedIn>());
        expect((result as LoggedIn).token.token, jwt);
        expect(auth.isAuthenticated.value, isTrue);
        expect((await storage.read())?.token, jwt);
      },
    );

    test(
      'returns MfaRequired without storing a session when the account has MFA enabled',
      () async {
        final client = ApiClient(
          baseUrl: 'https://trek.example.com',
          httpClient: MockClient((request) async {
            return _json({
              'mfa_required': true,
              'mfa_token': 'short-lived-token',
            });
          }),
        );
        final auth = AuthService(apiClient: client, tokenStorage: storage);

        final result = await auth.login(
          email: 'a@trek.app',
          password: 'hunter2',
        );

        expect(result, isA<MfaRequired>());
        expect((result as MfaRequired).mfaToken, 'short-lived-token');
        expect(auth.isAuthenticated.value, isFalse);
        expect(await storage.read(), isNull);
      },
    );
  });

  group('AuthService.verifyMfaLogin', () {
    test('posts the mfa token + code and completes the session', () async {
      final jwt = _futureJwt();
      final client = ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/auth/mfa/verify-login');
          expect(jsonDecode(request.body), {
            'mfa_token': 'short-lived-token',
            'code': '123456',
            'remember_me': false,
          });
          return _json({
            'token': jwt,
            'user': {'id': 1},
          });
        }),
      );
      final auth = AuthService(apiClient: client, tokenStorage: storage);

      final token = await auth.verifyMfaLogin(
        mfaToken: 'short-lived-token',
        code: '123456',
      );

      expect(token.token, jwt);
      expect(auth.isAuthenticated.value, isTrue);
    });
  });

  group('AuthService.logout', () {
    test('clears the session even if the server call fails', () async {
      await storage.write(
        SessionToken(token: _futureJwt(), expiresAt: DateTime.utc(2030)),
      );
      final client = ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient(
          (request) async => _json({'error': 'down'}, 500),
        ),
      );
      final auth = AuthService(apiClient: client, tokenStorage: storage);
      auth.isAuthenticated.value = true;

      await auth.logout();

      expect(auth.isAuthenticated.value, isFalse);
      expect(await storage.read(), isNull);
    });
  });

  group('AuthService.restoreSession', () {
    test(
      'sets isAuthenticated true when a non-expired token is already stored',
      () async {
        await storage.write(
          SessionToken(token: _futureJwt(), expiresAt: DateTime.utc(2030)),
        );
        final auth = AuthService(
          apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
          tokenStorage: storage,
        );

        await auth.restoreSession();

        expect(auth.isAuthenticated.value, isTrue);
      },
    );

    test('sets isAuthenticated false when no token is stored', () async {
      final auth = AuthService(
        apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
        tokenStorage: storage,
      );

      await auth.restoreSession();

      expect(auth.isAuthenticated.value, isFalse);
    });
  });

  group('AuthService.currentAccessToken', () {
    test('returns the stored token when it has not expired', () async {
      final jwt = _futureJwt();
      await storage.write(
        SessionToken(token: jwt, expiresAt: DateTime.utc(2030)),
      );
      final auth = AuthService(
        apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
        tokenStorage: storage,
      );

      expect(await auth.currentAccessToken, jwt);
    });

    test(
      'clears the session and returns null when the stored token has expired',
      () async {
        await storage.write(
          SessionToken(
            token: _expiredJwt(),
            expiresAt: DateTime.now().toUtc().subtract(
              const Duration(minutes: 1),
            ),
          ),
        );
        final auth = AuthService(
          apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
          tokenStorage: storage,
        );

        expect(await auth.currentAccessToken, isNull);
        expect(auth.isAuthenticated.value, isFalse);
        expect(await storage.read(), isNull);
      },
    );
  });

  group('AuthService.handleUnauthorized', () {
    test('flags needsReconnect without signing the user out or clearing the '
        'stored token, and never asks the caller to retry', () async {
      final token = SessionToken(
        token: _futureJwt(),
        expiresAt: DateTime.utc(2030),
      );
      await storage.write(token);
      final auth = AuthService(
        apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
        tokenStorage: storage,
      );
      auth.isAuthenticated.value = true;

      final shouldRetry = await auth.handleUnauthorized();

      expect(shouldRetry, isFalse);
      // Offline-first: a rejected token degrades to "can't sync," not
      // "logged out" — the app must stay usable.
      expect(auth.isAuthenticated.value, isTrue);
      expect(auth.needsReconnect.value, isTrue);
      expect((await storage.read())?.token, token.token);
    });
  });

  group('AuthService.needsReconnect', () {
    test('a fresh login clears a previously-set needsReconnect flag', () async {
      final jwt = _futureJwt();
      final client = ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient(
          (request) async => _json({
            'token': jwt,
            'user': {'id': 1},
          }),
        ),
      );
      final auth = AuthService(apiClient: client, tokenStorage: storage);
      auth.needsReconnect.value = true;

      await auth.login(email: 'a@trek.app', password: 'hunter2');

      expect(auth.needsReconnect.value, isFalse);
    });
  });
}
