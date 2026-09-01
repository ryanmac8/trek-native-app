import 'package:flutter_test/flutter_test.dart';
import 'package:trek/network/api_exception.dart';
import 'package:trek/weather/weather_api.dart';
import 'package:trek/weather/weather_models.dart';
import 'package:trek/weather/weather_repository.dart';

import '../test_helpers.dart';

/// Fake [WeatherApi] whose answers (or thrown errors) are set per date. A
/// `null` entry in [byDate] (key `'current'` for the no-date call) throws a
/// [NetworkException], standing in for the device being offline.
class _FakeWeatherApi implements WeatherApi {
  final Map<String, WeatherReport?> byDate = {};
  int calls = 0;

  WeatherReport _answer(String key) {
    calls++;
    if (!byDate.containsKey(key)) {
      return WeatherReport.fromJson({
        'temp': 15,
        'main': 'Clouds',
        'description': 'Overcast',
        'type': key == 'current' ? 'current' : 'forecast',
      });
    }
    final report = byDate[key];
    if (report == null) throw const NetworkException();
    return report;
  }

  @override
  Future<WeatherReport> fetch(GeoPoint point, {String? date}) async =>
      _answer(date ?? 'current');

  @override
  Future<WeatherReport> fetchDetailed(
    GeoPoint point, {
    required String date,
  }) async => _answer(date);
}

WeatherReport _report(int temp, {String type = 'forecast'}) =>
    WeatherReport.fromJson({
      'temp': temp,
      'main': 'Clear',
      'description': 'Clear sky',
      'type': type,
    });

void main() {
  late _FakeWeatherApi api;
  late InMemoryWeatherLocalStore localStore;
  late WeatherRepository repository;

  const point = GeoPoint(48.86, 2.35);

  setUp(() {
    api = _FakeWeatherApi();
    localStore = InMemoryWeatherLocalStore();
    repository = WeatherRepository(weatherApi: api, localStore: localStore);
  });

  group('report', () {
    test('fetches, caches, and returns when nothing is cached', () async {
      final snapshot = await repository.report(point, date: '2026-09-10');

      expect(snapshot.fromCache, isFalse);
      expect(snapshot.report.temp, 15);
      expect(
        localStore.entries['48.86_2.35_2026-09-10'],
        isNotNull,
        reason: 'the answer is written to the cache',
      );
    });

    test('serves a fresh cache entry without hitting the network', () async {
      localStore.entries['48.86_2.35_2026-09-10'] = _report(20);

      final snapshot = await repository.report(point, date: '2026-09-10');

      expect(snapshot.fromCache, isTrue);
      expect(snapshot.stale, isFalse);
      expect(snapshot.report.temp, 20);
      expect(api.calls, 0);
    });

    test('forceRefresh bypasses a fresh cache entry', () async {
      localStore.entries['48.86_2.35_2026-09-10'] = _report(20);

      final snapshot = await repository.report(
        point,
        date: '2026-09-10',
        forceRefresh: true,
      );

      expect(snapshot.fromCache, isFalse);
      expect(api.calls, 1);
    });

    test('falls back to a stale cache entry when the network fails', () async {
      localStore.entries['48.86_2.35_2026-09-10'] = _report(9);
      localStore.staleKeys.add('48.86_2.35_2026-09-10');
      api.byDate['2026-09-10'] = null; // offline

      final snapshot = await repository.report(point, date: '2026-09-10');

      expect(snapshot.fromCache, isTrue);
      expect(snapshot.stale, isTrue);
      expect(snapshot.report.temp, 9);
    });

    test('rethrows when offline and nothing is cached', () async {
      api.byDate['2026-09-10'] = null;

      expect(
        () => repository.report(point, date: '2026-09-10'),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('forecast', () {
    test('returns one entry per requested day', () async {
      final forecast = await repository.forecast(
        point,
        start: DateTime(2026, 9, 1),
        days: 5,
      );

      expect(forecast.days, hasLength(5));
      expect(forecast.days.first.date, DateTime.utc(2026, 9, 1));
      expect(forecast.days.last.date, DateTime.utc(2026, 9, 5));
      expect(forecast.isPartial, isFalse);
    });

    test('clamps the span to the forecast horizon', () async {
      final forecast = await repository.forecast(
        point,
        start: DateTime(2026, 9, 1),
        days: 60,
      );

      expect(forecast.days, hasLength(WeatherRepository.maxForecastDays));
    });

    test('degrades per-day: offline days with no cache become null', () async {
      // Day 2 has a stale cache entry; day 3 is offline with nothing cached.
      localStore.entries['48.86_2.35_2026-09-02'] = _report(11);
      localStore.staleKeys.add('48.86_2.35_2026-09-02');
      api.byDate['2026-09-02'] = null;
      api.byDate['2026-09-03'] = null;

      final forecast = await repository.forecast(
        point,
        start: DateTime(2026, 9, 1),
        days: 3,
      );

      expect(forecast.days[0].weather?.report.temp, 15);
      expect(forecast.days[1].weather?.stale, isTrue);
      expect(forecast.days[1].weather?.report.temp, 11);
      expect(forecast.days[2].weather, isNull);
      expect(forecast.isPartial, isTrue);
    });
  });

  test('cachedReport reads the local store without a fetch', () async {
    localStore.entries['48.86_2.35_current'] = _report(7, type: 'current');

    final report = await repository.cachedReport(point);

    expect(report?.temp, 7);
    expect(api.calls, 0);
  });
}
