import '../network/api_client.dart';
import 'packing_item.dart';

/// Thin wrapper around `GET /api/trips/:tripId/packing` and
/// `POST /api/trips/:tripId/packing`. Confirmed live against Trek's actual
/// `PackingController`: both the list and create responses are wrapped
/// (`{ items: [...] }` / `{ item }`), the same convention as
/// `/api/trips/:tripId/budget` and `/api/trips/:tripId/places`.
class PackingApi {
  PackingApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<PackingItem>> listItems(String tripId) async {
    final response =
        await _apiClient.get('/api/trips/$tripId/packing')
            as Map<String, dynamic>;
    final itemsJson = response['items'] as List<dynamic>? ?? const [];
    return itemsJson
        .map(
          (json) => PackingItem.fromJson(
            json as Map<String, dynamic>,
            tripId: tripId,
          ),
        )
        .toList();
  }

  /// `POST /api/trips/:tripId/packing`. Only [name] is required — the
  /// server falls back to category `'Allgemein'` and `checked: false` when
  /// omitted, so those defaults aren't replicated client-side. Sharing
  /// (`is_private`/`visibility`/`recipient_ids`) isn't sent by this first
  /// slice.
  Future<PackingItem> createItem(
    String tripId, {
    required String name,
    String? category,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      if (category != null && category.isNotEmpty) 'category': category,
    };
    final response =
        await _apiClient.post('/api/trips/$tripId/packing', body: body)
            as Map<String, dynamic>;
    return PackingItem.fromJson(
      response['item'] as Map<String, dynamic>,
      tripId: tripId,
    );
  }
}
