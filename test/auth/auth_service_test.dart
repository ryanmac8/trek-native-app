import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/auth/auth_tokens.dart';
import 'package:trek/auth/token_storage.dart';
import 'package:trek/network/api_client.dart';

/// Simple in-memory [TokenStorage] fake — no platform channel involved, so
/// tests can focus purely on [AuthService]'s orchestration logic.
class _InMemoryTokenStorage implements TokenStorage {
  AuthTokens? _tokens;

  @override
  Future<AuthTokens?> read() async => _tokens;

  @override
  Future<void> write(AuthTokens tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}

http.Response _json(Map<String, dynamic> body, [int statusCode = 200]) {
  return http.Response(jsonEncode(body), statusCode, headers: {
    'content-type': 'application/json',
  });
}

void main() {
  late _InMemoryTokenStorage storage;

  setUp(() {
    storage = _InMemoryTokenStorage();
  });

  group('AuthService.login', () {
    test('posts credentials, stores tokens, and marks the session active', () async {
      final client = ApiClient(
        baseUrl: 'https://api.trek.app',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/login');
          expect(jsonDecode(request.body), {'email': 'a@trek.app', 'password': 'hunter2'});
          return _json({'accessToken': 'access-1', 'refreshToken': 'refresh-1', 'expiresIn': 3600});
        }),
      );
      final auth = AuthService(apiClient: client, tokenStorage: storage);

      final tokens = await auth.login(email: 'a@trek.app', password: 'hunter2');

      expect(tokens.accessToken, 'access-1');
      expect(auth.isAuthenticated.value, isTrue);
      expect((await storage.read())?.accessToken, 'access-1');
    });
  });

  group('AuthService.logout', () {
    test('clears the session even if the server call fails', () async {
      await storage.write(
        AuthTokens(accessToken: 'a', refreshToken: 'r', expiresAt: DateTime.utc(2030)),
      );
      final client = ApiClient(
        baseUrl: 'https://api.trek.app',
        httpClient: MockClient((request) async => _json({'message': 'down'}, 500)),
      );
      final auth = AuthService(apiClient: client, tokenStorage: storage);
      auth.isAuthenticated.value = true;

      await auth.logout();

      expect(auth.isAuthenticated.value, isFalse);
      expect(await storage.read(), isNull);
    });
  });

  group('AuthService.restoreSession', () {
    test('sets isAuthenticated true when tokens are already stored', () async {
      await storage.write(
        AuthTokens(accessToken: 'a', refreshToken: 'r', expiresAt: DateTime.utc(2030)),
      );
      final auth = AuthService(
        apiClient: ApiClient(baseUrl: 'https://api.trek.app'),
        tokenStorage: storage,
      );

      await auth.restoreSession();

      expect(auth.isAuthenticated.value, isTrue);
    });

    test('sets isAuthenticated false when no tokens are stored', () async {
      final auth = AuthService(
        apiClient: ApiClient(baseUrl: 'https://api.trek.app'),
        tokenStorage: storage,
      );

      await auth.restoreSession();

      expect(auth.isAuthenticated.value, isFalse);
    });
  });

  group('AuthService.currentAccessToken', () {
    test('returns the stored token when it has not expired', () async {
      await storage.write(
        AuthTokens(
          accessToken: 'still-valid',
          refreshToken: 'r',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );
      final auth = AuthService(
        apiClient: ApiClient(baseUrl: 'https://api.trek.app'),
        tokenStorage: storage,
      );

      expect(await auth.currentAccessToken, 'still-valid');
    });

    test('transparently refreshes an expired token', () async {
      await storage.write(
        AuthTokens(
          accessToken: 'expired',
          refreshToken: 'refresh-1',
          expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        ),
      );
      final client = ApiClient(
        baseUrl: 'https://api.trek.app',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/refresh');
          expect(jsonDecode(request.body), {'refreshToken': 'refresh-1'});
          return _json({'accessToken': 'fresh', 'refreshToken': 'refresh-2', 'expiresIn': 3600});
        }),
      );
      final auth = AuthService(apiClient: client, tokenStorage: storage);

      expect(await auth.currentAccessToken, 'fresh');
      expect((await storage.read())?.refreshToken, 'refresh-2');
    });
  });

  group('AuthService.refreshTokens', () {
    test('returns null and clears the session when there is nothing to refresh', () async {
      final auth = AuthService(
        apiClient: ApiClient(baseUrl: 'https://api.trek.app'),
        tokenStorage: storage,
      );

      expect(await auth.refreshTokens(), isNull);
      expect(auth.isAuthenticated.value, isFalse);
    });

    test('clears the session when the refresh call is rejected', () async {
      await storage.write(
        AuthTokens(accessToken: 'a', refreshToken: 'stale', expiresAt: DateTime.utc(2020)),
      );
      final client = ApiClient(
        baseUrl: 'https://api.trek.app',
        httpClient: MockClient((request) async => _json({'message': 'invalid'}, 401)),
      );
      final auth = AuthService(apiClient: client, tokenStorage: storage);

      expect(await auth.refreshTokens(), isNull);
      expect(auth.isAuthenticated.value, isFalse);
      expect(await storage.read(), isNull);
    });
  });
}
