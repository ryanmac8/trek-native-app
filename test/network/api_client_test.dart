import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';

http.Response _json(Map<String, dynamic> body, int statusCode) {
  return http.Response(jsonEncode(body), statusCode, headers: {
    'content-type': 'application/json',
  });
}

void main() {
  group('ApiClient', () {
    test('get() returns decoded JSON on a 2xx response', () async {
      final client = ApiClient(
        baseUrl: 'https://api.trek.app',
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.toString(), 'https://api.trek.app/trips?page=1');
          return _json({'trips': []}, 200);
        }),
      );

      final result = await client.get('/trips', query: {'page': 1});

      expect(result, {'trips': []});
    });

    test('attaches a bearer token when getAccessToken is provided', () async {
      final client = ApiClient(
        baseUrl: 'https://api.trek.app',
        getAccessToken: () async => 'abc123',
        httpClient: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer abc123');
          return _json({}, 200);
        }),
      );

      await client.get('/trips');
    });

    test('sends a JSON-encoded body on post()', () async {
      final client = ApiClient(
        baseUrl: 'https://api.trek.app',
        httpClient: MockClient((request) async {
          expect(request.headers['Content-Type'], 'application/json');
          expect(jsonDecode(request.body), {'name': 'Iceland'});
          return _json({'id': '1'}, 201);
        }),
      );

      final result = await client.post('/trips', body: {'name': 'Iceland'});

      expect(result, {'id': '1'});
    });

    test('throws UnauthorizedException on 401 with no retry hook', () async {
      final client = ApiClient(
        baseUrl: 'https://api.trek.app',
        httpClient: MockClient((request) async {
          return _json({'message': 'Token expired'}, 401);
        }),
      );

      await expectLater(
        client.get('/trips'),
        throwsA(isA<UnauthorizedException>().having((e) => e.message, 'message', 'Token expired')),
      );
    });

    test('retries once after a 401 when onUnauthorized resolves true', () async {
      var callCount = 0;
      final client = ApiClient(
        baseUrl: 'https://api.trek.app',
        onUnauthorized: () async => true,
        httpClient: MockClient((request) async {
          callCount++;
          if (callCount == 1) return _json({}, 401);
          return _json({'ok': true}, 200);
        }),
      );

      final result = await client.get('/trips');

      expect(callCount, 2);
      expect(result, {'ok': true});
    });

    test('does not retry more than once even if the retry also 401s', () async {
      var callCount = 0;
      final client = ApiClient(
        baseUrl: 'https://api.trek.app',
        onUnauthorized: () async => true,
        httpClient: MockClient((request) async {
          callCount++;
          return _json({}, 401);
        }),
      );

      await expectLater(client.get('/trips'), throwsA(isA<UnauthorizedException>()));
      expect(callCount, 2);
    });

    test('throws ValidationException with field errors on 422', () async {
      final client = ApiClient(
        baseUrl: 'https://api.trek.app',
        httpClient: MockClient((request) async {
          return _json({
            'message': 'Validation failed',
            'errors': {
              'name': ['must not be blank'],
            },
          }, 422);
        }),
      );

      await expectLater(
        client.post('/trips', body: {}),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors['name'],
            'errors[name]',
            ['must not be blank'],
          ),
        ),
      );
    });

    test('throws ServerException on 500', () async {
      final client = ApiClient(
        baseUrl: 'https://api.trek.app',
        httpClient: MockClient((request) async {
          return _json({'message': 'Boom'}, 500);
        }),
      );

      await expectLater(
        client.get('/trips'),
        throwsA(isA<ServerException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test('throws NetworkException when the underlying client throws', () async {
      final client = ApiClient(
        baseUrl: 'https://api.trek.app',
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
      );

      await expectLater(client.get('/trips'), throwsA(isA<NetworkException>()));
    });
  });
}
