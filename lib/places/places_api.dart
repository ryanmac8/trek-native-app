import '../network/api_client.dart';
import 'place.dart';

/// Thin wrapper around `GET /api/trips/:tripId/places`. Confirmed live
/// against Trek's actual `PlacesController`: the response is
/// `{ places: [...] }` (never a bare array), matching the same wrapped-list
/// convention as `/api/trips` and `/api/trips/:tripId/days`.
class PlacesApi {
  PlacesApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<Place>> listPlaces(String tripId) async {
    final response =
        await _apiClient.get('/api/trips/$tripId/places')
            as Map<String, dynamic>;
    final placesJson = response['places'] as List<dynamic>? ?? const [];
    return placesJson
        .map((json) => Place.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
