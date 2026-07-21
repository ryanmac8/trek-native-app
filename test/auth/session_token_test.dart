import 'package:flutter_test/flutter_test.dart';
import 'package:trek/auth/session_token.dart';

import '../test_helpers.dart';

void main() {
  group('SessionToken.fromJwt', () {
    test('decodes the exp claim into expiresAt', () {
      final expSeconds =
          DateTime.utc(2030, 1, 1).millisecondsSinceEpoch ~/ 1000;
      final jwt = fakeJwt({'id': 1, 'exp': expSeconds});

      final token = SessionToken.fromJwt(jwt);

      expect(token.token, jwt);
      expect(token.expiresAt, DateTime.utc(2030, 1, 1));
      expect(token.isExpired, isFalse);
    });

    test('isExpired is true once the exp claim is in the past', () {
      final expSeconds =
          DateTime.utc(2000, 1, 1).millisecondsSinceEpoch ~/ 1000;
      final jwt = fakeJwt({'id': 1, 'exp': expSeconds});

      expect(SessionToken.fromJwt(jwt).isExpired, isTrue);
    });

    test('throws FormatException for a malformed token', () {
      expect(() => SessionToken.fromJwt('not-a-jwt'), throwsFormatException);
    });

    test('throws FormatException when the payload has no exp claim', () {
      final jwt = fakeJwt({'id': 1});

      expect(() => SessionToken.fromJwt(jwt), throwsFormatException);
    });
  });

  group('SessionToken storage round-trip', () {
    test('toStorageJson/fromStorageJson preserves token and expiry', () {
      final token = SessionToken(
        token: 'abc',
        expiresAt: DateTime.utc(2030, 1, 1),
      );

      final restored = SessionToken.fromStorageJson(token.toStorageJson());

      expect(restored.token, 'abc');
      expect(restored.expiresAt, DateTime.utc(2030, 1, 1));
    });
  });
}
