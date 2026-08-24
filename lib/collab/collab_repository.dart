import '../network/api_exception.dart';
import 'collab_api.dart';
import 'collab_local_store.dart';
import 'collab_note.dart';

/// Offline-first front door for a trip's collab notes (see
/// docs/offline-first.md) — screens should go through this, not
/// [CollabApi] directly, so the local cache stays the source of truth for
/// what's shown. Mirrors [TodoRepository]'s pending-write shape, trip-scoped
/// the same way, trimmed to this slice's list + create.
///
/// - [cachedNotes] never touches the network — safe to call for an instant
///   first paint.
/// - [refreshNotes] retries any pending (offline-created) notes, then
///   fetches the real list; on [NetworkException] it falls back to (and
///   returns) the cache instead of failing, unless the cache is empty, in
///   which case the exception propagates so the caller can show an
///   explicit offline state.
/// - [createNote] writes an optimistic local note immediately and returns
///   it; if the create can't reach the server it stays queued in the cache
///   ([CollabNote.isPending]) and is retried by the next [refreshNotes]
///   call (e.g. on screen load or pull-to-refresh) rather than lost.
/// - [updateNote] and [deleteNote] apply the same optimistic-write pattern
///   to an already-synced note: the edit/delete is applied to the local
///   cache immediately ([CollabNote.needsSync] / [CollabNote.pendingDelete]
///   mark it as not yet confirmed) and retried by the next [refreshNotes]
///   call if the server couldn't be reached.
class CollabRepository {
  CollabRepository({
    required CollabApi collabApi,
    required CollabLocalStore localStore,
  }) : _collabApi = collabApi,
       _localStore = localStore;

  final CollabApi _collabApi;
  final CollabLocalStore _localStore;

  Future<List<CollabNote>> cachedNotes(String tripId) =>
      _localStore.read(tripId);

  Future<List<CollabNote>> refreshNotes(String tripId) async {
    final afterRetry = await _retryPendingWrites(
      tripId,
      await _localStore.read(tripId),
    );

    try {
      final serverNotes = await _collabApi.listNotes(tripId);
      final serverIds = serverNotes.map((note) => note.id).toSet();
      final localById = {
        for (final note in afterRetry)
          if (note.id != null) note.id!: note,
      };

      final merged = [
        for (final serverNote in serverNotes)
          if (!(localById[serverNote.id]?.pendingDelete ?? false))
            _preferLocalEdit(serverNote, localById[serverNote.id]),
        // A note this call just retried into existence (or one still
        // pending, offline) doesn't necessarily show up in `serverNotes`
        // yet — e.g. the retry above raced this list call. Keep it rather
        // than silently dropping a note the user just created.
        ...afterRetry.where(
          (note) =>
              !note.pendingDelete &&
              (note.isPending || !serverIds.contains(note.id)),
        ),
      ];
      // Tombstoned notes stay in the cache (hidden from `merged`) so the
      // next refresh retries their delete instead of forgetting about it.
      await _localStore.write(tripId, [
        ...merged,
        ...afterRetry.where((note) => note.pendingDelete),
      ]);
      return merged;
    } on NetworkException {
      final visible = afterRetry.where((note) => !note.pendingDelete).toList();
      await _localStore.write(tripId, afterRetry);
      if (visible.isNotEmpty) return visible;
      rethrow;
    }
  }

  /// A server note whose local counterpart still has an unsynced edit
  /// ([CollabNote.needsSync]) keeps the local (edited) version instead of
  /// being overwritten by the stale copy the server just returned.
  CollabNote _preferLocalEdit(CollabNote serverNote, CollabNote? local) {
    if (local != null && local.needsSync) return local;
    return serverNote;
  }

  Future<CollabNote> createNote(
    String tripId, {
    required String title,
    String? content,
    String? category,
    String? color,
  }) async {
    final pending = CollabNote(
      localId: 'local-${DateTime.now().microsecondsSinceEpoch}',
      tripId: tripId,
      title: title,
      content: content,
      category: category,
      color: color,
    );

    final cached = await _localStore.read(tripId);
    await _localStore.write(tripId, [...cached, pending]);

    try {
      final synced = await _collabApi.createNote(
        tripId,
        title: title,
        content: content,
        category: category,
        color: color,
      );
      final reconciled = _reconcile(pending, synced);
      await _localStore.write(tripId, [
        for (final note in [...cached, pending])
          if (note.localId == pending.localId) reconciled else note,
      ]);
      return reconciled;
    } on NetworkException {
      // Stays queued (pending) in the cache — refreshNotes() retries it.
      return pending;
    } catch (_) {
      // A real rejection (validation, permissions, server error), not an
      // offline one — roll back the optimistic write rather than leave a
      // request that can never succeed sitting in the cache forever.
      await _localStore.write(tripId, cached);
      rethrow;
    }
  }

  /// Edits an already-synced note (see [CollabNote.isPending]) — a note
  /// still awaiting its first create should be edited by calling this with
  /// its updated fields too, but there's nothing to `PUT` yet: the local
  /// write below is all that happens, and the eventual create (or its
  /// retry in [refreshNotes]) picks up the new values from the note itself.
  ///
  /// [title] is always sent; [content] and [category] follow [createNote]'s
  /// convention (`null`/blank rather than a partial-update sentinel) — see
  /// [CollabApi.updateNote] for why that's enough to clear [content] but
  /// not [category].
  Future<CollabNote> updateNote(
    String tripId,
    CollabNote note, {
    required String title,
    String? content,
    String? category,
  }) async {
    final cached = await _localStore.read(tripId);
    final updatedLocal = CollabNote(
      id: note.id,
      localId: note.localId,
      tripId: note.tripId,
      title: title,
      content: content,
      category: category,
      color: note.color,
      pinned: note.pinned,
      authorUsername: note.authorUsername,
      needsSync: !note.isPending,
    );
    await _localStore.write(tripId, _replaceByLocalId(cached, updatedLocal));

    if (note.isPending) return updatedLocal;

    try {
      final synced = await _collabApi.updateNote(
        tripId,
        note.id!,
        title: title,
        content: content,
        category: category,
      );
      final reconciled = _reconcile(updatedLocal, synced);
      await _localStore.write(
        tripId,
        _replaceByLocalId(await _localStore.read(tripId), reconciled),
      );
      return reconciled;
    } on NetworkException {
      // Stays needsSync — refreshNotes() retries it.
      return updatedLocal;
    } catch (_) {
      // A real rejection, not an offline one — roll back to what the
      // server still actually has.
      await _localStore.write(tripId, cached);
      rethrow;
    }
  }

  /// Deletes an already-synced or still-[CollabNote.isPending] note. A
  /// pending note (never reached the server) is just dropped locally —
  /// there's nothing to tell the server about. A synced note is removed
  /// from the cache immediately but kept around, tombstoned
  /// ([CollabNote.pendingDelete]), until the `DELETE` actually confirms, so
  /// an offline delete is retried by [refreshNotes] instead of forgotten.
  Future<void> deleteNote(String tripId, CollabNote note) async {
    final cached = await _localStore.read(tripId);

    if (note.isPending) {
      await _localStore.write(
        tripId,
        cached.where((n) => n.localId != note.localId).toList(),
      );
      return;
    }

    await _localStore.write(
      tripId,
      _replaceByLocalId(cached, note.copyWith(pendingDelete: true)),
    );

    try {
      await _collabApi.deleteNote(tripId, note.id!);
      await _dropLocally(tripId, note.localId);
    } on NetworkException {
      // Stays tombstoned (hidden from the list) — refreshNotes() retries it.
    } on ServerException catch (e) {
      if (e.statusCode == 404) {
        // Already gone server-side — fine, that was the goal anyway.
        await _dropLocally(tripId, note.localId);
        return;
      }
      await _localStore.write(tripId, cached); // roll back (e.g. 403)
      rethrow;
    } catch (_) {
      await _localStore.write(tripId, cached);
      rethrow;
    }
  }

  Future<void> _dropLocally(String tripId, String localId) async {
    final current = await _localStore.read(tripId);
    await _localStore.write(
      tripId,
      current.where((n) => n.localId != localId).toList(),
    );
  }

  List<CollabNote> _replaceByLocalId(
    List<CollabNote> notes,
    CollabNote updated,
  ) {
    return [
      for (final note in notes)
        if (note.localId == updated.localId) updated else note,
    ];
  }

  /// Retries every not-yet-confirmed write in [notes] — offline-created
  /// notes ([CollabNote.isPending]), offline edits
  /// ([CollabNote.needsSync]), and offline deletes
  /// ([CollabNote.pendingDelete]) — before [refreshNotes] fetches the real
  /// list.
  Future<List<CollabNote>> _retryPendingWrites(
    String tripId,
    List<CollabNote> notes,
  ) async {
    final result = <CollabNote>[];
    for (final note in notes) {
      if (note.pendingDelete) {
        try {
          await _collabApi.deleteNote(tripId, note.id!);
          // Synced — drop it from the cache entirely (don't add to result).
        } on NetworkException {
          result.add(note); // still offline — keep it tombstoned
        } on ServerException catch (e) {
          if (e.statusCode != 404) rethrow;
          // 404 — already gone server-side, fine to drop.
        }
        continue;
      }
      if (note.isPending) {
        try {
          final synced = await _collabApi.createNote(
            tripId,
            title: note.title,
            content: note.content,
            category: note.category,
            color: note.color,
          );
          result.add(_reconcile(note, synced));
        } on NetworkException {
          result.add(note); // still offline — keep it queued
        }
        continue;
      }
      if (note.needsSync) {
        try {
          final synced = await _collabApi.updateNote(
            tripId,
            note.id!,
            title: note.title,
            content: note.content,
            category: note.category,
          );
          result.add(_reconcile(note, synced));
        } on NetworkException {
          result.add(note); // still offline — keep it queued
        }
        continue;
      }
      result.add(note);
    }
    return result;
  }

  /// Builds the post-sync note from a server response, keeping the local
  /// note's [CollabNote.localId]/[CollabNote.tripId] but otherwise trusting
  /// the server — used after both a create and an update succeed, since
  /// either way the result is a fully-synced note ([CollabNote.needsSync]
  /// and [CollabNote.pendingDelete] both default back to `false`).
  CollabNote _reconcile(CollabNote local, CollabNote synced) {
    return CollabNote(
      id: synced.id,
      localId: local.localId,
      tripId: local.tripId,
      title: synced.title,
      content: synced.content,
      category: synced.category,
      color: synced.color,
      pinned: synced.pinned,
      authorUsername: synced.authorUsername,
    );
  }
}
