import 'dart:convert';

import 'package:trek/account/account_local_store.dart';
import 'package:trek/account/account_models.dart';
import 'package:trek/auth/session_token.dart';
import 'package:trek/auth/token_storage.dart';
import 'package:trek/config/server_config.dart';

/// Builds a syntactically-valid, unsigned JWT string for tests — Trek's
/// backend is the only thing that verifies the signature; the client only
/// ever reads claims out of the payload.
String fakeJwt(Map<String, dynamic> payload) {
  String encodeSegment(Object part) =>
      base64Url.encode(utf8.encode(jsonEncode(part))).replaceAll('=', '');

  final header = encodeSegment({'alg': 'HS256', 'typ': 'JWT'});
  final body = encodeSegment(payload);
  return '$header.$body.signature';
}

/// In-memory [TokenStorage] fake — no platform channel involved, for tests
/// that need a real (non-mocked) `AuthService` wired to a widget tree.
class InMemoryTokenStorage implements TokenStorage {
  SessionToken? _token;

  @override
  Future<SessionToken?> read() async => _token;

  @override
  Future<void> write(SessionToken token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

/// [TokenStorage] fake that always throws on read — simulates
/// `flutter_secure_storage` failing (e.g. Keychain access after a backup
/// restore, Keystore invalidated by a biometric/lock-screen change).
class ThrowingTokenStorage implements TokenStorage {
  @override
  Future<SessionToken?> read() async {
    throw StateError('simulated secure storage failure');
  }

  @override
  Future<void> write(SessionToken token) async {}

  @override
  Future<void> clear() async {}
}

/// In-memory [ServerConfigStorage] fake — avoids the `shared_preferences`
/// platform channel in widget tests.
class InMemoryServerConfigStorage implements ServerConfigStorage {
  InMemoryServerConfigStorage({ServerConfig? initial}) : _config = initial;

  ServerConfig? _config;

  @override
  Future<ServerConfig?> read() async => _config;

  @override
  Future<void> write(ServerConfig config) async => _config = config;

  @override
  Future<void> clear() async => _config = null;
}

/// In-memory [AccountLocalStore] fake — avoids the `shared_preferences`
/// platform channel in repository/widget tests. A `null` read means
/// "nothing cached" (never fetched, or cleared on sign-out).
class InMemoryAccountLocalStore implements AccountLocalStore {
  InMemoryAccountLocalStore({TrekAccount? initial}) : account = initial;

  TrekAccount? account;

  @override
  Future<TrekAccount?> read() async => account;

  @override
  Future<void> write(TrekAccount account) async => this.account = account;

  @override
  Future<void> clear() async => account = null;
}

/// A representative `GET /api/auth/me` response body for tests.
Map<String, dynamic> fakeMeResponse({
  int id = 1,
  String username = 'ada',
  String email = 'ada@example.com',
  String role = 'user',
  bool mfaEnabled = false,
  String? oidcIssuer,
  String? createdAt = '2025-01-02T03:04:05.000Z',
}) {
  return {
    'user': {
      'id': id,
      'username': username,
      'email': email,
      'role': role,
      'avatar_url': 'https://trek.example.com/avatars/$id.png',
      'oidc_issuer': oidcIssuer,
      'created_at': createdAt,
      'mfa_enabled': mfaEnabled,
      'must_change_password': false,
    },
  };
}
