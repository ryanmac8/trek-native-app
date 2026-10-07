import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_exception.dart';
import 'addon_flags.dart';
import 'addon_flags_repository.dart';

/// Where the current [AddonFlagsState.flags] came from.
enum AddonFlagsSource {
  /// Nothing fetched or cached yet: [AddonFlags.freshInstallDefaults].
  defaults,

  /// The last flags fetched from this server, read from the local cache.
  cache,

  /// Fetched from the server during this app session.
  server,
}

class AddonFlagsState {
  const AddonFlagsState({
    required this.flags,
    required this.source,
    this.fetchedAt,
    this.refreshFailed = false,
  });

  static const initial = AddonFlagsState(
    flags: AddonFlags.freshInstallDefaults,
    source: AddonFlagsSource.defaults,
  );

  final AddonFlags flags;
  final AddonFlagsSource source;

  /// When [flags] were fetched from the server; `null` for defaults.
  final DateTime? fetchedAt;

  /// The most recent refresh attempt failed (offline, 401, server error);
  /// [flags] are whatever was there before it.
  final bool refreshFailed;

  bool isEnabled(String addonId) => flags.isEnabled(addonId);
}

/// Holds the instance's add-on flags for the UI. Never blocks on the
/// network: it starts at [AddonFlagsState.initial], swaps in the cached
/// flags as soon as they're read, then replaces them with a background
/// refresh. A failed refresh keeps the current flags and sets
/// [AddonFlagsState.refreshFailed].
class AddonFlagsController extends Notifier<AddonFlagsState> {
  AddonFlagsController(this._repository);

  final AddonFlagsRepository Function(Ref ref) _repository;
  late AddonFlagsRepository _repo;

  @override
  AddonFlagsState build() {
    _repo = _repository(ref);
    _loadCachedThenRefresh();
    return AddonFlagsState.initial;
  }

  Future<void> _loadCachedThenRefresh() async {
    final cached = await _repo.cachedFlags();
    if (!ref.mounted) return;
    if (cached != null && state.source == AddonFlagsSource.defaults) {
      state = AddonFlagsState(
        flags: cached.flags,
        source: AddonFlagsSource.cache,
        fetchedAt: cached.fetchedAt,
      );
    }
    await refresh();
  }

  /// Re-fetches the flags from the server. Offline, HTTP, and malformed-
  /// response failures are absorbed into [AddonFlagsState.refreshFailed].
  Future<void> refresh() async {
    try {
      final fresh = await _repo.refreshFlags();
      if (!ref.mounted) return;
      state = AddonFlagsState(
        flags: fresh.flags,
        source: AddonFlagsSource.server,
        fetchedAt: fresh.fetchedAt,
      );
    } on ApiException {
      _markRefreshFailed();
    } on FormatException {
      _markRefreshFailed();
    }
  }

  void _markRefreshFailed() {
    if (!ref.mounted) return;
    state = AddonFlagsState(
      flags: state.flags,
      source: state.source,
      fetchedAt: state.fetchedAt,
      refreshFailed: true,
    );
  }
}
