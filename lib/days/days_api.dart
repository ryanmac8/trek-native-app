import '../network/api_client.dart';
import 'day.dart';
import 'day_note.dart';

/// Thin wrapper around `GET /api/trips/:tripId/days`. Confirmed live against
/// Trek's actual `DaysController`: the response is `{ days: [...] }` (never
/// a bare array), matching the same wrapped-list convention as `/api/trips`.
///
/// Day notes live under `/api/trips/:tripId/days/:dayId/notes`: `POST`
/// creates (`{ note }`, 201), `PUT /:id` partially updates (`{ note }`), and
/// `DELETE /:id` removes (`{ success: true }`). All three need the trip's
/// `day_edit` permission (403 otherwise); an unknown day or note is a 404.
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

  /// [fields] uses the request body's wire names (`text`, `time`, `icon`,
  /// `color`); `text` is required and must be non-blank.
  Future<DayNote> createDayNote(
    String tripId,
    int dayId,
    Map<String, Object?> fields,
  ) async {
    final response =
        await _apiClient.post(
              '/api/trips/$tripId/days/$dayId/notes',
              body: fields,
            )
            as Map<String, dynamic>;
    return DayNote.fromJson(response['note'] as Map<String, dynamic>);
  }

  /// Only the keys present in [fields] change; an explicit `null` clears
  /// `time`/`icon`/`color`.
  Future<DayNote> updateDayNote(
    String tripId,
    int dayId,
    int noteId,
    Map<String, Object?> fields,
  ) async {
    final response =
        await _apiClient.put(
              '/api/trips/$tripId/days/$dayId/notes/$noteId',
              body: fields,
            )
            as Map<String, dynamic>;
    return DayNote.fromJson(response['note'] as Map<String, dynamic>);
  }

  Future<void> deleteDayNote(String tripId, int dayId, int noteId) async {
    await _apiClient.delete('/api/trips/$tripId/days/$dayId/notes/$noteId');
  }
}
