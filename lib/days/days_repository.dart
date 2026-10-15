import 'dart:async';

import '../network/api_exception.dart';
import 'day.dart';
import 'day_note.dart';
import 'day_note_outbox.dart';
import 'days_api.dart';
import 'days_local_store.dart';

/// Offline-first front door for a trip's days and their notes (see
/// docs/offline-first.md) — screens should go through this, not [DaysApi]
/// directly, so the local cache stays the source of truth for what's shown.
///
/// - [cachedDays] never touches the network — safe to call for an instant
///   first paint.
/// - [refreshDays] replays any queued note writes, then fetches the real
///   list and re-applies whatever is still queued on top of it. On
///   [NetworkException] it falls back to (and returns) the cache instead of
///   failing, unless the cache is empty, in which case the exception
///   propagates so the caller can show an explicit offline state.
/// - [createDayNote], [updateDayNote], and [deleteDayNote] change the cache
///   immediately, queue the write in the [DayNoteOutbox], and try to send
///   it. A write that can't reach the server stays queued (the note shows
///   as [DayNote.isPending]) until a later write or [refreshDays] gets it
///   through. One the server rejects (validation, permissions, the day is
///   gone) is dropped, the cache is re-read from the server where possible,
///   and the rejection is rethrown.
///
/// Operations run one at a time per repository, so a sync in flight can't
/// send the same queued write twice.
class DaysRepository {
  DaysRepository({
    required DaysApi daysApi,
    required DaysLocalStore localStore,
    required DayNoteOutbox noteOutbox,
    DateTime Function()? now,
  }) : _daysApi = daysApi,
       _localStore = localStore,
       _noteOutbox = noteOutbox,
       _now = now ?? DateTime.now;

  final DaysApi _daysApi;
  final DaysLocalStore _localStore;
  final DayNoteOutbox _noteOutbox;
  final DateTime Function() _now;

  Future<void>? _tail;

  Future<List<Day>> cachedDays(String tripId) => _localStore.read(tripId);

  Future<List<Day>> refreshDays(String tripId) {
    return _serialized(() async {
      await _flush(tripId);
      try {
        return await _fetchAndCache(tripId);
      } on NetworkException {
        final cached = await _localStore.read(tripId);
        if (cached.isNotEmpty) return cached;
        rethrow;
      }
    });
  }

  /// How many note writes for [tripId] are still waiting to reach the
  /// server.
  Future<int> pendingNoteWriteCount(String tripId) async =>
      (await _noteOutbox.read(tripId)).length;

  Future<DayNote> createDayNote(
    String tripId, {
    required int dayId,
    required String text,
    String? time,
    String? icon,
    String? color,
  }) {
    return _serialized(() async {
      final now = _now();
      final op = DayNoteOp(
        kind: DayNoteOpKind.create,
        dayId: dayId,
        localId: 'local-${now.microsecondsSinceEpoch}',
        createdAt: _sqliteTimestamp(now),
        fields: {
          'text': text.trim(),
          'time': _blankToNull(time),
          'icon': icon ?? DayNote.defaultIcon,
          'color': color,
        },
      );
      final local = _noteFromCreate(op);
      await _updateDay(tripId, dayId, (notes) => [...notes, local]);
      final synced = await _enqueueAndFlush(tripId, op);
      return synced ?? local;
    });
  }

  /// [fields] uses the `PUT` body's wire names (`text`, `time`, `icon`,
  /// `color`): a present key replaces that field, `null` clears it.
  Future<DayNote> updateDayNote(
    String tripId,
    DayNote note,
    Map<String, Object?> fields,
  ) {
    return _serialized(() async {
      final current = await _currentCopy(tripId, note);
      final normalized = {
        ...fields,
        if (fields['text'] is String) 'text': (fields['text'] as String).trim(),
        if (fields.containsKey('time'))
          'time': _blankToNull(fields['time'] as String?),
      };
      final local = current.withFields(normalized, isPending: true);
      await _updateDay(
        tripId,
        current.dayId,
        (notes) => [
          for (final existing in notes)
            if (existing.sameNoteAs(current)) local else existing,
        ],
      );
      final synced = await _enqueueAndFlush(
        tripId,
        DayNoteOp(
          kind: DayNoteOpKind.update,
          dayId: current.dayId,
          noteId: current.id,
          localId: current.id == null ? current.localId : null,
          fields: normalized,
        ),
      );
      return synced ?? local;
    });
  }

  Future<void> deleteDayNote(String tripId, DayNote note) {
    return _serialized(() async {
      final current = await _currentCopy(tripId, note);
      await _updateDay(
        tripId,
        current.dayId,
        (notes) => [
          for (final existing in notes)
            if (!existing.sameNoteAs(current)) existing,
        ],
      );
      await _enqueueAndFlush(
        tripId,
        DayNoteOp(
          kind: DayNoteOpKind.delete,
          dayId: current.dayId,
          noteId: current.id,
          localId: current.id == null ? current.localId : null,
        ),
      );
    });
  }

  /// The cache's copy of [note] — which may have picked up a server id
  /// since the caller read it.
  Future<DayNote> _currentCopy(String tripId, DayNote note) async {
    final days = await _localStore.read(tripId);
    for (final day in days) {
      for (final existing in day.noteItems) {
        if (existing.sameNoteAs(note)) return existing;
      }
    }
    return note;
  }

  /// Queues [op], tries to send everything queued, and returns the
  /// server's copy of the note [op] wrote if it got through.
  Future<DayNote?> _enqueueAndFlush(String tripId, DayNoteOp op) async {
    final queued = await _noteOutbox.read(tripId);
    await _noteOutbox.write(tripId, DayNoteOutbox.enqueue(queued, op));

    final result = await _flush(tripId);
    if (result.rejected.isNotEmpty) {
      // A dropped write leaves the cache showing something the server never
      // accepted — re-read the truth now if the server is reachable (the
      // next refresh does it otherwise).
      try {
        await _fetchAndCache(tripId);
      } on ApiException {
        // Keep the cache as is; the next refresh corrects it.
      }
    }
    final rejection = result.rejected[op.noteKey];
    if (rejection != null) throw rejection;
    return result.synced[op.noteKey];
  }

  /// Sends queued writes in order, stopping at the first one that can't
  /// reach the server (it and everything after it stay queued).
  Future<_FlushResult> _flush(String tripId) async {
    final result = _FlushResult();
    var ops = await _noteOutbox.read(tripId);
    while (ops.isNotEmpty) {
      final op = ops.first;
      try {
        switch (op.kind) {
          case DayNoteOpKind.create:
            final note = await _daysApi.createDayNote(
              tripId,
              op.dayId,
              op.fields,
            );
            await _replaceNote(tripId, op, note);
            result.synced[op.noteKey] = note;
          case DayNoteOpKind.update:
            final note = await _daysApi.updateDayNote(
              tripId,
              op.dayId,
              op.noteId!,
              op.fields,
            );
            await _replaceNote(tripId, op, note);
            result.synced[op.noteKey] = note;
          case DayNoteOpKind.delete:
            try {
              await _daysApi.deleteDayNote(tripId, op.dayId, op.noteId!);
            } on ServerException catch (e) {
              // Already gone server-side — the delete's intent holds.
              if (e.statusCode != 404) rethrow;
            }
        }
      } on ApiException catch (e) {
        if (_isTransient(e)) break;
        result.rejected[op.noteKey] = e;
      }
      ops = ops.sublist(1);
      await _noteOutbox.write(tripId, ops);
    }
    return result;
  }

  /// Offline, a 5xx, or an expired session: the write itself may be fine,
  /// so it stays queued rather than being dropped.
  bool _isTransient(ApiException e) {
    return e is NetworkException ||
        e is UnauthorizedException ||
        (e is ServerException && e.statusCode >= 500);
  }

  Future<List<Day>> _fetchAndCache(String tripId) async {
    final serverDays = await _daysApi.listDays(tripId);
    final ops = await _noteOutbox.read(tripId);
    final days = ops.isEmpty ? serverDays : _overlay(serverDays, ops);
    await _localStore.write(tripId, days);
    return days;
  }

  /// Re-applies still-queued writes on top of a fresh server read, so a
  /// refresh never makes an unsynced change disappear from the screen.
  List<Day> _overlay(List<Day> days, List<DayNoteOp> ops) {
    return [
      for (final day in days)
        day.withNoteItems(
          ops
              .where((op) => op.dayId == day.id)
              .fold<List<DayNote>>(day.noteItems, _applyOp),
        ),
    ];
  }

  List<DayNote> _applyOp(List<DayNote> notes, DayNoteOp op) {
    switch (op.kind) {
      case DayNoteOpKind.create:
        return [...notes, _noteFromCreate(op)];
      case DayNoteOpKind.update:
        return [
          for (final note in notes)
            if (note.id == op.noteId)
              note.withFields(op.fields, isPending: true)
            else
              note,
        ];
      case DayNoteOpKind.delete:
        return [
          for (final note in notes)
            if (note.id != op.noteId) note,
        ];
    }
  }

  DayNote _noteFromCreate(DayNoteOp op) {
    return DayNote(
      localId: op.localId,
      dayId: op.dayId,
      text: op.fields['text'] as String? ?? '',
      time: op.fields['time'] as String?,
      icon: op.fields['icon'] as String?,
      color: op.fields['color'] as String?,
      createdAt: op.createdAt,
      isPending: true,
    );
  }

  Future<void> _replaceNote(String tripId, DayNoteOp op, DayNote note) {
    return _updateDay(
      tripId,
      op.dayId,
      (notes) => [
        for (final existing in notes)
          if (existing.key == op.noteKey)
            note.withLocalId(existing.localId)
          else
            existing,
      ],
    );
  }

  Future<void> _updateDay(
    String tripId,
    int dayId,
    List<DayNote> Function(List<DayNote> notes) change,
  ) async {
    final days = await _localStore.read(tripId);
    await _localStore.write(tripId, [
      for (final day in days)
        if (day.id == dayId) day.withNoteItems(change(day.noteItems)) else day,
    ]);
  }

  /// Chains [action] after whatever is already running. The chain is
  /// created on first use, not up front, so no future exists before a
  /// caller (e.g. a widget test's fake-async zone) asks for one.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return () async {
      if (previous != null) await previous;
      try {
        return await action();
      } finally {
        done.complete();
      }
    }();
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : value;
  }

  /// SQLite's `CURRENT_TIMESTAMP` format — what server-created notes carry
  /// in `created_at` — so local and server notes sort together.
  static String _sqliteTimestamp(DateTime time) {
    final utc = time.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
        '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
  }
}

class _FlushResult {
  final synced = <String, DayNote>{};
  final rejected = <String, ApiException>{};
}
