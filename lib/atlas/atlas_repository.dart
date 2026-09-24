import 'atlas_api.dart';
import 'atlas_local_store.dart';
import 'atlas_models.dart';

/// Offline-first front door for Atlas stats (see docs/offline-first.md).
/// The Atlas screen uses this, not [AtlasApi] directly.
///
/// - [cachedStats] never touches the network, so the screen can paint the
///   last-known stats instantly.
/// - [refreshStats] fetches fresh stats, writes them to the cache, and
///   returns them. A `NetworkException` propagates: the screen keeps
///   showing whatever [cachedStats] returned, marked as stale, or shows an
///   explicit offline state if it has nothing cached.
///
/// Both are scoped to the current account via [cacheScope]; with no scope
/// (no live session) nothing is read from or written to the cache.
///
/// An `UnauthorizedException` from [refreshStats] also propagates: the
/// shared client has already cleared the session, and the router redirects
/// to login.
class AtlasRepository {
  AtlasRepository({
    required AtlasApi atlasApi,
    required AtlasLocalStore localStore,
    required Future<String?> Function() cacheScope,
    DateTime Function()? clock,
  }) : _api = atlasApi,
       _localStore = localStore,
       _cacheScope = cacheScope,
       _clock = clock ?? DateTime.now;

  final AtlasApi _api;
  final AtlasLocalStore _localStore;
  final Future<String?> Function() _cacheScope;
  final DateTime Function() _clock;

  Future<CachedAtlasStats?> cachedStats() async {
    final scope = await _cacheScope();
    if (scope == null) return null;
    return _localStore.read(scope);
  }

  Future<CachedAtlasStats> refreshStats() async {
    final scope = await _cacheScope();
    final stats = await _api.fetchStats();
    final cached = CachedAtlasStats(stats: stats, fetchedAt: _clock());
    if (scope != null) await _localStore.write(scope, cached);
    return cached;
  }
}
