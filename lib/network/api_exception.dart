/// Base type for all errors raised by [ApiClient].
///
/// Callers can catch this single type for generic handling, or catch the
/// specific subtypes below to react differently (e.g. redirect to login on
/// [UnauthorizedException]). [code] mirrors Trek's optional machine-readable
/// `code` field (e.g. `AUTH_REQUIRED`), when the response included one.
sealed class ApiException implements Exception {
  const ApiException(this.message, [this.code]);

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// The device is offline, the request timed out, or the host could not be
/// reached — no HTTP response was received at all.
class NetworkException extends ApiException {
  const NetworkException([super.message = 'Unable to reach the server.']);
}

/// The server returned 401 Unauthorized — the session token is missing,
/// invalid, expired, or was invalidated (e.g. by a password change
/// elsewhere).
class UnauthorizedException extends ApiException {
  const UnauthorizedException([
    super.message = 'Session expired. Please log in again.',
    super.code,
  ]);
}

/// The server returned 403 Forbidden — the caller is authenticated but not
/// allowed to perform this action.
class ForbiddenException extends ApiException {
  const ForbiddenException([
    super.message = 'You do not have permission to do that.',
    super.code,
  ]);
}

/// The server returned 400/422 with a validation-style error message. Trek
/// reports validation failures as a single flat message, not per-field
/// errors.
class ValidationException extends ApiException {
  const ValidationException(super.message, [super.code]);
}

/// Any other non-2xx response (404, 5xx, etc.).
class ServerException extends ApiException {
  const ServerException(this.statusCode, super.message);

  final int statusCode;
}
