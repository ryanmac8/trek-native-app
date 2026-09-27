import 'dart:math' as math;

import '../network/api_exception.dart';

/// How [SyncEngine] reacts to a failed push.
enum SyncFailure {
  /// No HTTP response at all ([NetworkException]). Stop draining, keep the
  /// write, retry with backoff. Doesn't count against the write's attempts.
  offline,

  /// 401 ([UnauthorizedException]). Stop draining and keep the write until
  /// the session is restored.
  unauthorized,

  /// 408, 429, 5xx, or an unexpected non-API error. Stop draining, count an
  /// attempt, retry with backoff — until [SyncPolicy.maxAttempts], after
  /// which the write is treated as [rejected].
  transient,

  /// Any other 4xx (validation, forbidden, not found, conflict). Retrying
  /// can't succeed, so the write is dropped and its handler's
  /// [SyncHandler.onRejected] rolls back the optimistic local change.
  rejected,
}

class SyncPolicy {
  const SyncPolicy({
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.maxAttempts = 8,
  });

  final Duration baseDelay;
  final Duration maxDelay;
  final int maxAttempts;

  SyncFailure classify(Object error) {
    return switch (error) {
      NetworkException() => SyncFailure.offline,
      UnauthorizedException() => SyncFailure.unauthorized,
      ServerException(:final statusCode)
          when statusCode == 408 || statusCode == 429 || statusCode >= 500 =>
        SyncFailure.transient,
      ApiException() => SyncFailure.rejected,
      _ => SyncFailure.transient,
    };
  }

  /// Exponential backoff: [baseDelay] doubled per consecutive failure
  /// (1-based), capped at [maxDelay].
  Duration delayFor(int consecutiveFailures) {
    final exponent = math.min(math.max(consecutiveFailures - 1, 0), 20);
    final delay = baseDelay * math.pow(2, exponent).toInt();
    return delay > maxDelay ? maxDelay : delay;
  }
}
