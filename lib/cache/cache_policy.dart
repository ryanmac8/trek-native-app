import 'cache_entry.dart';

/// Per-resource rules for when cached data needs revalidating and when it
/// can no longer be used at all.
///
/// Age never hides data: a stale entry is still shown (offline, it's all
/// there is) while a revalidation runs. Only a [schemaVersion] mismatch
/// makes an entry unusable.
class CachePolicy {
  const CachePolicy({
    this.maxAge = const Duration(minutes: 5),
    this.schemaVersion = 1,
  });

  static const standard = CachePolicy();

  /// How long after [CacheEntry.fetchedAt] the data counts as fresh.
  /// [Duration.zero] revalidates on every watch.
  final Duration maxAge;

  /// Bump when a resource's cached JSON shape or decoder changes
  /// incompatibly; entries written under another version are discarded.
  final int schemaVersion;

  bool accepts(CacheEntry entry) => entry.schemaVersion == schemaVersion;

  bool isStale(CacheEntry entry, DateTime now) =>
      entry.invalidated || now.difference(entry.fetchedAt) >= maxAge;
}
