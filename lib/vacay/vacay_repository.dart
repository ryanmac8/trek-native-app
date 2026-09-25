import 'vacay_api.dart';
import 'vacay_local_store.dart';
import 'vacay_models.dart';

/// Offline-first front door for Vacay (see docs/offline-first.md). The
/// Vacay screen uses this, not [VacayApi] directly.
///
/// - [cachedPlan] / [cachedYear] never touch the network, so the screen
///   can paint the last-known plan and year instantly.
/// - [refreshPlan] / [refreshYear] fetch fresh data, write it to the cache,
///   and return it. A `NetworkException` propagates: the screen keeps
///   showing whatever the cached reads returned, marked as stale, or shows
///   an explicit offline state if it has nothing cached.
///
/// All four are scoped to the current account via [cacheScope]; with no
/// scope (no live session) nothing is read from or written to the cache.
///
/// An `UnauthorizedException` from a refresh also propagates: the shared
/// client has already cleared the session, and the router redirects to
/// login.
class VacayRepository {
  VacayRepository({
    required VacayApi vacayApi,
    required VacayLocalStore localStore,
    required Future<String?> Function() cacheScope,
    DateTime Function()? clock,
  }) : _api = vacayApi,
       _localStore = localStore,
       _cacheScope = cacheScope,
       _clock = clock ?? DateTime.now;

  final VacayApi _api;
  final VacayLocalStore _localStore;
  final Future<String?> Function() _cacheScope;
  final DateTime Function() _clock;

  Future<CachedVacay<VacayPlan>?> cachedPlan() async {
    final scope = await _cacheScope();
    if (scope == null) return null;
    return _localStore.readPlan(scope);
  }

  Future<CachedVacay<VacayPlan>> refreshPlan() async {
    final scope = await _cacheScope();
    final plan = await _api.fetchPlan();
    final cached = CachedVacay(value: plan, fetchedAt: _clock());
    if (scope != null) await _localStore.writePlan(scope, cached);
    return cached;
  }

  Future<CachedVacay<VacayYear>?> cachedYear(int year) async {
    final scope = await _cacheScope();
    if (scope == null) return null;
    return _localStore.readYear(scope, year);
  }

  Future<CachedVacay<VacayYear>> refreshYear(int year) async {
    final scope = await _cacheScope();
    final data = await _api.fetchYear(year);
    final cached = CachedVacay(value: data, fetchedAt: _clock());
    if (scope != null) await _localStore.writeYear(scope, cached);
    return cached;
  }
}
