import '../network/api_client.dart';
import 'trip.dart';

/// Thin wrapper around the `/api/trips` list + create endpoints. Trek wraps
/// every list response in an object keyed by the plural resource name
/// (`{ trips: [...] }`), never a bare array — confirmed live, not guessed.
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

  /// `POST /api/trips`. Only [title] is required — the server infers a
  /// missing end date as 6 days after the start date (and vice versa) and
  /// auto-generates the trip's `Day` records from the resulting range, so
  /// none of that is replicated client-side.
  Future<Trip> createTrip({
    required String title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    String? currency,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (startDate != null) 'start_date': _dateStr(startDate),
      if (endDate != null) 'end_date': _dateStr(endDate),
      if (currency != null && currency.isNotEmpty) 'currency': currency,
    };
    final response =
        await _apiClient.post('/api/trips', body: body) as Map<String, dynamic>;
    return Trip.fromJson(response['trip'] as Map<String, dynamic>);
  }

  static String _dateStr(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }
}
