/// A per-user place tag, as returned by `GET /api/tags` / `POST /api/tags`,
/// plus the fields needed to track an offline-created tag until it syncs
/// (see [TagsRepository] in `tags_repository.dart`).
///
/// Unlike [Place]'s category, tags are scoped to the user, not a trip —
/// confirmed against Trek's real `tagSchema`/`TagsController`
/// (`server/src/nest/tags/`).
///
/// [id] is null exactly when the tag was created locally while offline and
/// hasn't been confirmed by the server yet ([isPending]). [localId] is a
/// stable client-generated key that survives that transition — used to find
/// and replace the pending entry in the local cache once the create syncs,
/// without depending on the server id existing yet. Mirrors [Trip]'s
/// pending-write shape.
class Tag {
  const Tag({this.id, required this.localId, required this.name, this.color});

  final int? id;
  final String localId;
  final String name;

  /// A hex color string (e.g. `#10b981`), matching Trek's per-tag `color`
  /// column. Server-side default is `#10b981` when omitted on create.
  final String? color;

  /// True for a tag created locally that hasn't been confirmed by the
  /// server yet — either still queued (offline) or its create request is in
  /// flight. See [TagsRepository.createTag].
  bool get isPending => id == null;

  factory Tag.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as int;
    return Tag(
      id: id,
      localId: 'server-$id',
      name: json['name'] as String,
      color: json['color'] as String?,
    );
  }

  /// Round-trips a [Tag] through the local cache (see
  /// `PreferencesTagsLocalStore`) — unlike [fromJson]/the real API shape,
  /// this must also carry [id] being absent (a still-pending tag) and the
  /// client-generated [localId].
  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'local_id': localId,
    'name': name,
    'color': color,
  };

  factory Tag.fromCacheJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'] as int?,
      localId: json['local_id'] as String,
      name: json['name'] as String,
      color: json['color'] as String?,
    );
  }
}
