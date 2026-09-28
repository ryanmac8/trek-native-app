import '../network/api_client.dart';
import 'notification_preferences_models.dart';

/// Wraps Trek's notification preference endpoints (`NotificationsController`,
/// JWT-guarded), so this uses the authenticated [ApiClient]
/// (`apiClientProvider`).
///
/// This is a thin transport layer: it does no caching and no offline
/// handling — [NotificationPreferencesRepository] is the offline-first
/// front door screens use. See docs/notification-preferences.md.
class NotificationPreferencesApi {
  NotificationPreferencesApi({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// `GET /api/notifications/preferences` → the user-scope matrix.
  Future<NotificationPreferencesMatrix> fetch() async {
    final response =
        await _apiClient.get('/api/notifications/preferences')
            as Map<String, dynamic>;
    return NotificationPreferencesMatrix.fromJson(response);
  }

  /// `PUT /api/notifications/preferences` with only the [cells] to change.
  /// The server applies each cell independently (enabled deletes the opt-out
  /// row, disabled upserts it) and answers with the refreshed matrix, so a
  /// partial body leaves every other cell untouched.
  Future<NotificationPreferencesMatrix> update(PreferenceCells cells) async {
    final response =
        await _apiClient.put('/api/notifications/preferences', body: cells)
            as Map<String, dynamic>;
    return NotificationPreferencesMatrix.fromJson(response);
  }
}
