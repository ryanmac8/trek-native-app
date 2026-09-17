import '../network/api_exception.dart';
import 'maps_api.dart';
import 'maps_local_store.dart';
import 'maps_models.dart';

/// One reverse-geocode answer and where it came from.
class ReverseGeocodeSnapshot {
  const ReverseGeocodeSnapshot({
    required this.result,
    required this.fromCache,
    required this.stale,
  });

  final ReverseGeocodeResult result;

  /// Served from the local store rather than a fresh fetch.
  final bool fromCache;

  /// Served from the local store *past its TTL* — i.e. a refresh was wanted
  /// but the network failed (or the geocoder found nothing this time). The
  /// screen shows an offline notice for these.
  final bool stale;
}

/// One resolved-URL answer and where it came from.
class ResolvedPlaceSnapshot {
  const ResolvedPlaceSnapshot({
    required this.place,
    required this.fromCache,
    required this.stale,
  });

  final ResolvedPlace place;
  final bool fromCache;
  final bool stale;
}

/// Offline-first front door for maps/geocoding lookups (see
/// docs/offline-first.md). Screens use this, not [MapsApi] directly.
///
/// [reverseGeocode] and [resolveUrl] both return a fresh cache hit as-is;
/// otherwise they fetch, write the cache, and return. On a [NetworkException]
/// they fall back to a stale cached answer (flagged `.stale`); only when
/// nothing is cached does the exception propagate, so the caller can show an
/// explicit offline state. A [ValidationException] (a URL that doesn't
/// resolve to anywhere, or a malformed coordinate) is a real user-facing
/// error, not an offline condition, so it always propagates.
class MapsRepository {
  MapsRepository({required MapsApi mapsApi, required MapsLocalStore localStore})
    : _api = mapsApi,
      _localStore = localStore;

  final MapsApi _api;
  final MapsLocalStore _localStore;

  Future<ReverseGeocodeSnapshot> reverseGeocode(
    LatLng point, {
    bool forceRefresh = false,
  }) async {
    final key = point.cacheKey;
    final cached = await _localStore.readReverseGeocode(key);

    if (!forceRefresh && cached != null && cached.isFresh) {
      return ReverseGeocodeSnapshot(
        result: cached.result,
        fromCache: true,
        stale: false,
      );
    }

    try {
      final fresh = await _api.reverseGeocode(point);
      // The server swallows lookup failures into an all-null result instead
      // of throwing (see ReverseGeocodeResult) — treat that the same as a
      // network failure so a stale cached answer, if any, still wins over
      // showing nothing.
      if (fresh.isEmpty && cached != null) {
        return ReverseGeocodeSnapshot(
          result: cached.result,
          fromCache: true,
          stale: true,
        );
      }
      await _localStore.writeReverseGeocode(key, fresh);
      return ReverseGeocodeSnapshot(
        result: fresh,
        fromCache: false,
        stale: false,
      );
    } on NetworkException {
      if (cached != null) {
        return ReverseGeocodeSnapshot(
          result: cached.result,
          fromCache: true,
          stale: true,
        );
      }
      rethrow;
    }
  }

  Future<ResolvedPlaceSnapshot> resolveUrl(
    String url, {
    bool forceRefresh = false,
  }) async {
    final key = url.trim();
    final cached = await _localStore.readResolvedPlace(key);

    if (!forceRefresh && cached != null && cached.isFresh) {
      return ResolvedPlaceSnapshot(
        place: cached.place,
        fromCache: true,
        stale: false,
      );
    }

    try {
      final fresh = await _api.resolveUrl(key);
      await _localStore.writeResolvedPlace(key, fresh);
      return ResolvedPlaceSnapshot(
        place: fresh,
        fromCache: false,
        stale: false,
      );
    } on NetworkException {
      if (cached != null) {
        return ResolvedPlaceSnapshot(
          place: cached.place,
          fromCache: true,
          stale: true,
        );
      }
      rethrow;
    }
  }
}
