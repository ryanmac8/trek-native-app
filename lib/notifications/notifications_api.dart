import '../network/api_client.dart';
import 'trek_notification.dart';

/// One page of the signed-in user's in-app notifications, plus the counts
/// the list header needs.
class InAppNotificationsPage {
  const InAppNotificationsPage({
    required this.notifications,
    required this.total,
    required this.unreadCount,
  });

  final List<TrekNotification> notifications;

  /// Total notifications for the user server-side (for "load more" — not
  /// used yet, this slice fetches only the first page).
  final int total;

  /// Unread count server-side, which can exceed the unread rows on this
  /// page.
  final int unreadCount;
}

/// Wraps Trek's `/api/notifications/in-app` endpoints. Confirmed against
/// `NotificationsController` (`server/src/nest/notifications/`):
///
/// - `GET /api/notifications/in-app?limit=&offset=&unread_only=` →
///   `{ notifications: [...], total, unread_count }`. `limit` is clamped
///   server-side to 50 (default 20).
/// - `PUT /api/notifications/in-app/:id/read` → `{ success: true }`, or
///   `404 { error: 'Not found' }` if the id isn't the caller's.
/// - `PUT /api/notifications/in-app/read-all` → `{ success: true, count }`.
///
/// All are JWT-guarded, so this needs the authenticated `ApiClient`.
class NotificationsApi {
  NotificationsApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<InAppNotificationsPage> listInApp({
    int limit = 20,
    int offset = 0,
    bool unreadOnly = false,
  }) async {
    final response =
        await _apiClient.get(
              '/api/notifications/in-app',
              query: {
                'limit': limit,
                'offset': offset,
                if (unreadOnly) 'unread_only': true,
              },
            )
            as Map<String, dynamic>;

    final rows = response['notifications'] as List<dynamic>? ?? const [];
    return InAppNotificationsPage(
      notifications: rows
          .map((e) => TrekNotification.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (response['total'] as num?)?.toInt() ?? rows.length,
      unreadCount: (response['unread_count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> markRead(int id) async {
    await _apiClient.put('/api/notifications/in-app/$id/read');
  }

  Future<void> markAllRead() async {
    await _apiClient.put('/api/notifications/in-app/read-all');
  }
}
