import '../network/api_exception.dart';
import 'tag.dart';
import 'tags_api.dart';
import 'tags_local_store.dart';

/// Offline-first front door for tag reads and writes (see
/// docs/offline-first.md) — screens should go through this, not [TagsApi]
/// directly, so the local cache stays the source of truth for what's shown.
/// Mirrors [TripsRepository]'s shape.
///
/// - [cachedTags] never touches the network — safe to call for an instant
///   first paint.
/// - [refreshTags] retries any pending offline creates, then fetches the
///   real list; on [NetworkException] it falls back to (and returns) the
///   cache instead of failing, unless the cache is empty, in which case the
///   exception propagates so the caller can show an explicit offline state.
/// - [createTag] writes an optimistic local tag immediately and returns it;
///   if the create can't reach the server it stays queued in the cache
///   ([Tag.isPending]) and is retried by the next [refreshTags] call (e.g.
///   on screen load or pull-to-refresh) rather than lost.
class TagsRepository {
  TagsRepository({required TagsApi tagsApi, required TagsLocalStore localStore})
    : _tagsApi = tagsApi,
      _localStore = localStore;

  final TagsApi _tagsApi;
  final TagsLocalStore _localStore;

  Future<List<Tag>> cachedTags() => _localStore.read();

  Future<List<Tag>> refreshTags() async {
    final afterRetry = await _retryPendingCreates(await _localStore.read());

    try {
      final serverTags = await _tagsApi.listTags();
      final serverIds = serverTags.map((tag) => tag.id).toSet();
      final merged = [
        ...serverTags,
        // Tags this call just retried into existence (or that were already
        // pending) don't necessarily show up in `serverTags` yet — e.g. the
        // retry above raced this list call. Keep them rather than silently
        // dropping a tag the user just created.
        ...afterRetry.where(
          (tag) => tag.isPending || !serverIds.contains(tag.id),
        ),
      ];
      await _localStore.write(merged);
      return merged;
    } on NetworkException {
      await _localStore.write(afterRetry);
      if (afterRetry.isNotEmpty) return afterRetry;
      rethrow;
    }
  }

  Future<Tag> createTag({required String name, String? color}) async {
    final pending = Tag(
      localId: 'local-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      color: color,
    );

    final cached = await _localStore.read();
    await _localStore.write([...cached, pending]);

    try {
      final synced = await _tagsApi.createTag(name: name, color: color);
      final reconciled = _reconcile(pending, synced);
      await _localStore.write([
        for (final tag in [...cached, pending])
          if (tag.localId == pending.localId) reconciled else tag,
      ]);
      return reconciled;
    } on NetworkException {
      // Stays queued (pending) in the cache — refreshTags() retries it.
      return pending;
    } catch (_) {
      // A real rejection (validation, permissions, server error), not an
      // offline one — roll back the optimistic write rather than leave a
      // request that can never succeed sitting in the cache forever.
      await _localStore.write(cached);
      rethrow;
    }
  }

  Future<List<Tag>> _retryPendingCreates(List<Tag> tags) async {
    final result = <Tag>[];
    for (final tag in tags) {
      if (!tag.isPending) {
        result.add(tag);
        continue;
      }
      try {
        final synced = await _tagsApi.createTag(
          name: tag.name,
          color: tag.color,
        );
        result.add(_reconcile(tag, synced));
      } on NetworkException {
        result.add(tag); // still offline — keep it queued
      }
    }
    return result;
  }

  Tag _reconcile(Tag pending, Tag synced) {
    return Tag(
      id: synced.id,
      localId: pending.localId,
      name: synced.name,
      color: synced.color,
    );
  }
}
