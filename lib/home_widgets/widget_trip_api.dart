import '../network/api_client.dart';
import 'widget_trip.dart';

/// Reads the signed-in account's trips for the home-screen widget.
class WidgetTripApi {
  WidgetTripApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// `GET /api/trips` — the account's non-archived trips (owned or shared),
  /// returned as `{ trips: [...] }`.
  Future<List<WidgetTrip>> fetchTrips() async {
    final json = await _apiClient.get('/api/trips') as Map<String, dynamic>;
    final trips = json['trips'] as List<dynamic>? ?? const [];
    return [
      for (final trip in trips)
        WidgetTrip.fromJson(trip as Map<String, dynamic>),
    ];
  }
}
