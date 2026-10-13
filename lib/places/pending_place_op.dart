enum PendingPlaceOpKind { create, update, delete }

/// One local place mutation waiting to reach the server — an entry in a
/// trip's place outbox (see [PlacesRepository]). Persisted in the local store
/// so it survives an app restart while offline.
class PendingPlaceOp {
  const PendingPlaceOp({
    required this.id,
    required this.kind,
    required this.placeId,
    this.fields = const {},
    this.baseUpdatedAt,
    this.conflictServer,
  });

  /// Stable identity for this entry, so a sync step can find "its" op again
  /// after other writes have changed the outbox around it.
  final String id;
  final PendingPlaceOpKind kind;

  /// The target place — a negative temporary id while it still refers to a
  /// place whose create hasn't synced.
  final int placeId;

  /// Request body in Trek's wire format (see `PlaceInput`). Unused for
  /// deletes.
  final Map<String, dynamic> fields;

  /// The `updated_at` this edit was based on, sent as `X-Base-Updated-At` so
  /// the server can refuse it (409) if someone else changed the place since.
  /// `null` sends the update unconditionally.
  final String? baseUpdatedAt;

  /// Set when the server answered 409: its current version of the place.
  /// The op is held back from syncing until the user resolves the conflict.
  final Map<String, dynamic>? conflictServer;

  bool get isConflicted => conflictServer != null;

  PendingPlaceOp copyWith({
    int? placeId,
    Map<String, dynamic>? fields,
    String? baseUpdatedAt,
    Map<String, dynamic>? conflictServer,
    bool clearConflict = false,
  }) {
    return PendingPlaceOp(
      id: id,
      kind: kind,
      placeId: placeId ?? this.placeId,
      fields: fields ?? this.fields,
      baseUpdatedAt: baseUpdatedAt ?? this.baseUpdatedAt,
      conflictServer: clearConflict
          ? null
          : (conflictServer ?? this.conflictServer),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'place_id': placeId,
    'fields': fields,
    'base_updated_at': baseUpdatedAt,
    'conflict_server': conflictServer,
  };

  factory PendingPlaceOp.fromJson(Map<String, dynamic> json) {
    return PendingPlaceOp(
      id: json['id'] as String,
      kind: PendingPlaceOpKind.values.byName(json['kind'] as String),
      placeId: json['place_id'] as int,
      fields: (json['fields'] as Map<String, dynamic>?) ?? const {},
      baseUpdatedAt: json['base_updated_at'] as String?,
      conflictServer: json['conflict_server'] as Map<String, dynamic>?,
    );
  }
}
