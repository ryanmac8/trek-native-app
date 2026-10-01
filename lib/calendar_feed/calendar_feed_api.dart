import '../network/api_client.dart';
import 'calendar_feed.dart';

/// Trek's feed token-management endpoints (`server/src/nest/feeds/`). Every
/// call returns `{ feed_url: string | null }`; the URL is absolute, built
/// from the server's `APP_URL` (or the request host when that's unset).
///
/// The trip-scoped endpoints need the `share_manage` permission (owner by
/// default) — a member without it gets 403.
class CalendarFeedApi {
  CalendarFeedApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<String?> fetch(CalendarFeedScope scope) async =>
      _feedUrl(await _apiClient.get(scope.tokenPath));

  Future<String?> apply(CalendarFeedScope scope, CalendarFeedAction action) {
    final path = scope.tokenPath;
    return switch (action) {
      CalendarFeedAction.enable => _apiClient.post(path).then(_feedUrl),
      CalendarFeedAction.rotate => _apiClient.put(path).then(_feedUrl),
      CalendarFeedAction.disable => _apiClient.delete(path).then(_feedUrl),
    };
  }

  String? _feedUrl(dynamic body) {
    final url = body is Map<String, dynamic> ? body['feed_url'] : null;
    return url is String && url.isNotEmpty ? url : null;
  }
}
