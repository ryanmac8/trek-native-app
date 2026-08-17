/// A trip's todo-list item, as returned by
/// `GET /api/trips/:tripId/todo` / `POST /api/trips/:tripId/todo`, plus the
/// fields needed to track an offline-created item until it syncs (see
/// [TodoRepository] in `todo_repository.dart`).
///
/// The real response also carries `due_date`, `description`,
/// `assigned_user_id`, `priority`, and `sort_order` — confirmed against
/// Trek's actual `todo_items` schema and `TodoController`/`todoService.ts`
/// (`server/src/nest/todo/`, `server/src/services/todoService.ts`). This
/// first slice of issue #9 only needs what the list row renders: name,
/// category, and checked state — the same scope [PackingItem] started with
/// for issue #8. Due dates, description, assignment, and priority are a
/// follow-up once this exists to attach them to.
///
/// [id] is null exactly when the item was created locally while offline and
/// hasn't been confirmed by the server yet ([isPending]). [localId] is a
/// stable client-generated key that survives that transition — used to find
/// and replace the pending entry in the local cache once the create syncs,
/// mirrors [PackingItem]'s pending-write shape.
class TodoItem {
  const TodoItem({
    this.id,
    required this.localId,
    required this.tripId,
    required this.name,
    this.category,
    this.checked = false,
  });

  final int? id;
  final String localId;
  final String tripId;
  final String name;
  final String? category;
  final bool checked;

  /// True for an item created locally that hasn't been confirmed by the
  /// server yet — either still queued (offline) or its create request is in
  /// flight. See [TodoRepository.createItem].
  bool get isPending => id == null;

  factory TodoItem.fromJson(
    Map<String, dynamic> json, {
    required String tripId,
  }) {
    final id = json['id'] as int;
    return TodoItem(
      id: id,
      localId: 'server-$id',
      tripId: tripId,
      name: json['name'] as String,
      category: json['category'] as String?,
      checked: _asBool(json['checked']),
    );
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return false;
  }

  /// Round-trips a [TodoItem] through the local cache (see
  /// `PreferencesTodoLocalStore`) — unlike [fromJson]/the real API shape,
  /// this must also carry [id] being absent (a still-pending item) and the
  /// client-generated [localId].
  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'local_id': localId,
    'trip_id': tripId,
    'name': name,
    'category': category,
    'checked': checked,
  };

  factory TodoItem.fromCacheJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id'] as int?,
      localId: json['local_id'] as String,
      tripId: json['trip_id'] as String,
      name: json['name'] as String,
      category: json['category'] as String?,
      checked: json['checked'] as bool? ?? false,
    );
  }
}
