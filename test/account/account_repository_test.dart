import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/account/account_api.dart';
import 'package:trek/account/account_models.dart';
import 'package:trek/account/account_repository.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';

import '../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

http.Client _offline() =>
    MockClient((_) async => throw http.ClientException('offline'));

AccountRepository _repository({
  required http.Client httpClient,
  InMemoryAccountLocalStore? localStore,
}) {
  return AccountRepository(
    accountApi: AccountApi(
      apiClient: ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: httpClient,
      ),
    ),
    localStore: localStore ?? InMemoryAccountLocalStore(),
  );
}

void main() {
  group('refreshAccount', () {
    test('fetches, then writes the result to the cache', () async {
      final store = InMemoryAccountLocalStore();
      final repository = _repository(
        httpClient: MockClient(
          (_) async => _json(fakeMeResponse(username: 'grace')),
        ),
        localStore: store,
      );

      final account = await repository.refreshAccount();

      expect(account.username, 'grace');
      expect(store.account?.username, 'grace');
    });

    test('leaves the cache untouched and rethrows when offline', () async {
      final store = InMemoryAccountLocalStore(
        initial: const TrekAccount(
          id: 1,
          username: 'cached-ada',
          email: 'ada@example.com',
        ),
      );
      final repository = _repository(httpClient: _offline(), localStore: store);

      await expectLater(
        repository.refreshAccount(),
        throwsA(isA<NetworkException>()),
      );
      // The stale entry is still there for the screen to fall back to.
      expect(store.account?.username, 'cached-ada');
    });

    test('rethrows an UnauthorizedException for a dead session', () async {
      final repository = _repository(
        httpClient: MockClient((_) async => _json({'error': 'nope'}, 401)),
      );

      expect(
        repository.refreshAccount(),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });

  group('cachedAccount', () {
    test('returns null before anything has been fetched', () async {
      final repository = _repository(
        httpClient: MockClient((_) async => fail('no network')),
      );

      expect(await repository.cachedAccount(), isNull);
    });

    test('returns the stored account without touching the network', () async {
      final repository = _repository(
        httpClient: MockClient((_) async => fail('no network')),
        localStore: InMemoryAccountLocalStore(
          initial: const TrekAccount(id: 2, username: 'x', email: 'x@y.z'),
        ),
      );

      expect((await repository.cachedAccount())?.id, 2);
    });
  });

  test('clearCachedAccount drops the cache', () async {
    final store = InMemoryAccountLocalStore(
      initial: const TrekAccount(id: 1, username: 'x', email: 'x@y.z'),
    );
    final repository = _repository(httpClient: _offline(), localStore: store);

    await repository.clearCachedAccount();

    expect(store.account, isNull);
  });
}
