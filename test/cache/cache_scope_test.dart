import 'package:flutter_test/flutter_test.dart';
import 'package:trek/auth/session_token.dart';
import 'package:trek/cache/cache_scope.dart';
import 'package:trek/config/server_config.dart';

import '../test_helpers.dart';

void main() {
  group('jwtAccountId', () {
    test('reads the numeric id claim', () {
      expect(jwtAccountId(fakeJwt({'id': 7, 'pv': 1, 'exp': 1})), '7');
    });

    test('is null without an id claim or for a non-JWT', () {
      expect(jwtAccountId(fakeJwt({'exp': 1})), isNull);
      expect(jwtAccountId('not-a-jwt'), isNull);
      expect(jwtAccountId('a.!!!.c'), isNull);
    });
  });

  group('accountCacheScope', () {
    test('combines the public server URL and the account id', () async {
      final tokens = InMemoryTokenStorage();
      await tokens.write(SessionToken.fromJwt(fakeJwt({'id': 7, 'exp': 1})));
      final scope = accountCacheScope(
        serverConfigStorage: InMemoryServerConfigStorage(
          initial: const ServerConfig(
            publicUrl: 'https://trek.example.com',
            privateUrl: 'http://192.168.1.5:3000',
          ),
        ),
        tokenStorage: tokens,
      );

      // An expired session still scopes, so cached data stays reachable.
      expect(await scope(), 'https://trek.example.com#7');
    });

    test('is null with no server or no session', () async {
      final noServer = accountCacheScope(
        serverConfigStorage: InMemoryServerConfigStorage(),
        tokenStorage: InMemoryTokenStorage(),
      );
      final noSession = accountCacheScope(
        serverConfigStorage: InMemoryServerConfigStorage(
          initial: const ServerConfig(publicUrl: 'https://trek.example.com'),
        ),
        tokenStorage: InMemoryTokenStorage(),
      );

      expect(await noServer(), isNull);
      expect(await noSession(), isNull);
    });
  });
}
