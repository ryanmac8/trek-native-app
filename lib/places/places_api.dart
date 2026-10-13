import '../network/api_client.dart';
import 'place.dart';

/// Thin wrapper around Trek's `/api/trips/:tripId/places` endpoints
/// (`PlacesController`). Every response wraps its payload — `{ places }` for
/// the list, `{ place }` for create/update — matching the same convention as
/// `/api/trips` and `/api/trips/:tripId/days`.
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

  /// `POST /api/trips/:tripId/places` — [fields] must include a non-empty
  /// `name`. Answers 201 `{ place }`.
  Future<Place> createPlace(String tripId, Map<String, dynamic> fields) async {
    final response =
        await _apiClient.post('/api/trips/$tripId/places', body: fields)
            as Map<String, dynamic>;
    return Place.fromJson(response['place'] as Map<String, dynamic>);
  }

  /// `PUT /api/trips/:tripId/places/:id` — a partial update: keys absent
  /// from [fields] keep their current value server-side. With
  /// [baseUpdatedAt], the server refuses the write with a 409
  /// `ConflictException` if the place has changed since that version.
  Future<Place> updatePlace(
    String tripId,
    int placeId,
    Map<String, dynamic> fields, {
    String? baseUpdatedAt,
  }) async {
    final response =
        await _apiClient.put(
              '/api/trips/$tripId/places/$placeId',
              body: fields,
              headers: baseUpdatedAt != null
                  ? {'X-Base-Updated-At': baseUpdatedAt}
                  : null,
            )
            as Map<String, dynamic>;
    return Place.fromJson(response['place'] as Map<String, dynamic>);
  }

  /// `DELETE /api/trips/:tripId/places/:id` — answers `{ success: true }`.
  Future<void> deletePlace(String tripId, int placeId) async {
    await _apiClient.delete('/api/trips/$tripId/places/$placeId');
  }
}
