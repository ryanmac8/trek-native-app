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
    final afterRetry = await _retryPending(
      tripId,
      await _localStore.read(tripId),
    );

    try {
      final serverNotes = await _collabApi.listNotes(tripId);
      final serverIds = serverNotes.map((note) => note.id).toSet();
      final merged = [
        ...serverNotes,
        // A note this call just retried into existence (or one still
        // pending, offline) doesn't necessarily show up in `serverNotes`
        // yet — e.g. the retry above raced this list call. Keep it rather
        // than silently dropping a note the user just created.
        ...afterRetry.where(
          (note) => note.isPending || !serverIds.contains(note.id),
        ),
      ];
      await _localStore.write(tripId, merged);
      return merged;
    } on NetworkException {
      await _localStore.write(tripId, afterRetry);
      if (afterRetry.isNotEmpty) return afterRetry;
      rethrow;
    }
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

  /// Retries every not-yet-synced (offline-created) note in [notes] before
  /// [refreshNotes] fetches the real list.
  Future<List<CollabNote>> _retryPending(
    String tripId,
    List<CollabNote> notes,
  ) async {
    final result = <CollabNote>[];
    for (final note in notes) {
      if (!note.isPending) {
        result.add(note);
        continue;
      }
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
    }
    return result;
  }

  CollabNote _reconcile(CollabNote pending, CollabNote synced) {
    return CollabNote(
      id: synced.id,
      localId: pending.localId,
      tripId: pending.tripId,
      title: synced.title,
      content: synced.content,
      category: synced.category,
      color: synced.color,
      pinned: synced.pinned,
      authorUsername: synced.authorUsername,
    );
  }
}
