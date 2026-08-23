/// A trip's shared collab note, as returned by
/// `GET /api/trips/:tripId/collab/notes` /
/// `POST /api/trips/:tripId/collab/notes`, plus the fields needed to track
/// an offline-created note until it syncs (see [CollabRepository] in
/// `collab_repository.dart`).
///
/// The real response also carries `website`, `attachments` (uploaded
/// files), `avatar_url`, and `updated_at` — confirmed against Trek's actual
/// `collab_notes` schema and `CollabController`/`collabService.ts`
/// (`server/src/nest/collab/`, `server/src/services/collabService.ts`).
/// This first slice of issue #13 only needs what the list row renders:
/// title, content, category, color, pinned, and the author's username.
/// Editing, pinning, file attachments, polls, chat, and membership are a
/// follow-up once this exists to attach them to.
///
/// [id] is null exactly when the note was created locally while offline
/// and hasn't been confirmed by the server yet ([isPending]). [localId] is
/// a stable client-generated key that survives that transition — used to
/// find and replace the pending entry in the local cache once the create
/// syncs, the same shape as [TodoItem].
class CollabNote {
  const CollabNote({
    this.id,
    required this.localId,
    required this.tripId,
    required this.title,
    this.content,
    this.category,
    this.color,
    this.pinned = false,
    this.authorUsername,
  });

  final int? id;
  final String localId;
  final String tripId;
  final String title;
  final String? content;
  final String? category;
  final String? color;
  final bool pinned;
  final String? authorUsername;

  /// True for a note created locally that hasn't been confirmed by the
  /// server yet — either still queued (offline) or its create request is
  /// in flight. See [CollabRepository.createNote].
  bool get isPending => id == null;

  factory CollabNote.fromJson(
    Map<String, dynamic> json, {
    required String tripId,
  }) {
    final id = json['id'] as int;
    return CollabNote(
      id: id,
      localId: 'server-$id',
      tripId: tripId,
      title: json['title'] as String,
      content: json['content'] as String?,
      category: json['category'] as String?,
      color: json['color'] as String?,
      pinned: _asBool(json['pinned']),
      authorUsername: json['username'] as String?,
    );
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return false;
  }

  /// Round-trips a [CollabNote] through the local cache (see
  /// `PreferencesCollabLocalStore`) — unlike [fromJson]/the real API shape,
  /// this must also carry [id] being absent (a still-pending note) and the
  /// client-generated [localId].
  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'local_id': localId,
    'trip_id': tripId,
    'title': title,
    'content': content,
    'category': category,
    'color': color,
    'pinned': pinned,
    'author_username': authorUsername,
  };

  factory CollabNote.fromCacheJson(Map<String, dynamic> json) {
    return CollabNote(
      id: json['id'] as int?,
      localId: json['local_id'] as String,
      tripId: json['trip_id'] as String,
      title: json['title'] as String,
      content: json['content'] as String?,
      category: json['category'] as String?,
      color: json['color'] as String?,
      pinned: json['pinned'] as bool? ?? false,
      authorUsername: json['author_username'] as String?,
    );
  }
}
