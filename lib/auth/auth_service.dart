import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import 'session_token.dart';
import 'token_storage.dart';

/// The outcome of [AuthService.login]: either a completed session, or a
/// signal that the account has TOTP MFA enabled and a follow-up call to
/// [AuthService.verifyMfaLogin] is required to finish signing in.
sealed class LoginResult {
  const LoginResult();
}

class LoggedIn extends LoginResult {
  const LoggedIn(this.token);
  final SessionToken token;
}

class MfaRequired extends LoginResult {
  const MfaRequired(this.mfaToken);

  /// Short-lived (5 minute) token to pass to [AuthService.verifyMfaLogin]
  /// along with the user's TOTP code.
  final String mfaToken;
}

/// Owns Trek's login/MFA/logout flow and persists the resulting session via
/// [TokenStorage].
///
/// Trek issues a single JWT per session (returned as `token`, and also set
/// as an httpOnly cookie for the web PWA) — there is no refresh-token
/// exchange for password logins, so once the JWT's `exp` claim passes the
/// user must log in again. [apiClient] should be an unauthenticated
/// [ApiClient] (no bearer token injected), since login/logout happen before
/// or independent of an existing session.
class AuthService {
  AuthService({required ApiClient apiClient, required TokenStorage tokenStorage})
      : _apiClient = apiClient,
        _tokenStorage = tokenStorage;

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  /// Whether a non-expired session is currently stored. Updated after every
  /// login/logout/expiry check so UI can listen and react (e.g. redirect to
  /// the login screen).
  final ValueNotifier<bool> isAuthenticated = ValueNotifier(false);

  /// Restores session state from storage; call once at app startup.
  Future<void> restoreSession() async {
    final token = await currentAccessToken;
    isAuthenticated.value = token != null;
  }

  Future<LoginResult> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    final response = await _apiClient.post('/api/auth/login', body: {
      'email': email,
      'password': password,
      'remember_me': rememberMe,
    }) as Map<String, dynamic>;

    if (response['mfa_required'] == true) {
      return MfaRequired(response['mfa_token'] as String);
    }

    final token = SessionToken.fromJwt(response['token'] as String);
    await _tokenStorage.write(token);
    isAuthenticated.value = true;
    return LoggedIn(token);
  }

  /// Completes a login that returned [MfaRequired], exchanging the
  /// short-lived `mfaToken` plus the user's current TOTP `code` for a full
  /// session token.
  Future<SessionToken> verifyMfaLogin({
    required String mfaToken,
    required String code,
    bool rememberMe = false,
  }) async {
    final response = await _apiClient.post('/api/auth/mfa/verify-login', body: {
      'mfa_token': mfaToken,
      'code': code,
      'remember_me': rememberMe,
    }) as Map<String, dynamic>;

    final token = SessionToken.fromJwt(response['token'] as String);
    await _tokenStorage.write(token);
    isAuthenticated.value = true;
    return token;
  }

  Future<void> logout() async {
    try {
      await _apiClient.post('/api/auth/logout');
    } on Exception {
      // Best-effort: the local session is cleared regardless of whether the
      // server-side cookie clear succeeds.
    } finally {
      await _tokenStorage.clear();
      isAuthenticated.value = false;
    }
  }

  /// The current session token, or `null` if there is no session or it has
  /// expired. Trek has no refresh flow for password logins, so an expired
  /// token means the stored session is cleared and the user must log in
  /// again — it is not silently renewed.
  Future<String?> get currentAccessToken async {
    final token = await _tokenStorage.read();
    if (token == null) return null;
    if (token.isExpired) {
      await _tokenStorage.clear();
      isAuthenticated.value = false;
      return null;
    }
    return token.token;
  }

  /// Wire this into an authenticated [ApiClient]'s `onUnauthorized` callback.
  /// A 401 from Trek (e.g. the token's `password_version` was invalidated by
  /// a password change on another device) means the session is dead — there
  /// is nothing to refresh, so this always clears local state and returns
  /// `false` (never retry).
  Future<bool> handleUnauthorized() async {
    await _tokenStorage.clear();
    isAuthenticated.value = false;
    return false;
  }
}
