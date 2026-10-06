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

  group('SessionToken.userId', () {
    test('reads the id claim', () {
      final token = SessionToken.fromJwt(fakeJwt({'id': 42, 'exp': 1 << 31}));

      expect(token.userId, 42);
    });

    test('is null when the id claim is missing or not an int', () {
      expect(SessionToken.fromJwt(fakeJwt({'exp': 1 << 31})).userId, isNull);
      expect(
        SessionToken.fromJwt(fakeJwt({'id': '42', 'exp': 1 << 31})).userId,
        isNull,
      );
    });

    test('survives a storage round-trip', () {
      final token = SessionToken.fromJwt(fakeJwt({'id': 7, 'exp': 1 << 31}));

      expect(SessionToken.fromStorageJson(token.toStorageJson()).userId, 7);
    });

    test('is null for an unreadable token', () {
      expect(
        SessionToken(token: 'not-a-jwt', expiresAt: DateTime.utc(2030)).userId,
        isNull,
      );
      expect(
        SessionToken(token: 'a.%%%.c', expiresAt: DateTime.utc(2030)).userId,
        isNull,
      );
    });
  });
}
