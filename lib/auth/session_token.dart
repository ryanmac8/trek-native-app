import 'dart:convert';

/// Trek's session credential: a single JWT (returned as `token` by
/// `POST /api/auth/login`, `.../mfa/verify-login`, etc., and also set as an
/// httpOnly cookie for the web PWA — the mobile app uses the bearer form).
///
/// There is no separate access/refresh token pair: the JWT's own `exp` claim
/// is the session lifetime (`SESSION_DURATION` / `SESSION_DURATION_REMEMBER`
/// server-side), and there is no refresh endpoint for password logins — once
/// it expires, the user has to log in again.
class SessionToken {
  const SessionToken({required this.token, required this.expiresAt});

  /// Decodes a JWT's `exp` claim (seconds since epoch) into a [SessionToken].
  /// Only the payload is read — Trek's backend is the one that verifies the
  /// signature; the client just needs to know when to treat it as stale.
  factory SessionToken.fromJwt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw const FormatException(
        'Not a valid JWT (expected 3 dot-separated segments).',
      );
    }

    final normalized = base64Url.normalize(parts[1]);
    final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (payload is! Map<String, dynamic> || payload['exp'] is! int) {
      throw const FormatException(
        'JWT payload is missing a numeric "exp" claim.',
      );
    }

    return SessionToken(
      token: token,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (payload['exp'] as int) * 1000,
        isUtc: true,
      ),
    );
  }

  final String token;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  Map<String, dynamic> toStorageJson() => {
    'token': token,
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory SessionToken.fromStorageJson(Map<String, dynamic> json) {
    return SessionToken(
      token: json['token'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );
  }
}
