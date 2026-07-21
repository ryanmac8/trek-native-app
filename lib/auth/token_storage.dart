import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_tokens.dart';

/// Persists [AuthTokens] between app launches. Implementations must not
/// store tokens in plaintext, unencrypted locations.
abstract class TokenStorage {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
}

/// Stores tokens in the platform's secure storage (iOS Keychain / Android
/// Keystore via `flutter_secure_storage`), so they survive app restarts but
/// are inaccessible outside the app sandbox.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokensKey = 'trek.auth.tokens';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthTokens?> read() async {
    final raw = await _storage.read(key: _tokensKey);
    if (raw == null) return null;
    return AuthTokens.fromStorageJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> write(AuthTokens tokens) {
    return _storage.write(key: _tokensKey, value: jsonEncode(tokens.toStorageJson()));
  }

  @override
  Future<void> clear() {
    return _storage.delete(key: _tokensKey);
  }
}
