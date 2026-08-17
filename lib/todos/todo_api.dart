import '../network/api_client.dart';
import 'todo_item.dart';

/// Thin wrapper around `GET /api/trips/:tripId/todo` and
/// `POST /api/trips/:tripId/todo`. Confirmed live against Trek's actual
/// `TodoController`: both the list and create responses are wrapped
/// (`{ items: [...] }` / `{ item }`), the same convention as
/// `/api/trips/:tripId/packing` and `/api/trips/:tripId/budget`. Note the
/// route is singular `todo`, not `todos`.
class TodoApi {
  TodoApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<TodoItem>> listItems(String tripId) async {
    final response =
        await _apiClient.get('/api/trips/$tripId/todo') as Map<String, dynamic>;
    final itemsJson = response['items'] as List<dynamic>? ?? const [];
    return itemsJson
        .map(
          (json) =>
              TodoItem.fromJson(json as Map<String, dynamic>, tripId: tripId),
        )
        .toList();
  }

  /// `POST /api/trips/:tripId/todo`. Only [name] is required — the server
  /// also accepts `due_date`, `description`, `assigned_user_id`, and
  /// `priority`, none of which this first slice sends.
  Future<TodoItem> createItem(
    String tripId, {
    required String name,
    String? category,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      if (category != null && category.isNotEmpty) 'category': category,
    };
    final response =
        await _apiClient.post('/api/trips/$tripId/todo', body: body)
            as Map<String, dynamic>;
    return TodoItem.fromJson(
      response['item'] as Map<String, dynamic>,
      tripId: tripId,
    );
  }
}
