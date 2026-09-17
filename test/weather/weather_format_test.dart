import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/weather/weather_format.dart';
import 'package:trek/weather/weather_models.dart';

WeatherReport _report(Map<String, dynamic> overrides) =>
    WeatherReport.fromJson({
      'temp': 18,
      'main': 'Clear',
      'description': 'Clear sky',
      'type': 'forecast',
      ...overrides,
    });

void main() {
  test('weatherIcon covers every condition bucket', () {
    for (final condition in WeatherCondition.values) {
      expect(weatherIcon(condition), isA<IconData>());
    }
    expect(weatherIcon(WeatherCondition.clear), Icons.wb_sunny_outlined);
    expect(weatherIcon(WeatherCondition.snow), Icons.ac_unit_outlined);
  });

  test('formatTemp appends a Celsius sign', () {
    expect(formatTemp(-3), '-3°C');
  });

  group('formatRange', () {
    test('shows high / low when both are present', () {
      expect(
        formatRange(_report({'temp_max': 24, 'temp_min': 15})),
        '24° / 15°',
      );
    });

    test('falls back to the single temp for current conditions', () {
      expect(formatRange(_report({'temp': 12, 'type': 'current'})), '12°C');
    });
  });

  group('formatForecastDay', () {
    final reference = DateTime(2026, 9, 1); // a Tuesday

    test('labels today and tomorrow', () {
      expect(
        formatForecastDay(DateTime(2026, 9, 1), reference: reference),
        'Today',
      );
      expect(
        formatForecastDay(DateTime(2026, 9, 2), reference: reference),
        'Tomorrow',
      );
    });

    test('labels later days with weekday and date', () {
      expect(
        formatForecastDay(DateTime(2026, 9, 4), reference: reference),
        'Fri 4 Sep',
      );
    });
  });

  group('weatherQualifier', () {
    test('names a missing forecast', () {
      expect(
        weatherQualifier(_report({'type': '', 'error': 'no_forecast'})),
        'No forecast available',
      );
    });

    test('names a climate estimate', () {
      expect(
        weatherQualifier(_report({'type': 'climate'})),
        'Seasonal average',
      );
    });

    test('is null for a plain forecast', () {
      expect(weatherQualifier(_report({})), isNull);
    });
  });
}
