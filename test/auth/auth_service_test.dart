import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/auth/auth_service.dart';
import 'package:trek/auth/local_data.dart';
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
    test('clears the session and never asks the caller to retry', () async {
      await storage.write(
        SessionToken(token: _futureJwt(), expiresAt: DateTime.utc(2030)),
      );
      final auth = AuthService(
        apiClient: ApiClient(baseUrl: 'https://trek.example.com'),
        tokenStorage: storage,
      );
      auth.isAuthenticated.value = true;

      final shouldRetry = await auth.handleUnauthorized();

      expect(shouldRetry, isFalse);
      expect(auth.isAuthenticated.value, isFalse);
      expect(await storage.read(), isNull);
    });
  });

  group('AuthService local data', () {
    const server = 'https://trek.example.com';
    const owner1 = LocalDataOwner(serverUrl: server, userId: 1);

    String jwtFor(int userId) => fakeJwt({
      'id': userId,
      'exp':
          DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch ~/
          1000,
    });

    late FakeAccountScopedData cache;
    late InMemoryLocalDataOwnerStorage owners;
    late String serverUrl;

    setUp(() {
      cache = FakeAccountScopedData(name: 'trips');
      owners = InMemoryLocalDataOwnerStorage();
      serverUrl = server;
    });

    AuthService buildAuth(MockClientHandler handler) => AuthService(
      apiClient: ApiClient(baseUrl: server, httpClient: MockClient(handler)),
      tokenStorage: storage,
      localData: LocalDataRegistry()..register(cache),
      ownerStorage: owners,
      getServerUrl: () async => serverUrl,
    );

    AuthService loginAs(int userId) =>
        buildAuth((request) async => _json({'token': jwtFor(userId)}));

    test('keeps local data when the same account signs back in', () async {
      owners.owner = owner1;

      await loginAs(1).login(email: 'a@trek.app', password: 'pw');

      expect(cache.wasCleared, isFalse);
      expect(owners.owner, owner1);
    });

    test('clears local data when a different user signs in', () async {
      owners.owner = owner1;

      await loginAs(2).login(email: 'b@trek.app', password: 'pw');

      expect(cache.wasCleared, isTrue);
      expect(owners.owner, const LocalDataOwner(serverUrl: server, userId: 2));
    });

    test('clears local data when the same user id signs in on another '
        'server', () async {
      owners.owner = owner1;
      serverUrl = 'https://other.example.com';

      await loginAs(1).login(email: 'a@trek.app', password: 'pw');

      expect(cache.wasCleared, isTrue);
      expect(owners.owner?.serverUrl, 'https://other.example.com');
    });

    test('clears local data when no previous owner is recorded', () async {
      await loginAs(1).login(email: 'a@trek.app', password: 'pw');

      expect(cache.wasCleared, isTrue);
      expect(owners.owner, owner1);
    });

    test('clears local data when the token has no user id', () async {
      owners.owner = owner1;
      final auth = buildAuth(
        (request) async => _json({
          'token': fakeJwt({
            'exp':
                DateTime.now()
                    .toUtc()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
        }),
      );

      await auth.login(email: 'a@trek.app', password: 'pw');

      expect(cache.wasCleared, isTrue);
      expect(owners.owner, isNull);
      expect(auth.isAuthenticated.value, isTrue);
    });

    test('applies the same account check after MFA verification', () async {
      owners.owner = owner1;

      await loginAs(2).verifyMfaLogin(mfaToken: 'mfa', code: '123456');

      expect(cache.wasCleared, isTrue);
      expect(owners.owner?.userId, 2);
    });

    test('still signs in, clearing data, when owner storage fails', () async {
      final auth = AuthService(
        apiClient: ApiClient(
          baseUrl: server,
          httpClient: MockClient(
            (request) async => _json({'token': jwtFor(1)}),
          ),
        ),
        tokenStorage: storage,
        localData: LocalDataRegistry()..register(cache),
        ownerStorage: _ThrowingOwnerStorage(),
        getServerUrl: () async => server,
      );

      await auth.login(email: 'a@trek.app', password: 'pw');

      expect(cache.wasCleared, isTrue);
      expect(auth.isAuthenticated.value, isTrue);
    });

    test('logout clears local data and the recorded owner', () async {
      owners.owner = owner1;
      final auth = buildAuth((request) async => _json({'success': true}));
      auth.isAuthenticated.value = true;

      await auth.logout();

      expect(cache.wasCleared, isTrue);
      expect(owners.owner, isNull);
      expect(auth.isAuthenticated.value, isFalse);
    });

    test('logout clears local data while offline', () async {
      owners.owner = owner1;
      await storage.write(
        SessionToken(token: jwtFor(1), expiresAt: DateTime.utc(2030)),
      );
      final auth = buildAuth(
        (request) async => throw const SocketException('no route to host'),
      );
      auth.isAuthenticated.value = true;

      await auth.logout();

      expect(cache.wasCleared, isTrue);
      expect(owners.owner, isNull);
      expect(await storage.read(), isNull);
      expect(auth.isAuthenticated.value, isFalse);
    });

    test('logout completes even if a store fails to clear', () async {
      final broken = FakeAccountScopedData(name: 'broken', failOnClear: true);
      final auth = buildAuth((request) async => _json({'success': true}));
      auth.localData.register(broken);
      auth.isAuthenticated.value = true;

      await auth.logout();

      expect(cache.wasCleared, isTrue);
      expect(auth.isAuthenticated.value, isFalse);
    });

    test('a 401 keeps local data for the same account', () async {
      owners.owner = owner1;
      final auth = buildAuth((request) async => _json({}));
      auth.isAuthenticated.value = true;

      await auth.handleUnauthorized();

      expect(cache.wasCleared, isFalse);
      expect(owners.owner, owner1);
    });
  });
}

class _ThrowingOwnerStorage implements LocalDataOwnerStorage {
  @override
  Future<LocalDataOwner?> read() async => throw StateError('read failed');

  @override
  Future<void> write(LocalDataOwner owner) async =>
      throw StateError('write failed');

  @override
  Future<void> clear() async => throw StateError('clear failed');
}
