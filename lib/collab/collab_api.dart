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

  /// `PUT /api/trips/:tripId/collab/notes/:id`. Confirmed against
  /// `updateNote` in `collabService.ts`: [title] and [category] use
  /// `COALESCE`, so the server silently keeps the old value if either is
  /// sent blank — but [content] checks for the field being present at all,
  /// so it's always sent (even blank) to make clearing it possible, the
  /// one field this slice's edit form can actually clear.
  Future<CollabNote> updateNote(
    String tripId,
    int noteId, {
    required String title,
    String? content,
    String? category,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      'content': content ?? '',
      if (category != null && category.isNotEmpty) 'category': category,
    };
    final response =
        await _apiClient.put(
              '/api/trips/$tripId/collab/notes/$noteId',
              body: body,
            )
            as Map<String, dynamic>;
    return CollabNote.fromJson(
      response['note'] as Map<String, dynamic>,
      tripId: tripId,
    );
  }

  /// `DELETE /api/trips/:tripId/collab/notes/:id`.
  Future<void> deleteNote(String tripId, int noteId) async {
    await _apiClient.delete('/api/trips/$tripId/collab/notes/$noteId');
  }
}
