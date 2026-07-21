import '../network/api_client.dart';
import 'day.dart';

/// Thin wrapper around `GET /api/trips/:tripId/days`. Confirmed live against
/// Trek's actual `DaysController`: the response is `{ days: [...] }` (never
/// a bare array), matching the same wrapped-list convention as `/api/trips`.
class DaysApi {
  DaysApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<Day>> listDays(String tripId) async {
    final response =
        await _apiClient.get('/api/trips/$tripId/days') as Map<String, dynamic>;
    final daysJson = response['days'] as List<dynamic>? ?? const [];
    return daysJson
        .map((json) => Day.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
