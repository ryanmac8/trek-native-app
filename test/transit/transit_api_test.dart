import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/transit/transit_api.dart';
import 'package:trek/transit/transit_models.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

TransitApi _api(http.Client client) {
  return TransitApi(
    apiClient: ApiClient(
      baseUrl: 'https://trek.example.com',
      httpClient: client,
    ),
  );
}

void main() {
  group('searchStops', () {
    test('hits /api/transit/geocode with q + near and maps results', () async {
      Uri? seen;
      final api = _api(
        MockClient((request) async {
          seen = request.url;
          return _json({
            'results': [
              {
                'name': 'Wellington Station',
                'lat': -41.27,
                'lng': 174.78,
                'type': 'STOP',
                'area': 'Wellington',
              },
            ],
          });
        }),
      );

      final results = await api.searchStops('welling', near: '-41.3,174.8');

      expect(seen?.path, '/api/transit/geocode');
      expect(seen?.queryParameters['q'], 'welling');
      expect(seen?.queryParameters['near'], '-41.3,174.8');
      expect(results.single.name, 'Wellington Station');
    });
  });

  group('planRoute', () {
    test('hits /api/transit/plan and maps itineraries', () async {
      Uri? seen;
      final api = _api(
        MockClient((request) async {
          seen = request.url;
          return _json({
            'itineraries': [
              {
                'startTime': '2026-08-30T08:00:00.000Z',
                'endTime': '2026-08-30T08:30:00.000Z',
                'duration': 1800,
                'transfers': 0,
                'walkSeconds': 120,
                'legs': [
                  {
                    'mode': 'BUS',
                    'from': {'name': 'A'},
                    'to': {'name': 'B'},
                    'duration': 1500,
                    'line': '2',
                  },
                ],
              },
            ],
          });
        }),
      );

      final itineraries = await api.planRoute(
        const TransitPlanQuery(from: '1,2', to: '3,4'),
      );

      expect(seen?.path, '/api/transit/plan');
      expect(seen?.queryParameters['from'], '1,2');
      expect(itineraries.single.transitLegs.single.line, '2');
    });
  });

  group('searchAirports', () {
    test('maps the bare array response', () async {
      final api = _api(
        MockClient((request) async {
          expect(request.url.path, '/api/airports/search');
          expect(request.url.queryParameters['q'], 'auck');
          return _json([
            {
              'iata': 'AKL',
              'icao': 'NZAA',
              'name': 'Auckland Airport',
              'city': 'Auckland',
              'country': 'New Zealand',
              'lat': -37.0,
              'lng': 174.79,
              'tz': 'Pacific/Auckland',
            },
          ]);
        }),
      );

      final results = await api.searchAirports('auck');

      expect(results.single.iata, 'AKL');
    });
  });

  group('lookupAirport', () {
    test('returns the airport for a known code', () async {
      final api = _api(
        MockClient(
          (request) async => _json({
            'iata': 'WLG',
            'icao': 'NZWN',
            'name': 'Wellington',
            'city': 'Wellington',
            'country': 'New Zealand',
            'lat': -41.3,
            'lng': 174.8,
            'tz': 'Pacific/Auckland',
          }),
        ),
      );

      expect((await api.lookupAirport('wlg'))?.iata, 'WLG');
    });

    test('returns null on a 404', () async {
      final api = _api(
        MockClient((_) async => _json({'error': 'Airport not found'}, 404)),
      );

      expect(await api.lookupAirport('ZZZ'), isNull);
    });

    test('propagates a non-404 server error', () async {
      final api = _api(MockClient((_) async => _json({'error': 'boom'}, 500)));

      expect(api.lookupAirport('WLG'), throwsA(isA<ServerException>()));
    });
  });
}
