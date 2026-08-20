import '../network/api_exception.dart';
import 'todo_api.dart';
import 'todo_item.dart';
import 'todo_local_store.dart';

/// Offline-first front door for a trip's todo-list items (see
/// docs/offline-first.md) — screens should go through this, not [TodoApi]
/// directly, so the local cache stays the source of truth for what's shown.
/// Mirrors [PackingRepository]'s pending-write shape, trip-scoped the same
/// way.
///
/// - [cachedItems] never touches the network — safe to call for an instant
///   first paint.
/// - [refreshItems] retries any pending (offline-created or offline-toggled)
///   items, then fetches the real list; on [NetworkException] it falls back
///   to (and returns) the cache instead of failing, unless the cache is
///   empty, in which case the exception propagates so the caller can show
///   an explicit offline state.
/// - [createItem] writes an optimistic local item immediately and returns
///   it; if the create can't reach the server it stays queued in the cache
///   ([TodoItem.isPending]) and is retried by the next [refreshItems] call
///   (e.g. on screen load or pull-to-refresh) rather than lost.
/// - [toggleChecked] flips an item's checked state in the cache immediately
///   and returns it; if the update can't reach the server it stays queued
///   ([TodoItem.pendingChecked]) and is retried the same way.
class TodoRepository {
  TodoRepository({required TodoApi todoApi, required TodoLocalStore localStore})
    : _todoApi = todoApi,
      _localStore = localStore;

  final TodoApi _todoApi;
  final TodoLocalStore _localStore;

  Future<List<TodoItem>> cachedItems(String tripId) => _localStore.read(tripId);

  Future<List<TodoItem>> refreshItems(String tripId) async {
    final afterRetry = await _retryPending(
      tripId,
      await _localStore.read(tripId),
    );

    try {
      final serverItems = await _todoApi.listItems(tripId);
      final serverIds = serverItems.map((item) => item.id).toSet();
      // A toggle that's still queued (offline) would otherwise be
      // overwritten by the server's stale `checked` value below.
      final stillPendingToggles = {
        for (final item in afterRetry)
          if (!item.isPending && item.pendingChecked) item.id: item,
      };
      final merged = [
        for (final serverItem in serverItems)
          stillPendingToggles[serverItem.id] ?? serverItem,
        // Items this call just retried into existence (or that were
        // already pending) don't necessarily show up in `serverItems` yet
        // — e.g. the retry above raced this list call. Keep them rather
        // than silently dropping an item the user just created.
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

  /// Optimistically flips [item]'s checked state in the cache immediately,
  /// then tries to sync it. Mirrors [createItem]'s shape:
  ///
  /// - Can't reach the server ([NetworkException]): the flip stays in the
  ///   cache with [TodoItem.pendingChecked] set, and the next [refreshItems]
  ///   call retries it.
  /// - A genuine rejection (not found, permissions, server error): the
  ///   optimistic flip is rolled back and the error rethrown.
  Future<TodoItem> toggleChecked(String tripId, TodoItem item) async {
    assert(!item.isPending, 'cannot toggle an item that has not synced yet');

    final optimistic = item.copyWithChecked(
      !item.checked,
      pendingChecked: true,
    );
    await _replace(tripId, item.localId, optimistic);

    try {
      final synced = await _todoApi.updateChecked(
        tripId,
        id: item.id!,
        checked: optimistic.checked,
      );
      final reconciled = optimistic.copyWithChecked(synced.checked);
      await _replace(tripId, item.localId, reconciled);
      return reconciled;
    } on NetworkException {
      return optimistic; // stays queued; refreshItems() retries it.
    } catch (_) {
      await _replace(tripId, item.localId, item);
      rethrow;
    }
  }

  Future<void> _replace(
    String tripId,
    String localId,
    TodoItem replacement,
  ) async {
    final cached = await _localStore.read(tripId);
    await _localStore.write(tripId, [
      for (final cachedItem in cached)
        if (cachedItem.localId == localId) replacement else cachedItem,
    ]);
  }

  Future<TodoItem> createItem(
    String tripId, {
    required String name,
    String? category,
  }) async {
    final pending = TodoItem(
      localId: 'local-${DateTime.now().microsecondsSinceEpoch}',
      tripId: tripId,
      name: name,
      category: category,
    );

    final cached = await _localStore.read(tripId);
    await _localStore.write(tripId, [...cached, pending]);

    try {
      final synced = await _todoApi.createItem(
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

  /// Retries every not-yet-synced item in [items] — both offline-created
  /// items ([TodoItem.isPending]) and offline checked/unchecked toggles
  /// ([TodoItem.pendingChecked]) — before [refreshItems] fetches the real
  /// list. An item can only be in one of those two states at a time: a
  /// pending-create item isn't toggleable yet (see [toggleChecked]).
  Future<List<TodoItem>> _retryPending(
    String tripId,
    List<TodoItem> items,
  ) async {
    final result = <TodoItem>[];
    for (final item in items) {
      if (item.isPending) {
        try {
          final synced = await _todoApi.createItem(
            tripId,
            name: item.name,
            category: item.category,
          );
          result.add(_reconcile(item, synced));
        } on NetworkException {
          result.add(item); // still offline — keep it queued
        }
        continue;
      }
      if (item.pendingChecked) {
        try {
          final synced = await _todoApi.updateChecked(
            tripId,
            id: item.id!,
            checked: item.checked,
          );
          result.add(item.copyWithChecked(synced.checked));
        } on NetworkException {
          result.add(item); // still offline — keep it queued
        }
        continue;
      }
      result.add(item);
    }
    return result;
  }

  TodoItem _reconcile(TodoItem pending, TodoItem synced) {
    return TodoItem(
      id: synced.id,
      localId: pending.localId,
      tripId: pending.tripId,
      name: synced.name,
      category: synced.category,
      checked: synced.checked,
    );
  }
}
