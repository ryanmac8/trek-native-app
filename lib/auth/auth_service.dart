import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import 'local_data.dart';
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
///
/// Account-scoped local data registered in [localData] is cleared on
/// [logout], and on login when the signing-in account (server public URL
/// from [getServerUrl] + JWT user id) differs from the one recorded in
/// [ownerStorage]. A dead session (expiry, 401) keeps local data, so the
/// same account signing back in still has its offline cache.
class AuthService {
  AuthService({
    required ApiClient apiClient,
    required TokenStorage tokenStorage,
    LocalDataRegistry? localData,
    LocalDataOwnerStorage? ownerStorage,
    Future<String?> Function()? getServerUrl,
  }) : _apiClient = apiClient,
       _tokenStorage = tokenStorage,
       localData = localData ?? LocalDataRegistry(),
       _ownerStorage = ownerStorage,
       _getServerUrl = getServerUrl;

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;
  final LocalDataOwnerStorage? _ownerStorage;
  final Future<String?> Function()? _getServerUrl;

  /// Account-scoped stores cleared on logout and account switch.
  final LocalDataRegistry localData;

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
    final response =
        await _apiClient.post(
              '/api/auth/login',
              body: {
                'email': email,
                'password': password,
                'remember_me': rememberMe,
              },
            )
            as Map<String, dynamic>;

    if (response['mfa_required'] == true) {
      return MfaRequired(response['mfa_token'] as String);
    }

    final token = SessionToken.fromJwt(response['token'] as String);
    await _startSession(token);
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
    final response =
        await _apiClient.post(
              '/api/auth/mfa/verify-login',
              body: {
                'mfa_token': mfaToken,
                'code': code,
                'remember_me': rememberMe,
              },
            )
            as Map<String, dynamic>;

    final token = SessionToken.fromJwt(response['token'] as String);
    await _startSession(token);
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
      await localData.clearAll();
      await _clearOwner();
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
  /// is nothing to refresh, so this always clears the stored session and
  /// returns `false` (never retry). Account-scoped local data is kept for
  /// when the same account signs back in.
  Future<bool> handleUnauthorized() async {
    await _tokenStorage.clear();
    isAuthenticated.value = false;
    return false;
  }

  /// Persists [token] as the active session, first clearing account-scoped
  /// local data unless it is known to belong to this same account — so a
  /// different account never sees the previous one's cached data.
  Future<void> _startSession(SessionToken token) async {
    final owner = await _ownerOf(token);
    final previous = await _readOwner();
    if (owner == null || previous != owner) {
      await localData.clearAll();
    }
    if (owner != null) {
      await _writeOwner(owner);
    } else {
      await _clearOwner();
    }
    await _tokenStorage.write(token);
    isAuthenticated.value = true;
  }

  Future<LocalDataOwner?> _ownerOf(SessionToken token) async {
    final userId = token.userId;
    final getServerUrl = _getServerUrl;
    if (userId == null || getServerUrl == null) return null;
    try {
      final serverUrl = await getServerUrl();
      if (serverUrl == null) return null;
      return LocalDataOwner(serverUrl: serverUrl, userId: userId);
    } on Object catch (error) {
      debugPrint('Failed to read server URL for local data owner: $error');
      return null;
    }
  }

  // Owner-storage failures never block login/logout: an unreadable owner is
  // treated as unknown, which errs on the side of clearing local data.
  Future<LocalDataOwner?> _readOwner() async {
    try {
      return await _ownerStorage?.read();
    } on Object catch (error) {
      debugPrint('Failed to read local data owner: $error');
      return null;
    }
  }

  Future<void> _writeOwner(LocalDataOwner owner) async {
    try {
      await _ownerStorage?.write(owner);
    } on Object catch (error) {
      debugPrint('Failed to write local data owner: $error');
    }
  }

  Future<void> _clearOwner() async {
    try {
      await _ownerStorage?.clear();
    } on Object catch (error) {
      debugPrint('Failed to clear local data owner: $error');
    }
  }
}
