import '../network/api_exception.dart';
import 'trip.dart';
import 'trips_api.dart';
import 'trips_local_store.dart';

/// Offline-first front door for trip reads and writes (see
/// docs/offline-first.md) — screens should go through this, not [TripsApi]
/// directly, so the local cache stays the source of truth for what's shown.
///
/// - [cachedTrips] never touches the network — safe to call for an instant
///   first paint.
/// - [refreshTrips] retries any pending offline creates, then fetches the
///   real list; on [NetworkException] it falls back to (and returns) the
///   cache instead of failing, unless the cache is empty, in which case the
///   exception propagates so the caller can show an explicit offline state.
/// - [createTrip] writes an optimistic local trip immediately and returns
///   it; if the create can't reach the server it stays queued in the cache
///   ([Trip.isPending]) and is retried by the next [refreshTrips] call
///   (e.g. on screen load or pull-to-refresh) rather than lost.
class TripsRepository {
  TripsRepository({
    required TripsApi tripsApi,
    required TripsLocalStore localStore,
  }) : _tripsApi = tripsApi,
       _localStore = localStore;

  final TripsApi _tripsApi;
  final TripsLocalStore _localStore;

  Future<List<Trip>> cachedTrips() => _localStore.read();

  Future<List<Trip>> refreshTrips() async {
    final stillPendingDeletes = await _retryPendingDeletes();
    final afterEdits = await _retryPendingEdits(await _localStore.read());
    final (afterRetry, justSyncedIds) = await _retryPendingCreates(afterEdits);

    try {
      final serverTrips = await _tripsApi.listTrips();
      // A delete that hasn't synced yet (still offline) must not have its
      // trip reappear just because the list call above happened to reach
      // the server before the delete retry above did.
      final visibleServerTrips = serverTrips
          .where((trip) => !stillPendingDeletes.contains(trip.id))
          .toList();
      final serverIds = visibleServerTrips.map((trip) => trip.id).toSet();
      final merged = [
        ...visibleServerTrips,
        ...afterRetry.where(
          (trip) =>
              // Still queued (pending create, edit, or archive toggle) —
              // keep it rather than silently dropping local state the
              // server hasn't confirmed yet.
              trip.isPending ||
              trip.hasPendingEdit ||
              trip.hasPendingArchiveSync ||
              // A create that synced moments ago, in this same call, might
              // not show up in `serverTrips` yet if the list call above
              // raced it — keep it rather than flash the trip out of
              // existence for one refresh. A trip that's simply absent for
              // any other reason has legitimately been archived or deleted
              // server-side (the default list excludes archived trips), so
              // it's correctly left out of `merged`.
              (justSyncedIds.contains(trip.id) && !serverIds.contains(trip.id)),
        ),
      ];
      await _localStore.write(merged);
      return merged;
    } on NetworkException {
      await _localStore.write(afterRetry);
      if (afterRetry.isNotEmpty) return afterRetry;
      rethrow;
    }
  }

  Future<Trip> createTrip({
    required String title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    String? currency,
  }) async {
    final pending = Trip(
      localId: 'local-${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      description: description,
      startDate: startDate,
      endDate: endDate,
      currency: currency,
    );

    final cached = await _localStore.read();
    await _localStore.write([...cached, pending]);

    try {
      final synced = await _tripsApi.createTrip(
        title: title,
        description: description,
        startDate: startDate,
        endDate: endDate,
        currency: currency,
      );
      final reconciled = _reconcile(pending, synced);
      await _localStore.write([
        for (final trip in [...cached, pending])
          if (trip.localId == pending.localId) reconciled else trip,
      ]);
      return reconciled;
    } on NetworkException {
      // Stays queued (pending) in the cache — refreshTrips() retries it.
      return pending;
    } catch (_) {
      // A real rejection (validation, permissions, server error), not an
      // offline one — roll back the optimistic write rather than leave a
      // request that can never succeed sitting in the cache forever.
      await _localStore.write(cached);
      rethrow;
    }
  }

  /// Saves an edit to a trip's title/description/dates/currency. Applies
  /// the change to the local cache immediately (so the dashboard reflects
  /// it before any network round-trip) and only rolls it back if the
  /// server outright rejects it — a [NetworkException] instead leaves the
  /// edit applied locally, flagged via [Trip.hasPendingEdit] for
  /// [refreshTrips] to retry.
  Future<Trip> editTrip({
    required int id,
    required String title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    String? currency,
  }) async {
    final cached = await _localStore.read();
    final index = cached.indexWhere((trip) => trip.id == id);
    if (index == -1) {
      throw StateError('Cannot edit trip $id: not present in the local cache.');
    }
    final previous = cached[index];
    final optimistic = Trip(
      id: id,
      localId: previous.localId,
      title: title,
      description: description,
      startDate: startDate,
      endDate: endDate,
      currency: currency,
      dayCount: previous.dayCount,
      placeCount: previous.placeCount,
      isArchived: previous.isArchived,
      hasPendingEdit: true,
      hasPendingArchiveSync: previous.hasPendingArchiveSync,
    );
    await _replaceInCache(id, optimistic);

    try {
      final synced = await _tripsApi.updateTrip(
        id: id,
        title: title,
        description: description,
        startDate: startDate,
        endDate: endDate,
        currency: currency,
      );
      final reconciled = synced.copyWith(
        localId: previous.localId,
        hasPendingArchiveSync: previous.hasPendingArchiveSync,
      );
      await _replaceInCache(id, reconciled);
      return reconciled;
    } on NetworkException {
      return optimistic; // stays flagged; refreshTrips() retries it
    } catch (_) {
      await _replaceInCache(id, previous);
      rethrow;
    }
  }

  /// Toggles [Trip.isArchived]. Kept separate from [editTrip] so it only
  /// ever sends `is_archived` to the server — see [TripsApi.archiveTrip].
  Future<Trip> setArchived({required int id, required bool archived}) async {
    final cached = await _localStore.read();
    final index = cached.indexWhere((trip) => trip.id == id);
    if (index == -1) {
      throw StateError(
        'Cannot archive trip $id: not present in the local cache.',
      );
    }
    final previous = cached[index];
    final optimistic = previous.copyWith(
      isArchived: archived,
      hasPendingArchiveSync: true,
    );
    await _replaceInCache(id, optimistic);

    try {
      final synced = await _tripsApi.archiveTrip(id: id, archived: archived);
      final reconciled = synced.copyWith(
        localId: previous.localId,
        hasPendingEdit: previous.hasPendingEdit,
      );
      await _replaceInCache(id, reconciled);
      return reconciled;
    } on NetworkException {
      return optimistic; // stays flagged; refreshTrips() retries it
    } catch (_) {
      await _replaceInCache(id, previous);
      rethrow;
    }
  }

  /// Removes a trip immediately from the local cache (so it disappears
  /// from the list right away) and attempts the server delete in the
  /// background. If that can't reach the server, the id is queued in
  /// [TripsLocalStore.readPendingDeletes] for [refreshTrips] to retry — the
  /// trip itself stays gone from the visible cache either way, since the
  /// user already asked for it to be deleted.
  Future<void> deleteTrip(int id) async {
    final cached = await _localStore.read();
    final index = cached.indexWhere((trip) => trip.id == id);
    if (index == -1) return;
    final removed = cached[index];
    final updatedCache = List.of(cached)..removeAt(index);
    await _localStore.write(updatedCache);

    try {
      await _tripsApi.deleteTrip(id);
    } on NetworkException {
      final pending = await _localStore.readPendingDeletes();
      await _localStore.writePendingDeletes({...pending, id});
    } catch (_) {
      // A genuine rejection (permissions, a 5xx) — restore the trip rather
      // than leave the user thinking it's gone when it isn't.
      final rollback = List.of(await _localStore.read());
      rollback.insert(index.clamp(0, rollback.length), removed);
      await _localStore.write(rollback);
      rethrow;
    }
  }

  Future<void> _replaceInCache(int id, Trip trip) async {
    final cached = await _localStore.read();
    final index = cached.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final updated = List.of(cached)..[index] = trip;
    await _localStore.write(updated);
  }

  Future<Set<int>> _retryPendingDeletes() async {
    final pending = await _localStore.readPendingDeletes();
    if (pending.isEmpty) return pending;
    final remaining = <int>{};
    for (final id in pending) {
      try {
        await _tripsApi.deleteTrip(id);
      } on NetworkException {
        remaining.add(id); // still offline — keep queued
      } catch (_) {
        // Already gone server-side, or a rejection that can't be retried
        // indefinitely — either way there's nothing left to reconcile,
        // since the trip is already off the visible cache.
      }
    }
    if (remaining.length != pending.length) {
      await _localStore.writePendingDeletes(remaining);
    }
    return remaining;
  }

  Future<List<Trip>> _retryPendingEdits(List<Trip> trips) async {
    final result = <Trip>[];
    for (final trip in trips) {
      var next = trip;
      if (trip.hasPendingEdit && trip.id != null) {
        try {
          final synced = await _tripsApi.updateTrip(
            id: trip.id!,
            title: trip.title,
            description: trip.description,
            startDate: trip.startDate,
            endDate: trip.endDate,
            currency: trip.currency,
          );
          next = synced.copyWith(
            localId: trip.localId,
            hasPendingArchiveSync: next.hasPendingArchiveSync,
          );
        } on NetworkException {
          // still offline — keep flagged
        }
      }
      if (next.hasPendingArchiveSync && next.id != null) {
        try {
          final synced = await _tripsApi.archiveTrip(
            id: next.id!,
            archived: next.isArchived,
          );
          next = synced.copyWith(
            localId: next.localId,
            hasPendingEdit: next.hasPendingEdit,
          );
        } on NetworkException {
          // still offline — keep flagged
        }
      }
      result.add(next);
    }
    return result;
  }

  Future<(List<Trip>, Set<int>)> _retryPendingCreates(List<Trip> trips) async {
    final result = <Trip>[];
    final justSyncedIds = <int>{};
    for (final trip in trips) {
      if (!trip.isPending) {
        result.add(trip);
        continue;
      }
      try {
        final synced = await _tripsApi.createTrip(
          title: trip.title,
          description: trip.description,
          startDate: trip.startDate,
          endDate: trip.endDate,
          currency: trip.currency,
        );
        final reconciled = _reconcile(trip, synced);
        result.add(reconciled);
        justSyncedIds.add(reconciled.id!);
      } on NetworkException {
        result.add(trip); // still offline — keep it queued
      }
    }
    return (result, justSyncedIds);
  }

  Trip _reconcile(Trip pending, Trip synced) {
    return Trip(
      id: synced.id,
      localId: pending.localId,
      title: synced.title,
      description: synced.description,
      startDate: synced.startDate,
      endDate: synced.endDate,
      currency: synced.currency,
      dayCount: synced.dayCount,
      placeCount: synced.placeCount,
    );
  }
}
