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

  /// `PUT /api/trips/:id` for the editable metadata fields (title,
  /// description, dates, currency) — matches the server's `trip_edit`
  /// permission check, which is separate from `trip_archive`
  /// ([archiveTrip]). Fields are sent unconditionally (including `null`, to
  /// clear an optional one) since this always represents a full save of the
  /// edit form, not a partial patch.
  Future<Trip> updateTrip({
    required int id,
    required String title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    String? currency,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      'description': description,
      'start_date': startDate != null ? _dateStr(startDate) : null,
      'end_date': endDate != null ? _dateStr(endDate) : null,
      'currency': currency,
    };
    final response =
        await _apiClient.put('/api/trips/$id', body: body)
            as Map<String, dynamic>;
    return Trip.fromJson(response['trip'] as Map<String, dynamic>);
  }

  /// `PUT /api/trips/:id` with only `is_archived` — kept separate from
  /// [updateTrip] so archiving never requires the `trip_edit` permission,
  /// only `trip_archive`.
  Future<Trip> archiveTrip({required int id, required bool archived}) async {
    final response =
        await _apiClient.put('/api/trips/$id', body: {'is_archived': archived})
            as Map<String, dynamic>;
    return Trip.fromJson(response['trip'] as Map<String, dynamic>);
  }

  /// `DELETE /api/trips/:id`.
  Future<void> deleteTrip(int id) async {
    await _apiClient.delete('/api/trips/$id');
  }

  static String _dateStr(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }
}
