import '../network/api_client.dart';
import 'todo_item.dart';

/// Thin wrapper around `GET /api/trips/:tripId/todo`,
/// `POST /api/trips/:tripId/todo`, and the `checked` slice of
/// `PUT /api/trips/:tripId/todo/:id`. Confirmed live against Trek's actual
/// `TodoController`: list/create/update responses are all wrapped
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

  /// `PUT /api/trips/:tripId/todo/:id`. The server also accepts updating
  /// `name`, `category`, `due_date`, `description`, `assigned_user_id`, and
  /// `priority` here, but this slice only ever sends `checked`. A missing
  /// item surfaces as the server's 404 `{ error: 'Item not found' }`.
  Future<TodoItem> updateChecked(
    String tripId, {
    required int id,
    required bool checked,
  }) async {
    final response =
        await _apiClient.put(
              '/api/trips/$tripId/todo/$id',
              body: {'checked': checked},
            )
            as Map<String, dynamic>;
    return TodoItem.fromJson(
      response['item'] as Map<String, dynamic>,
      tripId: tripId,
    );
  }

  /// `DELETE /api/trips/:tripId/todo/:id`. A missing item surfaces as the
  /// server's 404 `{ error: 'Item not found' }`, same as [updateChecked].
  Future<void> deleteItem(String tripId, {required int id}) async {
    await _apiClient.delete('/api/trips/$tripId/todo/$id');
  }
}
