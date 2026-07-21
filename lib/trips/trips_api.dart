import '../network/api_client.dart';
import 'trip.dart';

/// Read-only wrapper around the trip-list endpoint. Trek wraps every list
/// response in an object keyed by the plural resource name (`{ trips:
/// [...] }`), never a bare array — confirmed live, not guessed.
class TripsApi {
  TripsApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<Trip>> listTrips() async {
    final response = await _apiClient.get('/api/trips') as Map<String, dynamic>;
    final tripsJson = response['trips'] as List<dynamic>? ?? const [];
    return tripsJson
        .map((json) => Trip.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
