import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/maps/maps_api.dart';
import 'package:trek/maps/maps_models.dart';
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
  group('MapsApi.reverseGeocode', () {
    test('sends lat/lng/lang as query params and parses the result', () async {
      final api = MapsApi(
        apiClient: ApiClient(
          baseUrl: 'https://trek.example.com',
          httpClient: MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.url.path, '/api/maps/reverse');
            expect(request.url.queryParameters['lat'], '48.8566');
            expect(request.url.queryParameters['lng'], '2.3522');
            expect(request.url.queryParameters['lang'], 'en');
            return _json({
              'name': 'Notre-Dame',
              'address': 'Paris, France',
            }, 200);
          }),
        ),
      );

      final result = await api.reverseGeocode(const LatLng(48.8566, 2.3522));

      expect(result.name, 'Notre-Dame');
      expect(result.address, 'Paris, France');
    });

    test('a missing lat/lng surfaces as a ValidationException', () async {
      final api = MapsApi(
        apiClient: ApiClient(
          baseUrl: 'https://trek.example.com',
          httpClient: MockClient((request) async {
            return _json({'error': 'lat and lng required'}, 400);
          }),
        ),
      );

      expect(
        () => api.reverseGeocode(const LatLng(0, 0)),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('MapsApi.resolveUrl', () {
    test('POSTs the url and parses the resolved place', () async {
      final api = MapsApi(
        apiClient: ApiClient(
          baseUrl: 'https://trek.example.com',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/maps/resolve-url');
            expect(jsonDecode(request.body), {
              'url': 'https://maps.app.goo.gl/abc123',
            });
            return _json({
              'lat': 48.8584,
              'lng': 2.2945,
              'name': 'Eiffel Tower',
              'address': 'Paris, France',
              'google_ftid': null,
            }, 200);
          }),
        ),
      );

      final place = await api.resolveUrl('https://maps.app.goo.gl/abc123');

      expect(place.point, const LatLng(48.8584, 2.2945));
      expect(place.name, 'Eiffel Tower');
    });

    test(
      'a URL that cannot be resolved surfaces as a ValidationException',
      () async {
        final api = MapsApi(
          apiClient: ApiClient(
            baseUrl: 'https://trek.example.com',
            httpClient: MockClient((request) async {
              return _json({'error': 'Failed to resolve URL'}, 400);
            }),
          ),
        );

        expect(
          () => api.resolveUrl('not a maps url'),
          throwsA(isA<ValidationException>()),
        );
      },
    );
  });
}
