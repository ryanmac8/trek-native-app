import '../network/api_exception.dart';
import 'packing_api.dart';
import 'packing_item.dart';
import 'packing_local_store.dart';

/// Offline-first front door for a trip's packing-list items (see
/// docs/offline-first.md) — screens should go through this, not
/// [PackingApi] directly, so the local cache stays the source of truth for
/// what's shown. Mirrors [BudgetRepository]'s pending-write shape,
/// trip-scoped like [PlacesRepository].
///
/// - [cachedItems] never touches the network — safe to call for an instant
///   first paint.
/// - [refreshItems] retries any pending (offline-created) items, then
///   fetches the real list; on [NetworkException] it falls back to (and
///   returns) the cache instead of failing, unless the cache is empty, in
///   which case the exception propagates so the caller can show an
///   explicit offline state.
/// - [createItem] writes an optimistic local item immediately and returns
///   it; if the create can't reach the server it stays queued in the cache
///   ([PackingItem.isPending]) and is retried by the next [refreshItems]
///   call (e.g. on screen load or pull-to-refresh) rather than lost.
class PackingRepository {
  PackingRepository({
    required PackingApi packingApi,
    required PackingLocalStore localStore,
  }) : _packingApi = packingApi,
       _localStore = localStore;

  final PackingApi _packingApi;
  final PackingLocalStore _localStore;

  Future<List<PackingItem>> cachedItems(String tripId) =>
      _localStore.read(tripId);

  Future<List<PackingItem>> refreshItems(String tripId) async {
    final afterRetry = await _retryPendingCreates(
      tripId,
      await _localStore.read(tripId),
    );

    try {
      final serverItems = await _packingApi.listItems(tripId);
      final serverIds = serverItems.map((item) => item.id).toSet();
      final merged = [
        ...serverItems,
        // Items this call just retried into existence (or that were
        // already pending) don't necessarily show up in `serverItems`
        // yet — e.g. the retry above raced this list call. Keep them
        // rather than silently dropping an item the user just created.
        ...afterRetry.where(
          (item) => item.isPending || !serverIds.contains(item.id),
        ),
      ];
      await _localStore.write(tripId, merged);
      return merged;
    } on NetworkException {
      await _localStore.write(tripId, afterRetry);
      if (afterRetry.isNotEmpty) return afterRetry;
      rethrow;
    }
  }

  Future<PackingItem> createItem(
    String tripId, {
    required String name,
    String? category,
  }) async {
    final pending = PackingItem(
      localId: 'local-${DateTime.now().microsecondsSinceEpoch}',
      tripId: tripId,
      name: name,
      category: category,
    );

    final cached = await _localStore.read(tripId);
    await _localStore.write(tripId, [...cached, pending]);

    try {
      final synced = await _packingApi.createItem(
        tripId,
        name: name,
        category: category,
      );
      final reconciled = _reconcile(pending, synced);
      await _localStore.write(tripId, [
        for (final item in [...cached, pending])
          if (item.localId == pending.localId) reconciled else item,
      ]);
      return reconciled;
    } on NetworkException {
      // Stays queued (pending) in the cache — refreshItems() retries it.
      return pending;
    } catch (_) {
      // A real rejection (validation, permissions, server error), not an
      // offline one — roll back the optimistic write rather than leave a
      // request that can never succeed sitting in the cache forever.
      await _localStore.write(tripId, cached);
      rethrow;
    }
  }

  Future<List<PackingItem>> _retryPendingCreates(
    String tripId,
    List<PackingItem> items,
  ) async {
    final result = <PackingItem>[];
    for (final item in items) {
      if (!item.isPending) {
        result.add(item);
        continue;
      }
      try {
        final synced = await _packingApi.createItem(
          tripId,
          name: item.name,
          category: item.category,
        );
        result.add(_reconcile(item, synced));
      } on NetworkException {
        result.add(item); // still offline — keep it queued
      }
    }
    return result;
  }

  PackingItem _reconcile(PackingItem pending, PackingItem synced) {
    return PackingItem(
      id: synced.id,
      localId: pending.localId,
      tripId: pending.tripId,
      name: synced.name,
      category: synced.category,
      checked: synced.checked,
    );
  }
}
