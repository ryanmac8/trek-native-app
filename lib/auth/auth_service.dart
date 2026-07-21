import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import 'auth_tokens.dart';
import 'token_storage.dart';

/// Owns the login/logout/refresh flow against Trek's auth endpoints and
/// persists the resulting tokens via [TokenStorage].
///
/// [apiClient] should be an unauthenticated [ApiClient] (no bearer token
/// injected), since these endpoints are called before a session exists or to
/// establish a new one. Wiring [currentAccessToken] as the app's main
/// [ApiClient]'s `getAccessToken` and [refreshTokens] as its
/// `onUnauthorized` is part of the app-shell composition tracked in issue #2.
class AuthService {
  AuthService({required ApiClient apiClient, required TokenStorage tokenStorage})
      : _apiClient = apiClient,
        _tokenStorage = tokenStorage;

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  /// Whether a session is currently active. Updated after every
  /// login/logout/refresh so UI can listen and react (e.g. redirect to the
  /// login screen).
  final ValueNotifier<bool> isAuthenticated = ValueNotifier(false);

  /// Restores session state from storage; call once at app startup.
  Future<void> restoreSession() async {
    final tokens = await _tokenStorage.read();
    isAuthenticated.value = tokens != null;
  }

  Future<AuthTokens> login({required String email, required String password}) async {
    final response = await _apiClient.post(
      '/auth/login',
      body: {'email': email, 'password': password},
    );
    final tokens = AuthTokens.fromJson(response as Map<String, dynamic>);
    await _tokenStorage.write(tokens);
    isAuthenticated.value = true;
    return tokens;
  }

  Future<void> logout() async {
    try {
      await _apiClient.post('/auth/logout');
    } on Exception {
      // Best-effort: the session is cleared locally regardless of whether
      // the server-side revoke succeeds.
    } finally {
      await _tokenStorage.clear();
      isAuthenticated.value = false;
    }
  }

  /// Attempts to exchange the stored refresh token for a new token pair.
  /// Returns `null` (and clears the session) if there is no refresh token or
  /// the exchange is rejected.
  Future<AuthTokens?> refreshTokens() async {
    final current = await _tokenStorage.read();
    if (current == null) {
      isAuthenticated.value = false;
      return null;
    }

    try {
      final response = await _apiClient.post(
        '/auth/refresh',
        body: {'refreshToken': current.refreshToken},
      );
      final tokens = AuthTokens.fromJson(response as Map<String, dynamic>);
      await _tokenStorage.write(tokens);
      isAuthenticated.value = true;
      return tokens;
    } on Exception {
      await _tokenStorage.clear();
      isAuthenticated.value = false;
      return null;
    }
  }

  /// The current access token, transparently refreshing it first if expired.
  /// Returns `null` if there is no session or the refresh fails.
  Future<String?> get currentAccessToken async {
    final tokens = await _tokenStorage.read();
    if (tokens == null) return null;
    if (tokens.isExpired) {
      final refreshed = await refreshTokens();
      return refreshed?.accessToken;
    }
    return tokens.accessToken;
  }
}
