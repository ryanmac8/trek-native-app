import '../network/api_exception.dart';
import 'transit_api.dart';
import 'transit_local_store.dart';
import 'transit_models.dart';

/// Offline-first front door for transit + airport search (see
/// docs/offline-first.md). Screens use this, not [TransitApi] directly.
///
/// Search and planning need the network — there is no bundled transit graph
/// — but this keeps the local cache as the source of truth for *what's
/// shown*:
///
/// - `cached*` reads never touch the network, so a screen can paint the
///   last results for a query instantly.
/// - `search*` / `planRoute` fetch, write the cache, and return. On a
///   [NetworkException] they fall back to the cached results for that exact
///   query if there are any; only when nothing is cached does the exception
///   propagate, so the caller can show an explicit offline state.
///
/// There are no mutations here. Turning a result into an itinerary entry is
/// a write that depends on the Days feature (issue #4) and is deferred with
/// it.
class TransitRepository {
  TransitRepository({
    required TransitApi transitApi,
    required TransitLocalStore localStore,
  }) : _api = transitApi,
       _localStore = localStore;

  final TransitApi _api;
  final TransitLocalStore _localStore;

  /// The server ignores queries shorter than this; mirror it so an empty
  /// picker doesn't spend a request or a cache entry.
  static const minQueryLength = 2;

  /// Normalises a free-text query to a cache key: trimmed, lower-cased,
  /// internal whitespace collapsed, with an optional `near` suffix so a
  /// biased search doesn't collide with an unbiased one.
  static String queryKey(String query, {String? near}) {
    final normalised = query.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return near == null ? normalised : '$normalised@$near';
  }

  Future<List<TransitPlace>?> cachedStops(String query, {String? near}) {
    return _localStore.readStopSearch(queryKey(query, near: near));
  }

  Future<List<TransitPlace>> searchStops(String query, {String? near}) async {
    if (query.trim().length < minQueryLength) return const [];
    final key = queryKey(query, near: near);
    try {
      final results = await _api.searchStops(query, near: near);
      await _localStore.writeStopSearch(key, results);
      return results;
    } on NetworkException {
      final cached = await _localStore.readStopSearch(key);
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<List<TransitItinerary>?> cachedRoute(TransitPlanQuery query) {
    return _localStore.readRoutePlan(query.cacheKey);
  }

  Future<List<TransitItinerary>> planRoute(TransitPlanQuery query) async {
    try {
      final itineraries = await _api.planRoute(query);
      await _localStore.writeRoutePlan(query.cacheKey, itineraries);
      return itineraries;
    } on NetworkException {
      final cached = await _localStore.readRoutePlan(query.cacheKey);
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<List<Airport>?> cachedAirports(String query) {
    return _localStore.readAirportSearch(queryKey(query));
  }

  Future<List<Airport>> searchAirports(String query) async {
    if (query.trim().isEmpty) return const [];
    final key = queryKey(query);
    try {
      final results = await _api.searchAirports(query);
      await _localStore.writeAirportSearch(key, results);
      return results;
    } on NetworkException {
      final cached = await _localStore.readAirportSearch(key);
      if (cached != null) return cached;
      rethrow;
    }
  }
}
