import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/share/share_api.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

ShareApi _api(http.Client httpClient) {
  return ShareApi(
    apiClient: ApiClient(
      baseUrl: 'https://trek.example.com',
      httpClient: httpClient,
    ),
  );
}

void main() {
  group('getShareLink', () {
    test('GETs the trip-scoped endpoint and parses an enabled link', () async {
      Uri? requestedUri;
      final api = _api(
        MockClient((request) async {
          requestedUri = request.url;
          return _json({
            'token': 'abc123',
            'created_at': '2026-01-01T00:00:00.000Z',
            'share_map': true,
            'share_bookings': true,
            'share_packing': false,
            'share_budget': false,
            'share_collab': false,
          });
        }),
      );

      final link = await api.getShareLink('20');

      expect(requestedUri?.path, '/api/trips/20/share-link');
      expect(link?.token, 'abc123');
      expect(link?.tripId, '20');
    });

    test('a trip with no share link returns null, not an error', () async {
      final api = _api(MockClient((request) async => _json({'token': null})));

      expect(await api.getShareLink('20'), isNull);
    });

    test('a 404 (trip not found) surfaces as an exception', () async {
      final api = _api(
        MockClient((request) async => _json({'error': 'Trip not found'}, 404)),
      );

      expect(api.getShareLink('999'), throwsA(isA<ApiException>()));
    });
  });

  group('createOrUpdateShareLink', () {
    test('POSTs the permission flags and builds the link from what was sent '
        '(the response only carries the token)', () async {
      Map<String, dynamic>? sentBody;
      final api = _api(
        MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'token': 'abc123'}, 201);
        }),
      );

      final link = await api.createOrUpdateShareLink(
        '20',
        shareMap: true,
        shareBookings: false,
        sharePacking: true,
        shareBudget: false,
        shareCollab: true,
      );

      expect(sentBody, {
        'share_map': true,
        'share_bookings': false,
        'share_packing': true,
        'share_budget': false,
        'share_collab': true,
      });
      expect(link.token, 'abc123');
      expect(link.shareBookings, isFalse);
      expect(link.sharePacking, isTrue);
      expect(link.shareCollab, isTrue);
    });

    test('a 403 (no manage permission) surfaces as an exception', () async {
      final api = _api(
        MockClient((request) async => _json({'error': 'No permission'}, 403)),
      );

      expect(
        api.createOrUpdateShareLink(
          '20',
          shareMap: true,
          shareBookings: true,
          sharePacking: false,
          shareBudget: false,
          shareCollab: false,
        ),
        throwsA(isA<ForbiddenException>()),
      );
    });
  });

  group('deleteShareLink', () {
    test('DELETEs the trip-scoped endpoint', () async {
      Uri? requestedUri;
      String? method;
      final api = _api(
        MockClient((request) async {
          requestedUri = request.url;
          method = request.method;
          return _json({'success': true});
        }),
      );

      await api.deleteShareLink('20');

      expect(requestedUri?.path, '/api/trips/20/share-link');
      expect(method, 'DELETE');
    });

    test('a 403 (no manage permission) surfaces as an exception', () async {
      final api = _api(
        MockClient((request) async => _json({'error': 'No permission'}, 403)),
      );

      expect(api.deleteShareLink('20'), throwsA(isA<ForbiddenException>()));
    });
  });
}
