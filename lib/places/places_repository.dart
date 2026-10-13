import '../network/api_exception.dart';
import 'pending_place_op.dart';
import 'place.dart';
import 'places_api.dart';
import 'places_local_store.dart';

/// What a [PlacesRepository.syncPending] pass achieved.
class PlaceSyncResult {
  const PlaceSyncResult({this.offline = false, this.rejections = const []});

  /// The pass stopped because the server was unreachable; the remaining
  /// changes stay queued for the next pass.
  final bool offline;

  /// User-facing messages for changes the server refused outright (no
  /// permission, validation, place gone). Those changes were dropped and the
  /// local cache rolled back to the server's version.
  final List<String> rejections;
}

/// Offline-first front door for a trip's place pool (see
/// docs/offline-first.md and docs/places.md) — screens should go through
/// this, not [PlacesApi] directly, so the local cache stays the source of
/// truth for what's shown.
///
/// - [cachedPlaces] never touches the network — safe to call for an instant
///   first paint.
/// - [createPlace], [updatePlace], and [deletePlace] apply to the local cache
///   immediately and append to the trip's outbox; they never touch the
///   network. [syncPending] replays the outbox in order.
/// - [refreshPlaces] syncs the outbox, then fetches the real list and lays
///   any still-queued changes over it. On [NetworkException] it falls back
///   to (and returns) the cache instead of failing, unless the cache is
///   empty, in which case the exception propagates so the caller can show
///   an explicit offline state.
class PlacesRepository {
  PlacesRepository({
    required PlacesApi placesApi,
    required PlacesLocalStore localStore,
  }) : _placesApi = placesApi,
       _localStore = localStore;

  final PlacesApi _placesApi;
  final PlacesLocalStore _localStore;

  /// Per-trip tail of the read-modify-write chain over the local store, so
  /// a user edit and a sync step never interleave and lose each other's
  /// write.
  final Map<String, Future<void>> _locks = {};
  final Map<String, Future<PlaceSyncResult>> _syncs = {};
  final Set<String> _syncRequestedAgain = {};

  /// Outbox entries whose request is on the wire right now — new edits are
  /// queued behind them rather than merged into them.
  final Set<String> _inFlightOpIds = {};
  int _opCounter = 0;

  Future<List<Place>> cachedPlaces(String tripId) => _localStore.read(tripId);

  Future<List<Place>> refreshPlaces(String tripId) async {
    await syncPending(tripId);
    try {
      return await _fetchAndMerge(tripId);
    } on NetworkException {
      final cached = await _localStore.read(tripId);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  /// Adds a place locally under a negative temporary id and queues its
  /// create. Returns the local place.
  Future<Place> createPlace(String tripId, PlaceInput input) {
    return _locked(tripId, () async {
      final places = await _localStore.read(tripId);
      final ops = await _localStore.readPending(tripId);
      final lowestId = [
        ...places.map((p) => p.id),
        ...ops.map((op) => op.placeId),
      ].fold<int>(0, (lowest, id) => id < lowest ? id : lowest);
      final fields = input.toCreateJson();
      final place = _localPlace(tripId, lowestId - 1, fields);
      ops.add(
        PendingPlaceOp(
          id: _nextOpId(),
          kind: PendingPlaceOpKind.create,
          placeId: place.id,
          fields: fields,
        ),
      );
      await _localStore.write(tripId, [...places, place]);
      await _localStore.writePending(tripId, ops);
      return place;
    });
  }

  /// Applies [input] to [place] locally and queues only the changed fields.
  /// Edits to a place that already has a queued change are merged into it.
  Future<Place> updatePlace(String tripId, Place place, PlaceInput input) {
    return _locked(tripId, () async {
      final changes = input.changesFrom(place);
      final places = await _localStore.read(tripId);
      final index = places.indexWhere((p) => p.id == place.id);
      if (changes.isEmpty || index < 0) return place;

      final ops = await _localStore.readPending(tripId);
      final mergeIndex = ops.lastIndexWhere(
        (op) =>
            op.placeId == place.id &&
            op.kind != PendingPlaceOpKind.delete &&
            !_inFlightOpIds.contains(op.id),
      );
      var status = PlaceSyncStatus.pending;
      if (mergeIndex >= 0) {
        final target = ops[mergeIndex];
        ops[mergeIndex] = target.copyWith(
          fields: {...target.fields, ...changes},
        );
        if (target.isConflicted) status = PlaceSyncStatus.conflict;
      } else {
        ops.add(
          PendingPlaceOp(
            id: _nextOpId(),
            kind: PendingPlaceOpKind.update,
            placeId: place.id,
            fields: changes,
            baseUpdatedAt: places[index].updatedAt,
          ),
        );
      }
      final updated = places[index].applyFields(changes, status: status);
      places[index] = updated;
      await _localStore.write(tripId, places);
      await _localStore.writePending(tripId, ops);
      return updated;
    });
  }

  /// Removes a place locally and queues its delete. Any queued changes to
  /// it are dropped; a place whose create never synced just disappears.
  Future<void> deletePlace(String tripId, int placeId) {
    return _locked(tripId, () async {
      final places = await _localStore.read(tripId)
        ..removeWhere((p) => p.id == placeId);
      final ops = (await _localStore.readPending(tripId))
          .where(
            (op) => op.placeId != placeId || _inFlightOpIds.contains(op.id),
          )
          .toList();
      final existsOnServer =
          placeId > 0 ||
          ops.any(
            (op) =>
                op.placeId == placeId && op.kind == PendingPlaceOpKind.create,
          );
      if (existsOnServer) {
        ops.add(
          PendingPlaceOp(
            id: _nextOpId(),
            kind: PendingPlaceOpKind.delete,
            placeId: placeId,
          ),
        );
      }
      await _localStore.write(tripId, places);
      await _localStore.writePending(tripId, ops);
    });
  }

  /// Settles a 409 on [placeId]. [keepMine] re-queues the local edit against
  /// the server's current version (so it overwrites it); otherwise the
  /// local edit is discarded and the server's version shown.
  Future<void> resolveConflict(
    String tripId,
    int placeId, {
    required bool keepMine,
  }) {
    return _locked(tripId, () async {
      final ops = await _localStore.readPending(tripId);
      final index = ops.indexWhere(
        (op) => op.placeId == placeId && op.isConflicted,
      );
      if (index < 0) return;
      final op = ops[index];
      final server = Place.fromJson(op.conflictServer!);
      if (keepMine) {
        ops[index] = op.copyWith(
          baseUpdatedAt: server.updatedAt,
          clearConflict: true,
        );
      } else {
        ops.removeAt(index);
      }
      await _replacePlace(tripId, placeId, _overlayOne(server, ops));
      await _localStore.writePending(tripId, ops);
    });
  }

  /// Replays the trip's outbox oldest-first until it's empty or the server
  /// can't be reached. Concurrent calls share one pass; a call made while a
  /// pass is running makes it go round once more, so a change queued during
  /// it isn't left behind.
  Future<PlaceSyncResult> syncPending(String tripId) {
    final running = _syncs[tripId];
    if (running != null) {
      _syncRequestedAgain.add(tripId);
      return running;
    }
    final pass = () async {
      try {
        final rejections = <String>[];
        PlaceSyncResult result;
        do {
          _syncRequestedAgain.remove(tripId);
          result = await _runSync(tripId);
          rejections.addAll(result.rejections);
        } while (_syncRequestedAgain.contains(tripId) && !result.offline);
        return PlaceSyncResult(offline: result.offline, rejections: rejections);
      } finally {
        _syncs.remove(tripId);
        _syncRequestedAgain.remove(tripId);
      }
    }();
    _syncs[tripId] = pass;
    return pass;
  }

  Future<PlaceSyncResult> _runSync(String tripId) async {
    final rejections = <String>[];
    var offline = false;
    var refetch = false;

    while (true) {
      final op = await _locked(tripId, () async {
        final ops = await _localStore.readPending(tripId);
        // A place with an unresolved conflict holds back everything queued
        // after it for that place, so its changes still land in order.
        final blocked = <int>{};
        for (final op in ops) {
          if (op.isConflicted) {
            blocked.add(op.placeId);
          } else if (!blocked.contains(op.placeId)) {
            return op;
          }
        }
        return null;
      });
      if (op == null) break;

      _inFlightOpIds.add(op.id);
      try {
        switch (op.kind) {
          case PendingPlaceOpKind.create:
            final server = await _placesApi.createPlace(tripId, op.fields);
            await _locked(tripId, () => _applyCreated(tripId, op, server));
          case PendingPlaceOpKind.update:
            final server = await _placesApi.updatePlace(
              tripId,
              op.placeId,
              op.fields,
              baseUpdatedAt: op.baseUpdatedAt,
            );
            await _locked(tripId, () => _applyUpdated(tripId, op, server));
          case PendingPlaceOpKind.delete:
            await _placesApi.deletePlace(tripId, op.placeId);
            await _locked(tripId, () => _removeOp(tripId, op.id));
        }
      } on NetworkException {
        offline = true;
        break;
      } on UnauthorizedException {
        // Keep everything queued; it replays once signed back in.
        break;
      } on ConflictException catch (e) {
        final server = e.body?['server'];
        if (op.kind == PendingPlaceOpKind.update &&
            server is Map<String, dynamic>) {
          await _locked(tripId, () => _markConflict(tripId, op, server));
        } else {
          final name = await _locked(
            tripId,
            () => _dropRejected(tripId, op, placeGone: false),
          );
          rejections.add(_rejectionMessage(name, e.message));
          refetch = true;
        }
      } on ServerException catch (e) {
        if (e.statusCode != 404) break; // Server trouble — retry later.
        final name = await _locked(
          tripId,
          () => _dropRejected(tripId, op, placeGone: true),
        );
        if (op.kind != PendingPlaceOpKind.delete) {
          rejections.add('"$name" no longer exists on the server.');
        }
      } on ApiException catch (e) {
        final name = await _locked(
          tripId,
          () => _dropRejected(
            tripId,
            op,
            placeGone: op.kind == PendingPlaceOpKind.create,
          ),
        );
        rejections.add(_rejectionMessage(name, e.message));
        if (op.kind != PendingPlaceOpKind.create) refetch = true;
      } finally {
        _inFlightOpIds.remove(op.id);
      }
    }

    if (refetch && !offline) {
      try {
        await _fetchAndMerge(tripId);
      } on ApiException {
        // The next refresh restores the server's version instead.
      }
    }
    return PlaceSyncResult(offline: offline, rejections: rejections);
  }

  Future<void> _applyCreated(
    String tripId,
    PendingPlaceOp op,
    Place server,
  ) async {
    final ops = (await _localStore.readPending(tripId))
      ..removeWhere((o) => o.id == op.id);
    for (var i = 0; i < ops.length; i++) {
      if (ops[i].placeId != op.placeId) continue;
      ops[i] = ops[i].copyWith(
        placeId: server.id,
        baseUpdatedAt: ops[i].kind == PendingPlaceOpKind.update
            ? server.updatedAt
            : null,
      );
    }
    await _replacePlace(tripId, op.placeId, _overlayOne(server, ops));
    await _localStore.writePending(tripId, ops);
  }

  Future<void> _applyUpdated(
    String tripId,
    PendingPlaceOp op,
    Place server,
  ) async {
    final ops = (await _localStore.readPending(tripId))
      ..removeWhere((o) => o.id == op.id);
    // Edits queued while this one was on the wire were based on the version
    // it replaced; rebase them on ours so they don't 409 against it.
    for (var i = 0; i < ops.length; i++) {
      if (ops[i].placeId == server.id &&
          ops[i].kind == PendingPlaceOpKind.update &&
          !ops[i].isConflicted) {
        ops[i] = ops[i].copyWith(baseUpdatedAt: server.updatedAt);
      }
    }
    await _replacePlace(tripId, server.id, _overlayOne(server, ops));
    await _localStore.writePending(tripId, ops);
  }

  Future<void> _markConflict(
    String tripId,
    PendingPlaceOp op,
    Map<String, dynamic> server,
  ) async {
    final ops = await _localStore.readPending(tripId);
    final index = ops.indexWhere((o) => o.id == op.id);
    if (index >= 0) ops[index] = ops[index].copyWith(conflictServer: server);
    final places = await _localStore.read(tripId);
    final placeIndex = places.indexWhere((p) => p.id == op.placeId);
    if (placeIndex >= 0) {
      places[placeIndex] = places[placeIndex].withSyncStatus(
        PlaceSyncStatus.conflict,
      );
    }
    await _localStore.write(tripId, places);
    await _localStore.writePending(tripId, ops);
  }

  Future<void> _removeOp(String tripId, String opId) async {
    final ops = (await _localStore.readPending(tripId))
      ..removeWhere((o) => o.id == opId);
    await _localStore.writePending(tripId, ops);
  }

  /// Drops an op the server refused for good, returning the place's name for
  /// the user-facing message. With [placeGone] (a refused create, or a place
  /// the server answered 404 for) the local place and everything queued
  /// against it go too.
  Future<String> _dropRejected(
    String tripId,
    PendingPlaceOp op, {
    required bool placeGone,
  }) async {
    final places = await _localStore.read(tripId);
    final ops = await _localStore.readPending(tripId);
    final cached = places.where((p) => p.id == op.placeId).firstOrNull;
    final name = cached?.name ?? (op.fields['name'] as String?) ?? 'Place';
    if (placeGone) {
      ops.removeWhere((o) => o.placeId == op.placeId);
      places.removeWhere((p) => p.id == op.placeId);
      await _localStore.write(tripId, places);
    } else {
      ops.removeWhere((o) => o.id == op.id);
    }
    await _localStore.writePending(tripId, ops);
    return name;
  }

  Future<List<Place>> _fetchAndMerge(String tripId) async {
    final server = await _placesApi.listPlaces(tripId);
    return _locked(tripId, () async {
      final ops = await _localStore.readPending(tripId);
      final merged = _overlay(tripId, server, ops);
      await _localStore.write(tripId, merged);
      return merged;
    });
  }

  /// The server's list with the queued changes laid over it, in order.
  List<Place> _overlay(
    String tripId,
    List<Place> server,
    List<PendingPlaceOp> ops,
  ) {
    final result = List.of(server);
    for (final op in ops) {
      final index = result.indexWhere((p) => p.id == op.placeId);
      switch (op.kind) {
        case PendingPlaceOpKind.create:
          if (index < 0) result.add(_localPlace(tripId, op.placeId, op.fields));
        case PendingPlaceOpKind.update:
          if (index >= 0) {
            result[index] = result[index].applyFields(
              op.fields,
              status: _statusFor(op),
            );
          }
        case PendingPlaceOpKind.delete:
          if (index >= 0) result.removeAt(index);
      }
    }
    return result;
  }

  /// [server] with any changes still queued for it applied, or `null` if a
  /// queued delete means it shouldn't be shown.
  Place? _overlayOne(Place server, List<PendingPlaceOp> ops) {
    var place = server;
    for (final op in ops.where((o) => o.placeId == server.id)) {
      if (op.kind == PendingPlaceOpKind.delete) return null;
      place = place.applyFields(op.fields, status: _statusFor(op));
    }
    return place;
  }

  PlaceSyncStatus _statusFor(PendingPlaceOp op) =>
      op.isConflicted ? PlaceSyncStatus.conflict : PlaceSyncStatus.pending;

  /// Puts [replacement] where the place with [oldId] was in the cache (or at
  /// the end), dropping any other copy of it; `null` just removes it.
  Future<void> _replacePlace(
    String tripId,
    int oldId,
    Place? replacement,
  ) async {
    final places = await _localStore.read(tripId);
    final index = places.indexWhere((p) => p.id == oldId);
    places.removeWhere(
      (p) => p.id == oldId || (replacement != null && p.id == replacement.id),
    );
    if (replacement != null) {
      final insertAt = index < 0 || index > places.length
          ? places.length
          : index;
      places.insert(insertAt, replacement);
    }
    await _localStore.write(tripId, places);
  }

  Place _localPlace(String tripId, int id, Map<String, dynamic> fields) {
    return Place(
      id: id,
      tripId: int.tryParse(tripId) ?? 0,
      name: fields['name'] as String? ?? '',
      syncStatus: PlaceSyncStatus.pending,
    ).applyFields(fields);
  }

  String _nextOpId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_opCounter++}';

  String _rejectionMessage(String name, String reason) =>
      'Couldn\'t save changes to "$name": $reason';

  Future<T> _locked<T>(String tripId, Future<T> Function() body) {
    final previous = _locks[tripId];
    final result = previous == null ? body() : previous.then((_) => body());
    _locks[tripId] = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
