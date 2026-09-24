import '../network/api_client.dart';
import 'atlas_models.dart';

/// Wraps Trek's Atlas stats endpoint (`AtlasController`, JWT-guarded, no
/// addon gate), so this uses the authenticated [ApiClient]
/// (`apiClientProvider`).
///
/// This is a thin transport layer: it does no caching and no offline
/// handling — [AtlasRepository] is the offline-first front door screens
/// use. See docs/atlas.md.
class AtlasApi {
  AtlasApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// `GET /api/addons/atlas/stats` → the signed-in user's travel stats.
  Future<AtlasStats> fetchStats() async {
    final response =
        await _apiClient.get('/api/addons/atlas/stats') as Map<String, dynamic>;
    return AtlasStats.fromJson(response);
  }
}
