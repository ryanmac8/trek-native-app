import '../../network/api_client.dart';

/// What `GET /api/trip-invites/:token` reveals about an invite before the
/// user accepts it.
class TripInvitePreview {
  const TripInvitePreview({required this.tripId, required this.title});

  factory TripInvitePreview.fromJson(Map<String, dynamic> json) =>
      TripInvitePreview(
        tripId: (json['trip_id'] as num).toInt(),
        title: json['title'] as String? ?? '',
      );

  final int tripId;
  final String title;
}

/// The result of `POST /api/trip-invites/:token/accept`. [joined] is `false`
/// when the user already had access (owner or existing member) — the join
/// is idempotent server-side, so that's still a success.
class TripInviteAcceptance {
  const TripInviteAcceptance({required this.tripId, required this.joined});

  factory TripInviteAcceptance.fromJson(Map<String, dynamic> json) =>
      TripInviteAcceptance(
        tripId: (json['trip_id'] as num).toInt(),
        joined: json['joined'] as bool? ?? false,
      );

  final int tripId;
  final bool joined;
}

/// Trek's trip-invite endpoints for the invited user (JWT-guarded). An
/// unknown, rotated, disabled, or expired token is a 404 with
/// `{ "error": "Invalid or expired invite link" }`; both endpoints are
/// rate-limited per IP (429).
class TripInviteApi {
  const TripInviteApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<TripInvitePreview> preview(String token) async {
    final json = await _apiClient.get(_path(token));
    return TripInvitePreview.fromJson(json as Map<String, dynamic>);
  }

  Future<TripInviteAcceptance> accept(String token) async {
    final json = await _apiClient.post('${_path(token)}/accept');
    return TripInviteAcceptance.fromJson(json as Map<String, dynamic>);
  }

  String _path(String token) =>
      '/api/trip-invites/${Uri.encodeComponent(token)}';
}
