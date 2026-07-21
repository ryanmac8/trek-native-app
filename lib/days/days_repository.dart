import '../network/api_exception.dart';
import 'day.dart';
import 'days_api.dart';
import 'days_local_store.dart';

/// Offline-first front door for a trip's day list (see
/// docs/offline-first.md) — screens should go through this, not [DaysApi]
/// directly, so the local cache stays the source of truth for what's shown.
///
/// This first slice of issue #4 is read-only (no day create/reorder/edit
/// yet), so unlike [TripsRepository] there's no pending-write queue to
/// reconcile — [refreshDays] is a plain fetch-and-cache with an
/// offline fallback.
///
/// - [cachedDays] never touches the network — safe to call for an instant
///   first paint.
/// - [refreshDays] fetches the real list; on [NetworkException] it falls
///   back to (and returns) the cache instead of failing, unless the cache
///   is empty, in which case the exception propagates so the caller can
///   show an explicit offline state.
class DaysRepository {
  DaysRepository({required DaysApi daysApi, required DaysLocalStore localStore})
    : _daysApi = daysApi,
      _localStore = localStore;

  final DaysApi _daysApi;
  final DaysLocalStore _localStore;

  Future<List<Day>> cachedDays(String tripId) => _localStore.read(tripId);

  Future<List<Day>> refreshDays(String tripId) async {
    try {
      final serverDays = await _daysApi.listDays(tripId);
      await _localStore.write(tripId, serverDays);
      return serverDays;
    } on NetworkException {
      final cached = await _localStore.read(tripId);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }
}
