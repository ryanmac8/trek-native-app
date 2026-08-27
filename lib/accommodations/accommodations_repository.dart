import '../network/api_exception.dart';
import 'accommodation.dart';
import 'accommodations_api.dart';
import 'accommodations_local_store.dart';

/// Offline-first front door for a trip's accommodations (see
/// docs/offline-first.md) — screens should go through this, not
/// [AccommodationsApi] directly, so the local cache stays the source of
/// truth for what's shown.
///
/// This first slice of issue #10 is read-only (no accommodation
/// create/edit/delete yet), so there's no pending-write queue to reconcile
/// — [refreshAccommodations] is a plain fetch-and-cache with an offline
/// fallback, the same shape as `PlacesRepository`.
///
/// - [cachedAccommodations] never touches the network — safe to call for an
///   instant first paint.
/// - [refreshAccommodations] fetches the real list; on [NetworkException]
///   it falls back to (and returns) the cache instead of failing, unless
///   the cache is empty, in which case the exception propagates so the
///   caller can show an explicit offline state.
class AccommodationsRepository {
  AccommodationsRepository({
    required AccommodationsApi accommodationsApi,
    required AccommodationsLocalStore localStore,
  }) : _accommodationsApi = accommodationsApi,
       _localStore = localStore;

  final AccommodationsApi _accommodationsApi;
  final AccommodationsLocalStore _localStore;

  Future<List<Accommodation>> cachedAccommodations(String tripId) =>
      _localStore.read(tripId);

  Future<List<Accommodation>> refreshAccommodations(String tripId) async {
    try {
      final serverAccommodations = await _accommodationsApi.listAccommodations(
        tripId,
      );
      await _localStore.write(tripId, serverAccommodations);
      return serverAccommodations;
    } on NetworkException {
      final cached = await _localStore.read(tripId);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }
}
