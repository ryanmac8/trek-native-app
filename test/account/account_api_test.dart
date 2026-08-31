import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/account/account_api.dart';
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

AccountApi _api(http.Client client, {Future<String?> Function()? token}) {
  return AccountApi(
    apiClient: ApiClient(
      baseUrl: 'https://trek.example.com',
      httpClient: client,
      getAccessToken: token,
    ),
  );
}

void main() {
  test('GET /api/auth/me maps the user object', () async {
    Uri? seen;
    String? auth;
    final api = _api(
      MockClient((request) async {
        seen = request.url;
        auth = request.headers['Authorization'];
        return _json(
          fakeMeResponse(username: 'grace', email: 'grace@example.com'),
        );
      }),
      token: () async => 'jwt-123',
    );

    final account = await api.fetchAccount();

    expect(seen?.path, '/api/auth/me');
    expect(auth, 'Bearer jwt-123');
    expect(account.username, 'grace');
    expect(account.email, 'grace@example.com');
    expect(account.avatarUrl, isNotNull);
    expect(account.createdAt, DateTime.utc(2025, 1, 2, 3, 4, 5));
  });

  test('reads mfa + role + sso flags', () async {
    final api = _api(
      MockClient(
        (_) async => _json(
          fakeMeResponse(role: 'admin', mfaEnabled: true, oidcIssuer: 'okta'),
        ),
      ),
    );

    final account = await api.fetchAccount();

    expect(account.role, 'admin');
    expect(account.mfaEnabled, isTrue);
    expect(account.isSsoAccount, isTrue);
  });

  test('propagates UnauthorizedException on a dead session', () async {
    final api = _api(
      MockClient((_) async => _json({'error': 'Unauthorized'}, 401)),
    );

    expect(api.fetchAccount(), throwsA(isA<UnauthorizedException>()));
  });

  test('propagates NetworkException when the host is unreachable', () async {
    final api = _api(
      MockClient((_) async => throw http.ClientException('offline')),
    );

    expect(api.fetchAccount(), throwsA(isA<NetworkException>()));
  });
}
