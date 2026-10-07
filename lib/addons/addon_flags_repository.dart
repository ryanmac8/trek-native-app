import 'addon_flags.dart';
import 'addon_flags_local_store.dart';
import 'addons_api.dart';

/// Offline-first front door for the instance's add-on flags (see
/// docs/offline-first.md and docs/feature-flags.md).
///
/// - [cachedFlags] never touches the network and never throws: a storage
///   failure reads as "nothing cached".
/// - [refreshFlags] fetches fresh flags, caches them (best-effort — a failed
///   cache write doesn't fail the refresh), and returns them. Any
///   `ApiException` (offline, 401, 5xx) propagates to the caller, which keeps
///   whatever it already had.
///
/// Both are scoped to the configured server via [cacheScope]; with no scope
/// (no server configured) nothing is read from or written to the cache.
class AddonFlagsRepository {
  AddonFlagsRepository({
    required AddonsApi addonsApi,
    required AddonFlagsLocalStore localStore,
    required Future<String?> Function() cacheScope,
    DateTime Function()? clock,
  }) : _api = addonsApi,
       _localStore = localStore,
       _cacheScope = cacheScope,
       _clock = clock ?? DateTime.now;

  final AddonsApi _api;
  final AddonFlagsLocalStore _localStore;
  final Future<String?> Function() _cacheScope;
  final DateTime Function() _clock;

  Future<CachedAddonFlags?> cachedFlags() async {
    try {
      final scope = await _cacheScope();
      if (scope == null) return null;
      return await _localStore.read(scope);
    } on Object {
      return null;
    }
  }

  Future<CachedAddonFlags> refreshFlags() async {
    final flags = await _api.fetchFlags();
    final cached = CachedAddonFlags(flags: flags, fetchedAt: _clock());
    try {
      final scope = await _cacheScope();
      if (scope != null) await _localStore.write(scope, cached);
    } on Object {
      // The fresh flags are still returned; the cache just stays older.
    }
    return cached;
  }
}
