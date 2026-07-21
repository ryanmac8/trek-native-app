import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';

http.Response _json(Map<String, dynamic> body, int statusCode) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  group('ApiClient', () {
    test('get() returns decoded JSON on a 2xx response', () async {
      final client = ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            'https://trek.example.com/api/trips?page=1',
          );
          return _json({'trips': []}, 200);
        }),
      );

      final result = await client.get('/api/trips', query: {'page': 1});

      expect(result, {'trips': []});
    });

    test(
      'resolves the base URL fresh from getBaseUrl on every request',
      () async {
        var currentBaseUrl = 'https://public.example.com';
        final client = ApiClient(
          getBaseUrl: () async => currentBaseUrl,
          httpClient: MockClient((request) async {
            return _json({'host': request.url.host}, 200);
          }),
        );

        final first = await client.get('/api/trips');
        expect(first, {'host': 'public.example.com'});

        currentBaseUrl = 'http://192.168.1.50:3000';
        final second = await client.get('/api/trips');
        expect(second, {'host': '192.168.1.50'});
      },
    );

    test('attaches a bearer token when getAccessToken is provided', () async {
      final client = ApiClient(
        baseUrl: 'https://trek.example.com',
        getAccessToken: () async => 'abc123',
        httpClient: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer abc123');
          return _json({}, 200);
        }),
      );

      await client.get('/api/trips');
    });

    test('sends a JSON-encoded body on post()', () async {
      final client = ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient((request) async {
          expect(request.headers['Content-Type'], 'application/json');
          expect(jsonDecode(request.body), {'name': 'Iceland'});
          return _json({'id': '1'}, 201);
        }),
      );

      final result = await client.post('/api/trips', body: {'name': 'Iceland'});

      expect(result, {'id': '1'});
    });

    test(
      'throws UnauthorizedException on 401, reading Trek\'s {error, code} shape',
      () async {
        final client = ApiClient(
          baseUrl: 'https://trek.example.com',
          httpClient: MockClient((request) async {
            return _json({
              'error': 'Invalid or expired token',
              'code': 'AUTH_REQUIRED',
            }, 401);
          }),
        );

        await expectLater(
          client.get('/api/trips'),
          throwsA(
            isA<UnauthorizedException>()
                .having((e) => e.message, 'message', 'Invalid or expired token')
                .having((e) => e.code, 'code', 'AUTH_REQUIRED'),
          ),
        );
      },
    );

    test(
      'falls back to a generic {message} field when {error} is absent',
      () async {
        final client = ApiClient(
          baseUrl: 'https://trek.example.com',
          httpClient: MockClient(
            (request) async => _json({'message': 'nope'}, 403),
          ),
        );

        await expectLater(
          client.get('/api/trips'),
          throwsA(
            isA<ForbiddenException>().having(
              (e) => e.message,
              'message',
              'nope',
            ),
          ),
        );
      },
    );

    test(
      'retries once after a 401 when onUnauthorized resolves true',
      () async {
        var callCount = 0;
        final client = ApiClient(
          baseUrl: 'https://trek.example.com',
          onUnauthorized: () async => true,
          httpClient: MockClient((request) async {
            callCount++;
            if (callCount == 1) return _json({'error': 'expired'}, 401);
            return _json({'ok': true}, 200);
          }),
        );

        final result = await client.get('/api/trips');

        expect(callCount, 2);
        expect(result, {'ok': true});
      },
    );

    test('does not retry more than once even if the retry also 401s', () async {
      var callCount = 0;
      final client = ApiClient(
        baseUrl: 'https://trek.example.com',
        onUnauthorized: () async => true,
        httpClient: MockClient((request) async {
          callCount++;
          return _json({'error': 'expired'}, 401);
        }),
      );

      await expectLater(
        client.get('/api/trips'),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(callCount, 2);
    });

    test(
      'throws ValidationException on 400/422 with Trek\'s flat error message',
      () async {
        final client = ApiClient(
          baseUrl: 'https://trek.example.com',
          httpClient: MockClient((request) async {
            return _json({'error': 'Email and password are required'}, 400);
          }),
        );

        await expectLater(
          client.post('/api/auth/login', body: {}),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.message,
              'message',
              'Email and password are required',
            ),
          ),
        );
      },
    );

    test('throws ServerException on 500', () async {
      final client = ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient((request) async {
          return _json({'error': 'Boom'}, 500);
        }),
      );

      await expectLater(
        client.get('/api/trips'),
        throwsA(
          isA<ServerException>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('throws NetworkException when the underlying client throws', () async {
      final client = ApiClient(
        baseUrl: 'https://trek.example.com',
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
      );

      await expectLater(
        client.get('/api/trips'),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
