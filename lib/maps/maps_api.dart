import '../network/api_client.dart';
import 'maps_models.dart';

/// Wraps Trek's maps/geocoding endpoints. Both are JWT-guarded
/// (`MapsController`), so this uses the authenticated [ApiClient].
///
/// A thin transport layer: no caching, no offline handling —
/// [MapsRepository] is the offline-first front door screens use. See
/// docs/maps.md.
class MapsApi {
  MapsApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  static const _language = 'en';

  /// `GET /api/maps/reverse?lat=&lng=&lang=`. `lat`/`lng` go as strings — the
  /// server's query schema (`mapsReverseQuerySchema`) declares them as
  /// strings, not numbers. A missing lat/lng 400s as a [ValidationException];
  /// a geocoder miss comes back 200 with nulls (see [ReverseGeocodeResult]),
  /// it does not throw.
  Future<ReverseGeocodeResult> reverseGeocode(LatLng point) async {
    final response =
        await _apiClient.get(
              '/api/maps/reverse',
              query: {
                'lat': point.lat.toString(),
                'lng': point.lng.toString(),
                'lang': _language,
              },
            )
            as Map<String, dynamic>;
    return ReverseGeocodeResult.fromJson(response);
  }

  /// `POST /api/maps/resolve-url { url }`. A URL that doesn't resolve to a
  /// place 400s as a [ValidationException] (`MapsController.resolveUrl`).
  Future<ResolvedPlace> resolveUrl(String url) async {
    final response =
        await _apiClient.post('/api/maps/resolve-url', body: {'url': url})
            as Map<String, dynamic>;
    return ResolvedPlace.fromJson(response);
  }
}
