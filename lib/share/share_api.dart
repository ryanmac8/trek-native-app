import '../network/api_client.dart';
import 'share_link.dart';

/// Thin wrapper around `GET`/`POST`/`DELETE /api/trips/:tripId/share-link`.
/// Confirmed live against Trek's actual `TripShareController`
/// (`server/src/nest/share/share.controller.ts`).
class ShareApi {
  ShareApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// Returns `null` when the trip has no share link yet — the server
  /// answers `{ token: null }` rather than a 404, since "not shared" is a
  /// normal state, not an error.
  Future<ShareLink?> getShareLink(String tripId) async {
    final response =
        await _apiClient.get('/api/trips/$tripId/share-link')
            as Map<String, dynamic>;
    if (response['token'] == null) return null;
    return ShareLink.fromJson(response, tripId: tripId);
  }

  /// `POST /api/trips/:tripId/share-link` — creates the trip's share link if
  /// none exists yet, or updates its permissions if one already does (201
  /// vs. 200, both handled the same way here). Unlike [getShareLink], the
  /// response body only carries `{ token }` — not `created_at` or the
  /// permission flags — so the returned [ShareLink] is built from what was
  /// just sent rather than parsed from the response.
  Future<ShareLink> createOrUpdateShareLink(
    String tripId, {
    required bool shareMap,
    required bool shareBookings,
    required bool sharePacking,
    required bool shareBudget,
    required bool shareCollab,
  }) async {
    final body = <String, dynamic>{
      'share_map': shareMap,
      'share_bookings': shareBookings,
      'share_packing': sharePacking,
      'share_budget': shareBudget,
      'share_collab': shareCollab,
    };
    final response =
        await _apiClient.post('/api/trips/$tripId/share-link', body: body)
            as Map<String, dynamic>;
    return ShareLink(
      tripId: tripId,
      token: response['token'] as String,
      shareMap: shareMap,
      shareBookings: shareBookings,
      sharePacking: sharePacking,
      shareBudget: shareBudget,
      shareCollab: shareCollab,
    );
  }

  /// `DELETE /api/trips/:tripId/share-link`. Not id-scoped — a trip has at
  /// most one share link.
  Future<void> deleteShareLink(String tripId) async {
    await _apiClient.delete('/api/trips/$tripId/share-link');
  }
}
