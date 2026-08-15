import '../network/api_exception.dart';
import 'budget_api.dart';
import 'budget_item.dart';
import 'budget_local_store.dart';

/// Offline-first front door for a trip's budget items (see
/// docs/offline-first.md) — screens should go through this, not [BudgetApi]
/// directly, so the local cache stays the source of truth for what's shown.
/// Mirrors [TagsRepository]'s pending-write shape, trip-scoped like
/// [PlacesRepository].
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
///   ([BudgetItem.isPending]) and is retried by the next [refreshItems]
///   call (e.g. on screen load or pull-to-refresh) rather than lost.
class BudgetRepository {
  BudgetRepository({
    required BudgetApi budgetApi,
    required BudgetLocalStore localStore,
  }) : _budgetApi = budgetApi,
       _localStore = localStore;

  final BudgetApi _budgetApi;
  final BudgetLocalStore _localStore;

  Future<List<BudgetItem>> cachedItems(String tripId) =>
      _localStore.read(tripId);

  Future<List<BudgetItem>> refreshItems(String tripId) async {
    final afterRetry = await _retryPendingCreates(
      tripId,
      await _localStore.read(tripId),
    );

    try {
      final serverItems = await _budgetApi.listItems(tripId);
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

  Future<BudgetItem> createItem(
    String tripId, {
    required String name,
    String? category,
    double? totalPrice,
    int? persons,
    int? days,
    String? note,
    String? expenseDate,
  }) async {
    final pending = BudgetItem(
      localId: 'local-${DateTime.now().microsecondsSinceEpoch}',
      tripId: tripId,
      name: name,
      category: category,
      totalPrice: totalPrice,
      persons: persons,
      days: days,
      note: note,
      expenseDate: expenseDate,
    );

    final cached = await _localStore.read(tripId);
    await _localStore.write(tripId, [...cached, pending]);

    try {
      final synced = await _budgetApi.createItem(
        tripId,
        name: name,
        category: category,
        totalPrice: totalPrice,
        persons: persons,
        days: days,
        note: note,
        expenseDate: expenseDate,
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

  Future<List<BudgetItem>> _retryPendingCreates(
    String tripId,
    List<BudgetItem> items,
  ) async {
    final result = <BudgetItem>[];
    for (final item in items) {
      if (!item.isPending) {
        result.add(item);
        continue;
      }
      try {
        final synced = await _budgetApi.createItem(
          tripId,
          name: item.name,
          category: item.category,
          totalPrice: item.totalPrice,
          persons: item.persons,
          days: item.days,
          note: item.note,
          expenseDate: item.expenseDate,
        );
        result.add(_reconcile(item, synced));
      } on NetworkException {
        result.add(item); // still offline — keep it queued
      }
    }
    return result;
  }

  BudgetItem _reconcile(BudgetItem pending, BudgetItem synced) {
    return BudgetItem(
      id: synced.id,
      localId: pending.localId,
      tripId: pending.tripId,
      name: synced.name,
      category: synced.category,
      totalPrice: synced.totalPrice,
      currency: synced.currency,
      persons: synced.persons,
      days: synced.days,
      note: synced.note,
      expenseDate: synced.expenseDate,
    );
  }
}
