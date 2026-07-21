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
    final afterRetry = await _retryPendingCreates(await _localStore.read());

    try {
      final serverTrips = await _tripsApi.listTrips();
      final serverIds = serverTrips.map((trip) => trip.id).toSet();
      final merged = [
        ...serverTrips,
        // Trips this call just retried into existence (or that were
        // already pending) don't necessarily show up in `serverTrips` yet
        // — e.g. the retry above raced this list call. Keep them rather
        // than silently dropping a trip the user just created.
        ...afterRetry.where(
          (trip) => trip.isPending || !serverIds.contains(trip.id),
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

  Future<List<Trip>> _retryPendingCreates(List<Trip> trips) async {
    final result = <Trip>[];
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
        result.add(_reconcile(trip, synced));
      } on NetworkException {
        result.add(trip); // still offline — keep it queued
      }
    }
    return result;
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
