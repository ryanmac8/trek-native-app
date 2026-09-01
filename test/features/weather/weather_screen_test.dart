import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trek/app/providers.dart';
import 'package:trek/features/weather/weather_screen.dart';
import 'package:trek/network/api_client.dart';
import 'package:trek/weather/weather_api.dart';
import 'package:trek/weather/weather_models.dart';
import 'package:trek/weather/weather_repository.dart';

import '../../test_helpers.dart';

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _forecastBody() => {
  'temp': 18,
  'temp_max': 22,
  'temp_min': 14,
  'main': 'Clear',
  'description': 'Clear sky',
  'type': 'forecast',
};

Future<void> _pump(
  WidgetTester tester, {
  required http.Client httpClient,
  InMemoryWeatherLocalStore? localStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        weatherRepositoryProvider.overrideWithValue(
          WeatherRepository(
            weatherApi: WeatherApi(
              apiClient: ApiClient(
                baseUrl: 'https://trek.example.com',
                httpClient: httpClient,
              ),
            ),
            localStore: localStore ?? InMemoryWeatherLocalStore(),
          ),
        ),
      ],
      child: const MaterialApp(home: WeatherScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('picking a destination shows current conditions and a forecast', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/weather') {
        final hasDate = request.url.queryParameters.containsKey('date');
        return _json(
          hasDate
              ? _forecastBody()
              : {
                  'temp': 17,
                  'main': 'Clouds',
                  'description': 'Overcast',
                  'type': 'current',
                },
        );
      }
      return _json({'error': 'not found'}, 404);
    });

    await _pump(tester, httpClient: client);

    await tester.enterText(find.byType(TextField), 'Lisbon');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Lisbon'));
    await tester.pumpAndSettle();

    expect(find.text('Lisbon, Portugal'), findsOneWidget); // app bar title
    expect(find.text('17°C'), findsOneWidget); // current conditions
    expect(find.text('7-day forecast'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('22° / 14°'), findsWidgets); // forecast rows
  });

  testWidgets('offline with no cache shows an explicit offline state', (
    tester,
  ) async {
    final client = MockClient((request) async {
      throw http.ClientException('offline');
    });

    await _pump(tester, httpClient: client);

    await tester.enterText(find.byType(TextField), 'Berlin');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Berlin'));
    await tester.pumpAndSettle();

    expect(find.textContaining('offline'), findsWidgets);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('offline with a cached answer paints it behind a notice', (
    tester,
  ) async {
    final store = InMemoryWeatherLocalStore();
    final cached = WeatherReport.fromJson({
      'temp': 5,
      'main': 'Snow',
      'description': 'Light snowfall',
      'type': 'current',
    });
    // Seed current + every forecast day, all stale so a refresh is attempted.
    store.entries['52.52_13.40_current'] = cached;
    store.staleKeys.add('52.52_13.40_current');

    final client = MockClient((request) async {
      throw http.ClientException('offline');
    });

    await _pump(tester, httpClient: client, localStore: store);

    await tester.enterText(find.byType(TextField), 'Berlin');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Berlin'));
    await tester.pumpAndSettle();

    expect(find.text('5°C'), findsOneWidget);
    expect(find.textContaining('Showing saved weather'), findsOneWidget);
  });

  testWidgets('filtering the destination list narrows the results', (
    tester,
  ) async {
    await _pump(tester, httpClient: MockClient((_) async => _json({})));

    expect(find.widgetWithText(ListTile, 'Reykjavík'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz no match');
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNothing);
    expect(find.textContaining('No destination matches'), findsOneWidget);
  });
}
