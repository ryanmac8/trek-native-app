import 'package:flutter_test/flutter_test.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/sync/sync_policy.dart';

void main() {
  const policy = SyncPolicy();

  group('SyncPolicy.classify', () {
    test('no response at all is offline', () {
      expect(policy.classify(const NetworkException()), SyncFailure.offline);
    });

    test('401 waits for the session to be restored', () {
      expect(
        policy.classify(const UnauthorizedException()),
        SyncFailure.unauthorized,
      );
    });

    test('408, 429 and 5xx are transient', () {
      for (final status in [408, 429, 500, 502, 503]) {
        expect(
          policy.classify(ServerException(status, 'x')),
          SyncFailure.transient,
          reason: '$status',
        );
      }
    });

    test('other 4xx responses are rejected', () {
      expect(
        policy.classify(const ValidationException('Name is required')),
        SyncFailure.rejected,
      );
      expect(policy.classify(const ForbiddenException()), SyncFailure.rejected);
      expect(
        policy.classify(const ServerException(404, 'Not found')),
        SyncFailure.rejected,
      );
      expect(
        policy.classify(const ServerException(409, 'Conflict')),
        SyncFailure.rejected,
      );
    });

    test('a non-API error is transient, so it is retried a bounded number '
        'of times rather than dropped outright', () {
      expect(
        policy.classify(const FormatException('bad json')),
        SyncFailure.transient,
      );
    });
  });

  group('SyncPolicy.delayFor', () {
    test('doubles per consecutive failure, capped at maxDelay', () {
      const policy = SyncPolicy(
        baseDelay: Duration(seconds: 2),
        maxDelay: Duration(seconds: 30),
      );

      expect(policy.delayFor(1), const Duration(seconds: 2));
      expect(policy.delayFor(2), const Duration(seconds: 4));
      expect(policy.delayFor(3), const Duration(seconds: 8));
      expect(policy.delayFor(4), const Duration(seconds: 16));
      expect(policy.delayFor(5), const Duration(seconds: 30));
      expect(policy.delayFor(1000), const Duration(seconds: 30));
    });
  });
}
