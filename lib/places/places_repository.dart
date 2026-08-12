import '../network/api_exception.dart';
import 'place.dart';
import 'places_api.dart';
import 'places_local_store.dart';

/// Offline-first front door for a trip's place pool (see
/// docs/offline-first.md) — screens should go through this, not [PlacesApi]
/// directly, so the local cache stays the source of truth for what's shown.
///
/// This first slice of issue #5 is read-only (no place create/edit/delete
/// yet), so unlike [TripsRepository] there's no pending-write queue to
/// reconcile — [refreshPlaces] is a plain fetch-and-cache with an offline
/// fallback, the same shape as [DaysRepository].
///
/// - [cachedPlaces] never touches the network — safe to call for an instant
///   first paint.
/// - [refreshPlaces] fetches the real list; on [NetworkException] it falls
///   back to (and returns) the cache instead of failing, unless the cache
///   is empty, in which case the exception propagates so the caller can
///   show an explicit offline state.
class PlacesRepository {
  PlacesRepository({
    required PlacesApi placesApi,
    required PlacesLocalStore localStore,
  }) : _placesApi = placesApi,
       _localStore = localStore;

  final PlacesApi _placesApi;
  final PlacesLocalStore _localStore;

  Future<List<Place>> cachedPlaces(String tripId) => _localStore.read(tripId);

  Future<List<Place>> refreshPlaces(String tripId) async {
    try {
      final serverPlaces = await _placesApi.listPlaces(tripId);
      await _localStore.write(tripId, serverPlaces);
      return serverPlaces;
    } on NetworkException {
      final cached = await _localStore.read(tripId);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }
}
