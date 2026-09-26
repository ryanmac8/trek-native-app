import 'journey_api.dart';
import 'journey_local_store.dart';
import 'journey_models.dart';

/// Offline-first front door for Journey (see docs/offline-first.md). The
/// Journey screens use this, not [JourneyApi] directly.
///
/// - [cachedList] / [cachedJourney] never touch the network, so screens
///   can paint the last-known data instantly.
/// - [refreshList] / [refreshJourney] fetch fresh data, write it to the
///   cache, and return it. A `NetworkException` propagates: the screen
///   keeps showing whatever the cached reads returned, marked as stale, or
///   shows an explicit offline state if it has nothing cached.
///
/// All four are scoped to the current account via [cacheScope]; with no
/// scope (no live session) nothing is read from or written to the cache.
///
/// An `UnauthorizedException` from a refresh also propagates: the shared
/// client has already cleared the session, and the router redirects to
/// login.
class JourneyRepository {
  JourneyRepository({
    required JourneyApi journeyApi,
    required JourneyLocalStore localStore,
    required Future<String?> Function() cacheScope,
    DateTime Function()? clock,
  }) : _api = journeyApi,
       _localStore = localStore,
       _cacheScope = cacheScope,
       _clock = clock ?? DateTime.now;

  final JourneyApi _api;
  final JourneyLocalStore _localStore;
  final Future<String?> Function() _cacheScope;
  final DateTime Function() _clock;

  Future<CachedJourney<JourneyList>?> cachedList() async {
    final scope = await _cacheScope();
    if (scope == null) return null;
    return _localStore.readList(scope);
  }

  Future<CachedJourney<JourneyList>> refreshList() async {
    final scope = await _cacheScope();
    final list = await _api.fetchJourneys();
    final cached = CachedJourney(value: list, fetchedAt: _clock());
    if (scope != null) await _localStore.writeList(scope, cached);
    return cached;
  }

  Future<CachedJourney<JourneyDetail>?> cachedJourney(int id) async {
    final scope = await _cacheScope();
    if (scope == null) return null;
    return _localStore.readJourney(scope, id);
  }

  Future<CachedJourney<JourneyDetail>> refreshJourney(int id) async {
    final scope = await _cacheScope();
    final journey = await _api.fetchJourney(id);
    final cached = CachedJourney(value: journey, fetchedAt: _clock());
    if (scope != null) await _localStore.writeJourney(scope, cached);
    return cached;
  }
}
