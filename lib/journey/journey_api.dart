import '../network/api_client.dart';
import 'journey_models.dart';

/// Wraps the read endpoints of Trek's Journey addon (`JourneyController`
/// under `/api/journeys`), using the authenticated [ApiClient]
/// (`apiClientProvider`). The routes are JWT-guarded and gated on the
/// Journey addon: with the addon disabled every route answers
/// `404 { error: 'Journey addon is not enabled' }`.
///
/// This is a thin transport layer: it does no caching and no offline
/// handling — [JourneyRepository] is the offline-first front door screens
/// use. See docs/journey.md.
class JourneyApi {
  JourneyApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  static const _base = '/api/journeys';

  /// `GET /api/journeys` → journeys the user owns or contributes to.
  Future<JourneyList> fetchJourneys() async {
    final json = await _apiClient.get(_base);
    return JourneyList.fromJson(json as Map<String, dynamic>);
  }

  /// `GET /api/journeys/:id` → one journey with entries, trips,
  /// contributors, and stats. 404 when the journey doesn't exist or the
  /// user can't access it.
  Future<JourneyDetail> fetchJourney(int id) async {
    final json = await _apiClient.get('$_base/$id');
    return JourneyDetail.fromJson(json as Map<String, dynamic>);
  }
}
