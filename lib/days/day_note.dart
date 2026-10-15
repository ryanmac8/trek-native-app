/// A free-text annotation on a day (Trek's `day_notes` table), as nested in
/// `GET /api/trips/:tripId/days` under each day's `notes_items` and returned
/// by the `/api/trips/:tripId/days/:dayId/notes` endpoints (see [DaysApi]).
///
/// A note created offline has no server [id] yet — it's identified by
/// [localId] until its create syncs. [isPending] marks any note whose latest
/// local change (create or edit) hasn't reached the server.
class DayNote {
  const DayNote({
    this.id,
    this.localId,
    required this.dayId,
    required this.text,
    this.time,
    this.icon,
    this.color,
    this.sortOrder = defaultSortOrder,
    this.createdAt,
    this.isPending = false,
  }) : assert(id != null || localId != null);

  /// What the server assigns a note created without an explicit
  /// `sort_order`, which sorts it after everything already on the day.
  static const double defaultSortOrder = 9999;

  /// The icon Trek's web client gives a note when none is picked.
  static const String defaultIcon = 'FileText';

  final int? id;
  final String? localId;
  final int dayId;

  /// The note's title line (required, at most 500 characters).
  final String text;

  /// The note's secondary text (at most 2000 characters). The column is
  /// named `time` server-side; Trek's web client uses it as the note body.
  final String? time;

  /// A lucide icon name from Trek's note icon set (e.g. `FileText`), or a
  /// single emoji (the server's default for notes created without one).
  final String? icon;

  /// One of Trek's note palette colors (`#rrggbb`), or `null` for the
  /// neutral card. The server stores anything outside the palette as `null`.
  final String? color;

  final double sortOrder;
  final String? createdAt;
  final bool isPending;

  /// Stable identity across the local create → server id handover: the
  /// server id once there is one, otherwise the local id.
  String get key => id != null ? '$id' : localId!;

  factory DayNote.fromJson(Map<String, dynamic> json) {
    return DayNote(
      id: json['id'] as int,
      dayId: json['day_id'] as int,
      text: json['text'] as String? ?? '',
      time: json['time'] as String?,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toDouble() ?? 0,
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'local_id': localId,
    'day_id': dayId,
    'text': text,
    'time': time,
    'icon': icon,
    'color': color,
    'sort_order': sortOrder,
    'created_at': createdAt,
    'is_pending': isPending,
  };

  factory DayNote.fromCacheJson(Map<String, dynamic> json) {
    return DayNote(
      id: json['id'] as int?,
      localId: json['local_id'] as String?,
      dayId: json['day_id'] as int,
      text: json['text'] as String? ?? '',
      time: json['time'] as String?,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toDouble() ?? 0,
      createdAt: json['created_at'] as String?,
      isPending: json['is_pending'] as bool? ?? false,
    );
  }

  /// Applies a partial update in the same shape as the `PUT` body — a key
  /// that's present replaces the field (an explicit `null` clears it), an
  /// absent key keeps it, matching the server's own merge rule.
  DayNote withFields(Map<String, Object?> fields, {bool? isPending}) {
    return DayNote(
      id: id,
      localId: localId,
      dayId: dayId,
      text: fields.containsKey('text') ? fields['text'] as String : text,
      time: fields.containsKey('time') ? fields['time'] as String? : time,
      icon: fields.containsKey('icon') ? fields['icon'] as String? : icon,
      color: fields.containsKey('color') ? fields['color'] as String? : color,
      sortOrder: sortOrder,
      createdAt: createdAt,
      isPending: isPending ?? this.isPending,
    );
  }

  /// This note as the server returned it, still carrying [localId] so a
  /// screen holding the pre-sync copy can find it again.
  DayNote withLocalId(String? localId) {
    return DayNote(
      id: id,
      localId: localId,
      dayId: dayId,
      text: text,
      time: time,
      icon: icon,
      color: color,
      sortOrder: sortOrder,
      createdAt: createdAt,
      isPending: isPending,
    );
  }

  /// Whether [other] is the same note, matching on either identity so a
  /// local copy still matches once its create has synced.
  bool sameNoteAs(DayNote other) {
    if (id != null && id == other.id) return true;
    return localId != null && localId == other.localId;
  }

  /// The server's ordering: `sort_order` ascending, then creation time.
  static int compare(DayNote a, DayNote b) {
    final bySort = a.sortOrder.compareTo(b.sortOrder);
    if (bySort != 0) return bySort;
    return (a.createdAt ?? '').compareTo(b.createdAt ?? '');
  }
}
