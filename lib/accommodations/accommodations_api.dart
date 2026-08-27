import '../network/api_client.dart';
import 'accommodation.dart';

/// Thin wrapper around `GET /api/trips/:tripId/accommodations`. Confirmed
/// against Trek's actual `AccommodationsController`: the response is
/// `{ accommodations: [...] }` (never a bare array), the same wrapped-list
/// convention as `/api/trips/:tripId/places`, ordered by `created_at` ascending.
/// A trip the caller can't access is `404 { error: 'Trip not found' }`.
class AccommodationsApi {
  AccommodationsApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<Accommodation>> listAccommodations(String tripId) async {
    final response =
        await _apiClient.get('/api/trips/$tripId/accommodations')
            as Map<String, dynamic>;
    final json = response['accommodations'] as List<dynamic>? ?? const [];
    return json
        .map((e) => Accommodation.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
