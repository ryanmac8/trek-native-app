import '../network/api_client.dart';
import 'vacay_models.dart';

/// Wraps the read endpoints of Trek's Vacay addon (`VacayController` under
/// `/api/addons/vacay`, JWT-guarded, no addon gate), using the
/// authenticated [ApiClient] (`apiClientProvider`). Every endpoint acts on
/// the signed-in user's *active* plan — their own, or the plan they've
/// joined.
///
/// This is a thin transport layer: it does no caching and no offline
/// handling — [VacayRepository] is the offline-first front door screens
/// use. See docs/vacay.md.
class VacayApi {
  VacayApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  static const _base = '/api/addons/vacay';

  /// `GET /plan` + `GET /years` → the plan overview. `GET /plan` creates
  /// the user's own plan (seeded with the current year) on first use.
  Future<VacayPlan> fetchPlan() async {
    // Future.wait rethrows the first failure as-is, so callers still see
    // the typed ApiException (e.g. NetworkException).
    final [plan, years] = await Future.wait([
      _apiClient.get('$_base/plan'),
      _apiClient.get('$_base/years'),
    ]);
    return VacayPlan.fromJson(
      plan as Map<String, dynamic>,
      (years as Map<String, dynamic>)['years'] as List? ?? const [],
    );
  }

  /// `GET /stats/:year` + `GET /entries/:year` → one tracked year.
  Future<VacayYear> fetchYear(int year) async {
    final [stats, entries] = await Future.wait([
      _apiClient.get('$_base/stats/$year'),
      _apiClient.get('$_base/entries/$year'),
    ]);
    return VacayYear.fromJson(
      year,
      (stats as Map<String, dynamic>)['stats'] as List? ?? const [],
      entries as Map<String, dynamic>,
    );
  }
}
