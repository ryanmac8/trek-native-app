import 'package:flutter_test/flutter_test.dart';
import 'package:trek/weather/weather_models.dart';

void main() {
  group('WeatherReport.fromJson', () {
    test('parses a forecast answer with a high/low range', () {
      final report = WeatherReport.fromJson({
        'temp': 17,
        'temp_max': 21,
        'temp_min': 12,
        'main': 'Rain',
        'description': 'Light rain',
        'type': 'forecast',
        'precipitation_sum': 4.2,
        'precipitation_probability_max': 80,
        'wind_max': 19.0,
      });

      expect(report.temp, 17);
      expect(report.tempMax, 21);
      expect(report.tempMin, 12);
      expect(report.kind, WeatherKind.forecast);
      expect(report.conditionBucket, WeatherCondition.rain);
      expect(report.precipitationProbabilityMax, 80);
      expect(report.isMissing, isFalse);
      expect(report.isEstimate, isFalse);
    });

    test('treats the no_forecast sentinel as missing', () {
      final report = WeatherReport.fromJson({
        'temp': 0,
        'main': '',
        'description': '',
        'type': '',
        'error': 'no_forecast',
      });

      expect(report.isMissing, isTrue);
      expect(report.kind, WeatherKind.unknown);
      expect(report.conditionBucket, WeatherCondition.unknown);
    });

    test('flags a climate answer as an estimate', () {
      final report = WeatherReport.fromJson({
        'temp': 24,
        'temp_max': 29,
        'temp_min': 19,
        'main': 'Clear',
        'description': '',
        'type': 'climate',
      });

      expect(report.isEstimate, isTrue);
      expect(report.isMissing, isFalse);
    });

    test('parses the hourly series from the detailed endpoint', () {
      final report = WeatherReport.fromJson({
        'temp': 15,
        'main': 'Clouds',
        'description': 'Overcast',
        'type': 'forecast',
        'sunrise': '05:12',
        'sunset': '21:40',
        'hourly': [
          {
            'hour': 9,
            'temp': 13,
            'precipitation': 0.0,
            'precipitation_probability': 10,
            'main': 'Clouds',
            'wind': 8,
            'humidity': 72,
          },
        ],
      });

      expect(report.sunrise, '05:12');
      expect(report.hourly, hasLength(1));
      expect(report.hourly!.single.hour, 9);
      expect(report.hourly!.single.conditionBucket, WeatherCondition.clouds);
    });
  });

  test('WeatherReport round-trips through JSON', () {
    final original = WeatherReport.fromJson({
      'temp': 8,
      'temp_max': 10,
      'temp_min': 5,
      'main': 'Snow',
      'description': 'Light snowfall',
      'type': 'forecast',
      'wind_max': 22.0,
      'hourly': [
        {
          'hour': 0,
          'temp': 6,
          'precipitation': 1.2,
          'precipitation_probability': 60,
          'main': 'Snow',
          'wind': 12,
          'humidity': 90,
        },
      ],
    });

    final restored = WeatherReport.fromJson(original.toJson());

    expect(restored.temp, original.temp);
    expect(restored.tempMax, original.tempMax);
    expect(restored.condition, 'Snow');
    expect(restored.kind, WeatherKind.forecast);
    expect(restored.hourly!.single.temp, 6);
  });

  test('WeatherKind.unknown serialises back to an empty string', () {
    expect(WeatherKind.unknown.wireValue, '');
    expect(WeatherKind.forecast.wireValue, 'forecast');
  });

  group('WeatherCondition.parse', () {
    test('is case-insensitive and buckets mist/haze as fog', () {
      expect(WeatherCondition.parse('CLEAR'), WeatherCondition.clear);
      expect(WeatherCondition.parse('Mist'), WeatherCondition.fog);
      expect(WeatherCondition.parse('haze'), WeatherCondition.fog);
      expect(WeatherCondition.parse(null), WeatherCondition.unknown);
      expect(WeatherCondition.parse('tornado'), WeatherCondition.unknown);
    });
  });

  group('GeoPoint', () {
    test('cacheKey rounds to two decimals, matching the server', () {
      expect(const GeoPoint(64.14589, -21.94236).cacheKey, '64.15_-21.94');
    });

    test('round-trips and compares by value', () {
      final json = const GeoPoint(1.5, -2.5).toJson();
      expect(GeoPoint.fromJson(json), const GeoPoint(1.5, -2.5));
    });
  });

  test('TravelDestination round-trips with an inline lat/lng', () {
    const destination = TravelDestination(
      name: 'Reykjavík',
      country: 'Iceland',
      point: GeoPoint(64.15, -21.94),
    );

    final restored = TravelDestination.fromJson(destination.toJson());

    expect(restored.label, 'Reykjavík, Iceland');
    expect(restored.point, const GeoPoint(64.15, -21.94));
  });
}
