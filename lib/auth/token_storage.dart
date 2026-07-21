import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session_token.dart';

/// Persists a [SessionToken] between app launches. Implementations must not
/// store it in plaintext, unencrypted locations.
abstract class TokenStorage {
  Future<SessionToken?> read();
  Future<void> write(SessionToken token);
  Future<void> clear();
}

/// Stores the session token in the platform's secure storage (iOS Keychain /
/// Android Keystore via `flutter_secure_storage`), so it survives app
/// restarts but is inaccessible outside the app sandbox.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'trek.auth.session_token';

  final FlutterSecureStorage _storage;

  @override
  Future<SessionToken?> read() async {
    final raw = await _storage.read(key: _tokenKey);
    if (raw == null) return null;
    return SessionToken.fromStorageJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> write(SessionToken token) {
    return _storage.write(key: _tokenKey, value: jsonEncode(token.toStorageJson()));
  }

  @override
  Future<void> clear() {
    return _storage.delete(key: _tokenKey);
  }
}
