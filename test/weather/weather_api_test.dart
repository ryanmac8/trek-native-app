import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/weather/weather_api.dart';
import 'package:trek/weather/weather_models.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

WeatherApi _api(http.Client client) {
  return WeatherApi(
    apiClient: ApiClient(
      baseUrl: 'https://trek.example.com',
      httpClient: client,
    ),
  );
}

void main() {
  group('fetch', () {
    test(
      'hits /api/weather with lat/lng/lang and no date for current',
      () async {
        Uri? seen;
        final api = _api(
          MockClient((request) async {
            seen = request.url;
            return _json({
              'temp': 12,
              'main': 'Clouds',
              'description': 'Overcast',
              'type': 'current',
            });
          }),
        );

        final report = await api.fetch(const GeoPoint(48.86, 2.35));

        expect(seen?.path, '/api/weather');
        expect(seen?.queryParameters['lat'], '48.86');
        expect(seen?.queryParameters['lng'], '2.35');
        expect(seen?.queryParameters['lang'], 'en');
        expect(seen?.queryParameters.containsKey('date'), isFalse);
        expect(report.kind, WeatherKind.current);
        expect(report.temp, 12);
      },
    );

    test('passes the date through for a forecast lookup', () async {
      Uri? seen;
      final api = _api(
        MockClient((request) async {
          seen = request.url;
          return _json({
            'temp': 20,
            'temp_max': 24,
            'temp_min': 16,
            'main': 'Clear',
            'description': 'Clear sky',
            'type': 'forecast',
          });
        }),
      );

      final report = await api.fetch(
        const GeoPoint(41.39, 2.17),
        date: '2026-09-10',
      );

      expect(seen?.queryParameters['date'], '2026-09-10');
      expect(report.tempMax, 24);
    });

    test(
      'returns a missing report rather than throwing on no_forecast',
      () async {
        final api = _api(
          MockClient((request) async {
            return _json({
              'temp': 0,
              'main': '',
              'description': '',
              'type': '',
              'error': 'no_forecast',
            });
          }),
        );

        final report = await api.fetch(
          const GeoPoint(0, 0),
          date: '2030-01-01',
        );

        expect(report.isMissing, isTrue);
      },
    );

    test('maps a 400 to a ValidationException', () async {
      final api = _api(
        MockClient((request) async {
          return _json({'error': 'Latitude and longitude are required'}, 400);
        }),
      );

      expect(
        () => api.fetch(const GeoPoint(0, 0)),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('fetchDetailed', () {
    test('hits /api/weather/detailed with a required date', () async {
      Uri? seen;
      final api = _api(
        MockClient((request) async {
          seen = request.url;
          return _json({
            'temp': 15,
            'main': 'Rain',
            'description': 'Rain showers',
            'type': 'forecast',
            'hourly': [
              {
                'hour': 12,
                'temp': 16,
                'precipitation': 0.4,
                'precipitation_probability': 55,
                'main': 'Rain',
                'wind': 14,
                'humidity': 80,
              },
            ],
          });
        }),
      );

      final report = await api.fetchDetailed(
        const GeoPoint(51.51, -0.13),
        date: '2026-09-05',
      );

      expect(seen?.path, '/api/weather/detailed');
      expect(seen?.queryParameters['date'], '2026-09-05');
      expect(seen?.queryParameters['lang'], 'en');
      expect(report.hourly, hasLength(1));
    });
  });
}
