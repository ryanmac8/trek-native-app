/// Data types for Trek's weather endpoints.
///
/// Confirmed against Trek's backend (`server/src/nest/weather/`, and the Zod
/// contract in `@trek/shared/weather`):
///
/// - `GET /api/weather?lat=&lng=&date=&lang=&time=` → [WeatherReport]
///   (`WeatherController.getWeather` → `weather.impl.ts:getWeather`). `lat` /
///   `lng` are required; a missing one is `400 { error: 'Latitude and
///   longitude are required' }`. `date` (`YYYY-MM-DD`) is optional — without
///   it the server answers current conditions. `lang` defaults to `de`
///   server-side, so this app always sends `en`.
/// - `GET /api/weather/detailed?lat=&lng=&date=&lang=` → [WeatherReport] with
///   an [WeatherReport.hourly] series. `date` is required here — a missing one
///   is `400 { error: 'Latitude, longitude, and date are required' }`.
///
/// Both endpoints are JWT-guarded (`@UseGuards(JwtAuthGuard)` on
/// `WeatherController`).
///
/// The response is one flat object whose populated fields depend on the
/// request: `type` is `current` / `forecast` / `climate`, and a request the
/// provider has no data for comes back as `{ temp: 0, main: '', description:
/// '', type: '', error: 'no_forecast' }`. The wire shape and the local-cache
/// shape are the same JSON here, so `fromJson` / `toJson` round-trip through
/// [WeatherLocalStore].
library;

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

double? _toDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int _toInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String? _toStringOrNull(Object? value) => value is String ? value : null;

/// Which archive/forecast path the server answered from. `climate` means a
/// historical-average estimate (dates too far out for a real forecast) and is
/// shown with an "average" qualifier; `unknown` is the `type: ''` the server
/// pairs with `error: 'no_forecast'`.
enum WeatherKind {
  current,
  forecast,
  climate,
  unknown;

  static WeatherKind parse(Object? raw) {
    switch (raw) {
      case 'current':
        return WeatherKind.current;
      case 'forecast':
        return WeatherKind.forecast;
      case 'climate':
        return WeatherKind.climate;
      default:
        return WeatherKind.unknown;
    }
  }

  String get wireValue => this == WeatherKind.unknown ? '' : name;
}

/// Trek collapses Open-Meteo's WMO codes into a handful of condition strings
/// (`Clear`, `Clouds`, `Rain`, `Drizzle`, `Snow`, `Fog`, `Thunderstorm`) — see
/// `WMO_MAP` in `weather.impl.ts`. This maps those (case-insensitively) to a
/// stable icon bucket the UI can render; anything unrecognised, including the
/// empty string from a `no_forecast` response, falls to [unknown].
enum WeatherCondition {
  clear,
  clouds,
  rain,
  drizzle,
  snow,
  fog,
  thunderstorm,
  unknown;

  static WeatherCondition parse(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'clear':
        return WeatherCondition.clear;
      case 'clouds':
        return WeatherCondition.clouds;
      case 'rain':
        return WeatherCondition.rain;
      case 'drizzle':
        return WeatherCondition.drizzle;
      case 'snow':
        return WeatherCondition.snow;
      case 'fog':
      case 'mist':
      case 'haze':
        return WeatherCondition.fog;
      case 'thunderstorm':
        return WeatherCondition.thunderstorm;
      default:
        return WeatherCondition.unknown;
    }
  }
}

/// One hour of the [WeatherReport.hourly] series from `/api/weather/detailed`.
class HourlyWeather {
  const HourlyWeather({
    required this.hour,
    required this.temp,
    this.precipitation = 0,
    this.precipitationProbability = 0,
    this.condition = 'Clouds',
    this.wind = 0,
    this.humidity = 0,
  });

  /// Local hour of day, 0–23.
  final int hour;
  final double temp;
  final double precipitation;
  final int precipitationProbability;
  final String condition;
  final double wind;
  final int humidity;

  WeatherCondition get conditionBucket => WeatherCondition.parse(condition);

  factory HourlyWeather.fromJson(Map<String, dynamic> json) {
    return HourlyWeather(
      hour: _toInt(json['hour']),
      temp: _toDouble(json['temp']),
      precipitation: _toDouble(json['precipitation']),
      precipitationProbability: _toInt(json['precipitation_probability']),
      condition: json['main'] as String? ?? 'Clouds',
      wind: _toDouble(json['wind']),
      humidity: _toInt(json['humidity']),
    );
  }

  Map<String, dynamic> toJson() => {
    'hour': hour,
    'temp': temp,
    'precipitation': precipitation,
    'precipitation_probability': precipitationProbability,
    'main': condition,
    'wind': wind,
    'humidity': humidity,
  };
}

/// A weather answer for one coordinate (and optionally one date).
///
/// Field presence mirrors the server: [tempMax] / [tempMin] are absent for
/// current conditions, [sunrise] / [sunset] / [hourly] only come from the
/// detailed endpoint (or a climate estimate), and [isMissing] is true when the
/// provider had no data (`error: 'no_forecast'`).
class WeatherReport {
  const WeatherReport({
    required this.temp,
    required this.condition,
    required this.description,
    required this.kind,
    this.tempMax,
    this.tempMin,
    this.sunrise,
    this.sunset,
    this.precipitationSum,
    this.precipitationProbabilityMax,
    this.windMax,
    this.hourly,
    this.error,
  });

  /// Whole degrees Celsius (the server rounds before sending). For a forecast
  /// this is the mid-point of the day's high and low.
  final int temp;

  /// Raw condition string from the server (`Clear`, `Rain`, …). Use
  /// [conditionBucket] for rendering.
  final String condition;

  /// A localised sentence (`Light rain`, …). Empty for the archive-hourly and
  /// climate paths, which the server sends without a description.
  final String description;

  final WeatherKind kind;

  final int? tempMax;
  final int? tempMin;

  /// `HH:MM` local time, or null when not part of this answer.
  final String? sunrise;
  final String? sunset;

  final double? precipitationSum;
  final int? precipitationProbabilityMax;
  final double? windMax;

  final List<HourlyWeather>? hourly;

  /// The server's error marker — `no_forecast` when it had nothing for this
  /// coordinate/date. Requests that fail outright throw from [WeatherApi]
  /// instead of coming back here.
  final String? error;

  bool get isMissing => error != null || kind == WeatherKind.unknown;

  /// True when this is a historical-average estimate rather than a real
  /// forecast (dates beyond Open-Meteo's ~16-day forecast horizon).
  bool get isEstimate => kind == WeatherKind.climate;

  WeatherCondition get conditionBucket => WeatherCondition.parse(condition);

  factory WeatherReport.fromJson(Map<String, dynamic> json) {
    final hourlyRaw = json['hourly'];
    return WeatherReport(
      temp: _toInt(json['temp']),
      condition: json['main'] as String? ?? '',
      description: json['description'] as String? ?? '',
      kind: WeatherKind.parse(json['type']),
      tempMax: json['temp_max'] == null ? null : _toInt(json['temp_max']),
      tempMin: json['temp_min'] == null ? null : _toInt(json['temp_min']),
      sunrise: _toStringOrNull(json['sunrise']),
      sunset: _toStringOrNull(json['sunset']),
      precipitationSum: _toDoubleOrNull(json['precipitation_sum']),
      precipitationProbabilityMax: json['precipitation_probability_max'] == null
          ? null
          : _toInt(json['precipitation_probability_max']),
      windMax: _toDoubleOrNull(json['wind_max']),
      hourly: hourlyRaw is List
          ? hourlyRaw
                .map((e) => HourlyWeather.fromJson(e as Map<String, dynamic>))
                .toList(growable: false)
          : null,
      error: _toStringOrNull(json['error']),
    );
  }

  Map<String, dynamic> toJson() => {
    'temp': temp,
    'main': condition,
    'description': description,
    'type': kind.wireValue,
    if (tempMax != null) 'temp_max': tempMax,
    if (tempMin != null) 'temp_min': tempMin,
    if (sunrise != null) 'sunrise': sunrise,
    if (sunset != null) 'sunset': sunset,
    if (precipitationSum != null) 'precipitation_sum': precipitationSum,
    if (precipitationProbabilityMax != null)
      'precipitation_probability_max': precipitationProbabilityMax,
    if (windMax != null) 'wind_max': windMax,
    if (hourly != null) 'hourly': hourly!.map((e) => e.toJson()).toList(),
    if (error != null) 'error': error,
  };
}

/// A latitude/longitude pair. The weather endpoints take `lat` / `lng` as
/// separate query params; this groups them for the cache key and the
/// destination list.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  /// Rounded to 2 decimal places — the same precision `cacheKey()` uses
  /// server-side, so two nearby lookups share a cache entry.
  String get cacheKey => '${lat.toStringAsFixed(2)}_${lng.toStringAsFixed(2)}';

  factory GeoPoint.fromJson(Map<String, dynamic> json) =>
      GeoPoint(_toDouble(json['lat']), _toDouble(json['lng']));

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}

/// A named place the weather screen can look up. A small bundled starter set
/// (see `weather_destinations.dart`) stands in until real coordinates arrive
/// from geocoding ([#17](https://github.com/ryanmac8/trek-native-app/issues/17))
/// or a trip's places ([#5](https://github.com/ryanmac8/trek-native-app/issues/5)).
class TravelDestination {
  const TravelDestination({
    required this.name,
    required this.country,
    required this.point,
  });

  final String name;
  final String country;
  final GeoPoint point;

  String get label => '$name, $country';

  factory TravelDestination.fromJson(Map<String, dynamic> json) {
    return TravelDestination(
      name: json['name'] as String? ?? '',
      country: json['country'] as String? ?? '',
      point: GeoPoint.fromJson(json),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'country': country,
    ...point.toJson(),
  };
}
