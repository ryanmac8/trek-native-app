import '../network/api_exception.dart';
import 'reservation.dart';
import 'reservations_api.dart';
import 'reservations_local_store.dart';

/// Offline-first front door for a trip's reservations (see
/// docs/offline-first.md) — screens should go through this, not
/// [ReservationsApi] directly, so the local cache stays the source of
/// truth for what's shown.
///
/// This first slice of issue #11 is read-only (no reservation
/// create/edit/delete yet), so there's no pending-write queue to reconcile
/// — [refreshReservations] is a plain fetch-and-cache with an offline
/// fallback, the same shape as `AccommodationsRepository`.
///
/// - [cachedReservations] never touches the network — safe to call for an
///   instant first paint.
/// - [refreshReservations] fetches the real list; on [NetworkException] it
///   falls back to (and returns) the cache instead of failing, unless the
///   cache is empty, in which case the exception propagates so the caller
///   can show an explicit offline state.
class ReservationsRepository {
  ReservationsRepository({
    required ReservationsApi reservationsApi,
    required ReservationsLocalStore localStore,
  }) : _reservationsApi = reservationsApi,
       _localStore = localStore;

  final ReservationsApi _reservationsApi;
  final ReservationsLocalStore _localStore;

  Future<List<Reservation>> cachedReservations(String tripId) =>
      _localStore.read(tripId);

  Future<List<Reservation>> refreshReservations(String tripId) async {
    try {
      final serverReservations = await _reservationsApi.listReservations(
        tripId,
      );
      await _localStore.write(tripId, serverReservations);
      return serverReservations;
    } on NetworkException {
      final cached = await _localStore.read(tripId);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }
}
