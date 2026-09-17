import '../network/api_client.dart';
import 'weather_models.dart';

/// Wraps Trek's weather endpoints. Both are JWT-guarded (`WeatherController`),
/// so this uses the authenticated [ApiClient] (`apiClientProvider`).
///
/// A thin transport layer: no caching, no offline handling — [WeatherRepository]
/// is the offline-first front door screens use. See docs/weather.md.
///
/// `lang` is pinned to `en`: the server defaults it to `de` when the param is
/// absent, and this app has no locale system yet.
class WeatherApi {
  WeatherApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  static const _language = 'en';

  /// `GET /api/weather?lat=&lng=&date=&lang=` — current conditions when [date]
  /// is null, otherwise the forecast (or a historical-average estimate) for
  /// that `YYYY-MM-DD`.
  ///
  /// The server 400s if [point] somehow serialises without lat/lng, which
  /// surfaces as a [ValidationException]; a provider with no data for the
  /// coordinate/date returns `200` with [WeatherReport.isMissing] set rather
  /// than throwing.
  Future<WeatherReport> fetch(GeoPoint point, {String? date}) async {
    final response =
        await _apiClient.get(
              '/api/weather',
              query: {
                'lat': point.lat,
                'lng': point.lng,
                'lang': _language,
                'date': ?date,
              },
            )
            as Map<String, dynamic>;
    return WeatherReport.fromJson(response);
  }

  /// `GET /api/weather/detailed?lat=&lng=&date=&lang=` — same shape as [fetch]
  /// plus an hourly series. [date] is required here (the server 400s without
  /// one).
  Future<WeatherReport> fetchDetailed(
    GeoPoint point, {
    required String date,
  }) async {
    final response =
        await _apiClient.get(
              '/api/weather/detailed',
              query: {
                'lat': point.lat,
                'lng': point.lng,
                'date': date,
                'lang': _language,
              },
            )
            as Map<String, dynamic>;
    return WeatherReport.fromJson(response);
  }
}
