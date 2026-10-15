import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum DayNoteOpKind { create, update, delete }

/// One day-note write that hasn't reached the server yet. [fields] uses the
/// request body's wire names (`text`, `time`, `icon`, `color`).
///
/// A create is addressed by [localId] (the note has no server id yet); an
/// update or delete by [noteId], or by [localId] when it targets a note
/// whose create is still queued. [DayNoteOutbox.enqueue] folds those into
/// the queued create, so a queued update or delete always has a [noteId].
class DayNoteOp {
  const DayNoteOp({
    required this.kind,
    required this.dayId,
    this.noteId,
    this.localId,
    this.fields = const {},
    this.createdAt,
  }) : assert(
         kind == DayNoteOpKind.create
             ? localId != null
             : (noteId != null || localId != null),
       );

  final DayNoteOpKind kind;
  final int dayId;
  final int? noteId;
  final String? localId;
  final Map<String, Object?> fields;

  /// When a create was made locally, so the note keeps its place among the
  /// day's other notes each time the queue is re-applied to a server read.
  final String? createdAt;

  /// Matches [DayNote.key] for the note this op writes.
  String get noteKey => noteId != null ? '$noteId' : localId!;

  DayNoteOp copyWith({DayNoteOpKind? kind, Map<String, Object?>? fields}) {
    return DayNoteOp(
      kind: kind ?? this.kind,
      dayId: dayId,
      noteId: noteId,
      localId: localId,
      fields: fields ?? this.fields,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'day_id': dayId,
    'note_id': noteId,
    'local_id': localId,
    'fields': fields,
    'created_at': createdAt,
  };

  factory DayNoteOp.fromJson(Map<String, dynamic> json) {
    return DayNoteOp(
      kind: DayNoteOpKind.values.byName(json['kind'] as String),
      dayId: json['day_id'] as int,
      noteId: json['note_id'] as int?,
      localId: json['local_id'] as String?,
      fields: Map<String, Object?>.from(json['fields'] as Map? ?? const {}),
      createdAt: json['created_at'] as String?,
    );
  }
}

/// Durable, per-trip queue of day-note writes made while the server was
/// unreachable — what [DaysRepository] replays on its next sync and
/// re-applies on top of every fresh server read until it does.
abstract class DayNoteOutbox {
  Future<List<DayNoteOp>> read(String tripId);
  Future<void> write(String tripId, List<DayNoteOp> ops);

  /// Adds [op] to [ops], keeping at most one op per note:
  ///
  /// - an update to a note whose create is still queued merges into that
  ///   create; an update after an update merges into the earlier one;
  /// - a delete of a note whose create is still queued drops the create
  ///   (the server never needs to hear about it); a delete after an update
  ///   replaces the update;
  /// - an update or delete addressed only by a local id with no queued
  ///   create to fold into has nothing it could be sent as, and is dropped.
  static List<DayNoteOp> enqueue(List<DayNoteOp> ops, DayNoteOp op) {
    final index = ops.indexWhere((queued) => queued.noteKey == op.noteKey);
    if (index == -1) {
      if (op.kind != DayNoteOpKind.create && op.noteId == null) return ops;
      return [...ops, op];
    }

    final queued = ops[index];
    final result = List.of(ops);
    switch (op.kind) {
      case DayNoteOpKind.create:
        result.add(op);
      case DayNoteOpKind.update:
        result[index] = queued.copyWith(
          fields: {...queued.fields, ...op.fields},
        );
      case DayNoteOpKind.delete:
        if (queued.kind == DayNoteOpKind.create) {
          result.removeAt(index);
        } else {
          result[index] = op;
        }
    }
    return result;
  }
}

/// Stores each trip's queue as JSON in `shared_preferences`, alongside the
/// day cache it overlays (`PreferencesDaysLocalStore`).
class PreferencesDayNoteOutbox implements DayNoteOutbox {
  PreferencesDayNoteOutbox({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  String _key(String tripId) => 'trek.day_notes.pending.$tripId';

  @override
  Future<List<DayNoteOp>> read(String tripId) async {
    final raw = await _preferences.getString(_key(tripId));
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((json) => DayNoteOp.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> write(String tripId, List<DayNoteOp> ops) async {
    if (ops.isEmpty) {
      await _preferences.remove(_key(tripId));
      return;
    }
    final encoded = jsonEncode(ops.map((op) => op.toJson()).toList());
    await _preferences.setString(_key(tripId), encoded);
  }
}
