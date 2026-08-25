import '../network/api_exception.dart';
import 'share_api.dart';
import 'share_link.dart';
import 'share_local_store.dart';

/// Offline-first front door for a trip's share link (see
/// docs/offline-first.md) — screens should go through this, not [ShareApi]
/// directly, so the local cache stays the source of truth for what's shown.
/// Trip-scoped like [CollabRepository], but for a single optional resource
/// instead of a list — there's at most one [ShareLink] per trip.
///
/// - [cachedShareLink] never touches the network — safe to call for an
///   instant first paint.
/// - [refreshShareLink] retries a not-yet-confirmed enable/update/disable,
///   then fetches the real state; on [NetworkException] it falls back to
///   (and returns) the cache instead of failing, unless nothing has ever
///   been cached, in which case the exception propagates so the caller can
///   show an explicit offline state.
/// - [setSharing] enables sharing (or updates its permissions if already
///   enabled) — it writes the optimistic state to the cache immediately and
///   returns it; if the request can't reach the server, the change stays
///   queued ([ShareLink.needsSync]) and is retried by the next
///   [refreshShareLink] call rather than lost.
/// - [disableSharing] applies the same optimistic-write pattern in reverse:
///   the link is hidden ([ShareLink.isEnabled] false) immediately but kept
///   in the cache, tombstoned ([ShareLink.pendingDelete]), until the
///   `DELETE` actually confirms.
class ShareRepository {
  ShareRepository({
    required ShareApi shareApi,
    required ShareLocalStore localStore,
  }) : _shareApi = shareApi,
       _localStore = localStore;

  final ShareApi _shareApi;
  final ShareLocalStore _localStore;

  Future<ShareLink?> cachedShareLink(String tripId) => _localStore.read(tripId);

  Future<ShareLink?> refreshShareLink(String tripId) async {
    final afterRetry = await _retryPendingWrite(
      tripId,
      await _localStore.read(tripId),
    );

    try {
      final serverLink = await _shareApi.getShareLink(tripId);
      // A retry above (or a write still in flight when this call started)
      // hasn't necessarily landed server-side yet by the time this GET
      // fires — keep the local, not-yet-confirmed state rather than
      // overwriting it with a possibly-stale server response.
      final result = _preferLocalIfPending(afterRetry, serverLink);
      await _localStore.write(tripId, result);
      return result?.pendingDelete == true ? null : result;
    } on NetworkException {
      await _localStore.write(tripId, afterRetry);
      if (afterRetry == null) rethrow;
      return afterRetry.pendingDelete ? null : afterRetry;
    }
  }

  ShareLink? _preferLocalIfPending(ShareLink? local, ShareLink? server) {
    if (local != null && (local.needsSync || local.pendingDelete)) {
      return local;
    }
    return server;
  }

  Future<ShareLink> setSharing(
    String tripId, {
    bool shareMap = true,
    bool shareBookings = true,
    bool sharePacking = false,
    bool shareBudget = false,
    bool shareCollab = false,
  }) async {
    final cached = await _localStore.read(tripId);
    final pending = ShareLink(
      tripId: tripId,
      // Keep the existing token (if any) visible while an update to an
      // already-enabled link is syncing — only a brand-new enable has none.
      token: cached?.pendingDelete == true ? null : cached?.token,
      shareMap: shareMap,
      shareBookings: shareBookings,
      sharePacking: sharePacking,
      shareBudget: shareBudget,
      shareCollab: shareCollab,
      needsSync: true,
    );
    await _localStore.write(tripId, pending);

    try {
      final synced = await _shareApi.createOrUpdateShareLink(
        tripId,
        shareMap: shareMap,
        shareBookings: shareBookings,
        sharePacking: sharePacking,
        shareBudget: shareBudget,
        shareCollab: shareCollab,
      );
      await _localStore.write(tripId, synced);
      return synced;
    } on NetworkException {
      // Stays queued (needsSync) — refreshShareLink() retries it.
      return pending;
    } catch (_) {
      // A real rejection (permissions, a 5xx), not an offline one — roll
      // back the optimistic write rather than leave a request that can
      // never succeed sitting in the cache forever.
      await _localStore.write(tripId, cached);
      rethrow;
    }
  }

  /// Disables sharing. A no-op if sharing isn't currently enabled (nothing
  /// cached, or a not-yet-synced enable that hasn't produced a token yet —
  /// in that case the still-pending [setSharing] retry is what needs to
  /// resolve first).
  Future<void> disableSharing(String tripId) async {
    final cached = await _localStore.read(tripId);
    if (cached == null || cached.pendingDelete) return;

    await _localStore.write(tripId, cached.copyWith(pendingDelete: true));

    try {
      await _shareApi.deleteShareLink(tripId);
      await _localStore.write(tripId, null);
    } on NetworkException {
      // Stays tombstoned (hidden from the UI) — refreshShareLink() retries it.
    } catch (_) {
      // A real rejection, not an offline one — roll back.
      await _localStore.write(tripId, cached);
      rethrow;
    }
  }

  /// Retries a not-yet-confirmed write before [refreshShareLink] fetches
  /// the real state: an offline disable ([ShareLink.pendingDelete]) or an
  /// offline enable/update ([ShareLink.needsSync]).
  Future<ShareLink?> _retryPendingWrite(String tripId, ShareLink? link) async {
    if (link == null) return null;

    if (link.pendingDelete) {
      try {
        await _shareApi.deleteShareLink(tripId);
        return null; // synced — cache cleared
      } on NetworkException {
        return link; // still offline — keep it tombstoned
      }
    }

    if (link.needsSync) {
      try {
        return await _shareApi.createOrUpdateShareLink(
          tripId,
          shareMap: link.shareMap,
          shareBookings: link.shareBookings,
          sharePacking: link.sharePacking,
          shareBudget: link.shareBudget,
          shareCollab: link.shareCollab,
        );
      } on NetworkException {
        return link; // still offline — keep it queued
      }
    }

    return link;
  }
}
