/// Base type for all errors raised by [ApiClient].
///
/// Callers can catch this single type for generic handling, or catch the
/// specific subtypes below to react differently (e.g. redirect to login on
/// [UnauthorizedException]).
sealed class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The device is offline, the request timed out, or the host could not be
/// reached — no HTTP response was received at all.
class NetworkException extends ApiException {
  const NetworkException([super.message = 'Unable to reach the server.']);
}

/// The server returned 401 Unauthorized — the access token is missing,
/// invalid, or expired.
class UnauthorizedException extends ApiException {
  const UnauthorizedException([super.message = 'Session expired. Please log in again.']);
}

/// The server returned 403 Forbidden — the caller is authenticated but not
/// allowed to perform this action.
class ForbiddenException extends ApiException {
  const ForbiddenException([super.message = 'You do not have permission to do that.']);
}

/// The server returned 422 (or 400) with field-level validation errors.
class ValidationException extends ApiException {
  const ValidationException(super.message, this.errors);

  /// Field name -> list of error messages, as returned by the API.
  final Map<String, List<String>> errors;
}

/// Any other non-2xx response (404, 5xx, etc.).
class ServerException extends ApiException {
  const ServerException(this.statusCode, super.message);

  final int statusCode;
}
