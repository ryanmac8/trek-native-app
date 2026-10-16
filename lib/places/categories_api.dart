import '../network/api_client.dart';
import 'place.dart';

/// Thin wrapper around Trek's `GET /api/categories` (`CategoriesController`)
/// — the server-wide list of place categories, sorted by name. Any
/// authenticated user can list them; creating, editing, and deleting them
/// is admin-only and not wrapped here.
///
/// A row is `{ id, name, color, icon, user_id, created_at }`; the fields
/// a place's embedded category carries (id/name/color/icon) are modeled as
/// [PlaceCategoryRef].
class CategoriesApi {
  CategoriesApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<PlaceCategoryRef>> listCategories() async {
    final response =
        await _apiClient.get('/api/categories') as Map<String, dynamic>;
    final categoriesJson = response['categories'] as List<dynamic>? ?? const [];
    return categoriesJson
        .map((json) => PlaceCategoryRef.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
