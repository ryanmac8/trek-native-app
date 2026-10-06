import 'dart:convert';

import 'package:trek/auth/local_data.dart';
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

/// In-memory [AccountScopedData] that records whether it was cleared, with
/// an adjustable unsynced-change count and an optional failing [clear].
class FakeAccountScopedData extends AccountScopedData {
  FakeAccountScopedData({
    this.name = 'fake store',
    this.unsynced = 0,
    this.failOnClear = false,
  });

  @override
  final String name;
  int unsynced;
  bool failOnClear;
  int clearCount = 0;

  bool get wasCleared => clearCount > 0;

  @override
  Future<void> clear() async {
    if (failOnClear) throw StateError('simulated clear failure');
    clearCount++;
    unsynced = 0;
  }

  @override
  Future<int> unsyncedChangeCount() async => unsynced;
}

/// In-memory [LocalDataOwnerStorage] fake — avoids `shared_preferences`.
class InMemoryLocalDataOwnerStorage implements LocalDataOwnerStorage {
  InMemoryLocalDataOwnerStorage({LocalDataOwner? initial}) : owner = initial;

  LocalDataOwner? owner;

  @override
  Future<LocalDataOwner?> read() async => owner;

  @override
  Future<void> write(LocalDataOwner owner) async => this.owner = owner;

  @override
  Future<void> clear() async => owner = null;
}
