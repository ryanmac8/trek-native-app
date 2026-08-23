import '../network/api_client.dart';
import 'collab_note.dart';

/// Thin wrapper around the notes slice of
/// `GET`/`POST /api/trips/:tripId/collab/notes`. Confirmed live against
/// Trek's actual `CollabController`: list/create responses are both
/// wrapped (`{ notes: [...] }` / `{ note }`), the same convention as
/// `/api/trips/:tripId/todo`.
class CollabApi {
  CollabApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<CollabNote>> listNotes(String tripId) async {
    final response =
        await _apiClient.get('/api/trips/$tripId/collab/notes')
            as Map<String, dynamic>;
    final notesJson = response['notes'] as List<dynamic>? ?? const [];
    return notesJson
        .map(
          (json) =>
              CollabNote.fromJson(json as Map<String, dynamic>, tripId: tripId),
        )
        .toList();
  }

  /// `POST /api/trips/:tripId/collab/notes`. Only [title] is required — the
  /// server also accepts `pinned` and `website`, neither of which this
  /// first slice sends.
  Future<CollabNote> createNote(
    String tripId, {
    required String title,
    String? content,
    String? category,
    String? color,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      if (content != null && content.isNotEmpty) 'content': content,
      if (category != null && category.isNotEmpty) 'category': category,
      if (color != null && color.isNotEmpty) 'color': color,
    };
    final response =
        await _apiClient.post('/api/trips/$tripId/collab/notes', body: body)
            as Map<String, dynamic>;
    return CollabNote.fromJson(
      response['note'] as Map<String, dynamic>,
      tripId: tripId,
    );
  }
}
