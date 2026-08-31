/// Data type for Trek's current-account endpoint.
///
/// Confirmed against Trek's backend (`server/src/nest/auth/`):
///
/// - `GET /api/auth/me` → `{ user: TrekAccount }` (`AuthController.me`, via
///   `AuthService.getCurrentUser` + `stripUserForClient`). JWT-guarded and
///   MFA-exempt. Secrets (password hash, API keys, MFA secret/backup codes)
///   are stripped server-side and never reach the client.
///
/// The wire shape and the local-cache shape are the same JSON here, so
/// `fromJson` / `toJson` round-trip through [AccountLocalStore].
library;

String _string(Object? value) => value is String ? value : '';

String? _stringOrNull(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

bool _bool(Object? value) => value == true || value == 1 || value == '1';

/// The signed-in Trek user, from `GET /api/auth/me`.
class TrekAccount {
  const TrekAccount({
    required this.id,
    required this.username,
    required this.email,
    this.role = 'user',
    this.avatarUrl,
    this.oidcIssuer,
    this.createdAt,
    this.mfaEnabled = false,
    this.mustChangePassword = false,
  });

  final int id;
  final String username;
  final String email;

  /// `user` or `admin` (Trek's two roles). Kept as a raw string.
  final String role;

  /// Absolute or server-relative avatar URL the server resolved, when the
  /// account has one.
  final String? avatarUrl;

  /// The OIDC issuer this account authenticates through, when it is an SSO
  /// account rather than a password one. `null` for password accounts —
  /// the settings screen uses this to hide password-only actions.
  final String? oidcIssuer;

  /// When the account was created, if the server sent a parseable
  /// timestamp (ISO-8601, `Z`-suffixed by `stripUserForClient`).
  final DateTime? createdAt;

  /// Whether TOTP MFA is enabled on the account.
  final bool mfaEnabled;

  /// Whether the server is forcing a password change on next login.
  final bool mustChangePassword;

  /// True when the account signs in through an identity provider rather
  /// than a Trek password.
  bool get isSsoAccount => oidcIssuer != null;

  factory TrekAccount.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'];
    return TrekAccount(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      username: _string(json['username']),
      email: _string(json['email']),
      role: _stringOrNull(json['role']) ?? 'user',
      avatarUrl: _stringOrNull(json['avatar_url']),
      oidcIssuer: _stringOrNull(json['oidc_issuer']),
      createdAt: createdAtRaw is String
          ? DateTime.tryParse(createdAtRaw)
          : null,
      mfaEnabled: _bool(json['mfa_enabled']),
      mustChangePassword: _bool(json['must_change_password']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'role': role,
    'avatar_url': avatarUrl,
    'oidc_issuer': oidcIssuer,
    'created_at': createdAt?.toIso8601String(),
    'mfa_enabled': mfaEnabled,
    'must_change_password': mustChangePassword,
  };
}
