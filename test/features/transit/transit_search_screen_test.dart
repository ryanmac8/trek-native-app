import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/features/transit/transit_search_screen.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/transit/transit_api.dart';
import 'package:trek/transit/transit_models.dart';
import 'package:trek/transit/transit_repository.dart';

import '../../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required http.Client httpClient,
  InMemoryTransitLocalStore? localStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transitRepositoryProvider.overrideWithValue(
          TransitRepository(
            transitApi: TransitApi(
              apiClient: ApiClient(
                baseUrl: 'https://trek.example.com',
                httpClient: httpClient,
              ),
            ),
            localStore: localStore ?? InMemoryTransitLocalStore(),
          ),
        ),
      ],
      child: const MaterialApp(home: TransitSearchScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _stop(String name) => {
  'name': name,
  'lat': -41.0,
  'lng': 174.0,
  'type': 'STOP',
  'area': 'Wellington',
};

Future<void> _submit(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('plans a route from two searched stops', (tester) async {
    final api = MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/transit/geocode') {
        final q = request.url.queryParameters['q']!;
        return _json({
          'results': [_stop(q == 'home' ? 'Home Stop' : 'Museum Stop')],
        });
      }
      if (path == '/api/transit/plan') {
        return _json({
          'itineraries': [
            {
              'startTime': DateTime(2026, 8, 30, 9).toUtc().toIso8601String(),
              'endTime': DateTime(2026, 8, 30, 9, 25).toUtc().toIso8601String(),
              'duration': 1500,
              'transfers': 1,
              'walkSeconds': 240,
              'legs': [
                {
                  'mode': 'BUS',
                  'from': {'name': 'Home Stop'},
                  'to': {'name': 'Museum Stop'},
                  'duration': 900,
                  'line': '1',
                },
              ],
            },
          ],
        });
      }
      return _json({'error': 'unexpected ${request.url}'}, 500);
    });

    await _pump(tester, httpClient: api);

    final fields = find.byType(TextField);
    await _submit(tester, fields.first, 'home');
    await tester.tap(find.text('Home Stop'));
    await tester.pumpAndSettle();

    await _submit(tester, find.byType(TextField).last, 'museum');
    await tester.tap(find.text('Museum Stop'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Find routes'));
    await tester.pumpAndSettle();

    expect(find.text('09:00 – 09:25'), findsOneWidget);
    expect(find.text('Bus 1'), findsOneWidget);
    expect(find.textContaining('1 transfer'), findsOneWidget);
  });

  testWidgets('stop search shows an offline message with nothing cached', (
    tester,
  ) async {
    await _pump(
      tester,
      httpClient: MockClient((_) async => throw http.ClientException('x')),
    );

    await _submit(tester, find.byType(TextField).first, 'welly');

    expect(find.textContaining("You're offline"), findsOneWidget);
  });

  testWidgets('airport search renders results from the API', (tester) async {
    final api = MockClient((request) async {
      expect(request.url.path, '/api/airports/search');
      return _json([
        {
          'iata': 'WLG',
          'icao': 'NZWN',
          'name': 'Wellington International Airport',
          'city': 'Wellington',
          'country': 'New Zealand',
          'lat': -41.3,
          'lng': 174.8,
          'tz': 'Pacific/Auckland',
        },
      ]);
    });

    await _pump(tester, httpClient: api);
    await tester.tap(find.text('Airports'));
    await tester.pumpAndSettle();

    await _submit(tester, find.byType(TextField).first, 'wellington');

    expect(find.text('Wellington International Airport'), findsOneWidget);
    expect(find.text('Wellington, New Zealand'), findsOneWidget);
    expect(find.text('WLG'), findsOneWidget);
  });

  testWidgets('airport search falls back to cached results when offline', (
    tester,
  ) async {
    final store = InMemoryTransitLocalStore()
      ..airports['auckland'] = const [
        Airport(
          iata: 'AKL',
          name: 'Auckland Airport',
          city: 'Auckland',
          country: 'New Zealand',
          lat: -37,
          lng: 174.8,
          tz: 'Pacific/Auckland',
        ),
      ];

    await _pump(
      tester,
      httpClient: MockClient((_) async => throw http.ClientException('x')),
      localStore: store,
    );
    await tester.tap(find.text('Airports'));
    await tester.pumpAndSettle();

    await _submit(tester, find.byType(TextField).first, 'Auckland');

    expect(find.text('Auckland Airport'), findsOneWidget);
  });
}
