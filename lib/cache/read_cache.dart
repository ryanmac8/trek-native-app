import 'dart:async';

import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'cache_entry.dart';
import 'cache_policy.dart';
import 'cache_store.dart';

/// Where a [CacheSnapshot]'s data came from.
enum CacheSource {
  /// Nothing cached and nothing fetched yet.
  none,

  /// Read from local storage; not yet confirmed by the server during this
  /// app session.
  cache,

  /// Fetched or revalidated (304) from the server during this app session.
  server,
}

/// What a screen renders for one cached resource: the data (if any), how
/// old it is, and how the latest revalidation went.
class CacheSnapshot<T> {
  const CacheSnapshot({
    this.data,
    this.fetchedAt,
    this.source = CacheSource.none,
    this.isStale = false,
    this.isRefreshing = false,
    this.refreshError,
  });

  final T? data;
  final DateTime? fetchedAt;
  final CacheSource source;

  /// Past the policy's `maxAge`, or explicitly invalidated. Still shown.
  final bool isStale;

  /// A revalidation for this resource is in flight.
  final bool isRefreshing;

  /// Why the latest revalidation failed (`ApiException`,
  /// `FormatException`, …); `null` if it succeeded or none has run.
  final Object? refreshError;

  bool get hasData => source != CacheSource.none;

  /// The latest revalidation got no HTTP response at all.
  bool get isOffline => refreshError is NetworkException;

  CacheSnapshot<T> copyWith({
    bool? isRefreshing,
    Object? Function()? refreshError,
  }) {
    return CacheSnapshot<T>(
      data: data,
      fetchedAt: fetchedAt,
      source: source,
      isStale: isStale,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      refreshError: refreshError == null ? this.refreshError : refreshError(),
    );
  }
}

/// Describes one cacheable server read: its cache [key], how to fetch it,
/// and how to convert between its JSON and the feature's model.
class CacheResource<T> {
  const CacheResource({
    required this.key,
    required this.fetch,
    required this.decode,
    required this.encode,
    this.policy = CachePolicy.standard,
  });

  /// A plain conditional `GET` of [path] through [client].
  CacheResource.get(
    ApiClient client,
    String path, {
    required this.key,
    required this.decode,
    required this.encode,
    Map<String, dynamic>? query,
    this.policy = CachePolicy.standard,
  }) : fetch = ((etag) => client.getIfChanged(path, query: query, etag: etag));

  /// Path-like and unique per resource, e.g. `trips` or `trips/20/days`, so
  /// prefix invalidation (`trips/20/`) can target everything under a trip.
  final String key;

  /// Fetches the resource, sending [etag] as `If-None-Match` when non-null.
  final Future<ConditionalResponse> Function(String? etag) fetch;

  /// Turns cached/server JSON into the model. Throwing marks the JSON as
  /// unusable: a cached entry reads as a miss, a server body as a failed
  /// refresh.
  final T Function(Object? json) decode;

  /// Turns the model back into JSON, for [ReadCache.put].
  final Object? Function(T value) encode;

  final CachePolicy policy;
}

enum _EventKind { changed, refreshStarted, refreshFinished }

class _CacheEvent {
  const _CacheEvent(this.kind, [this.error]);

  final _EventKind kind;
  final Object? error;
}

/// The app's shared, feature-agnostic read cache: stale-while-revalidate
/// over [CacheStore], scoped per server account (see
/// docs/local-cache.md).
///
/// Nothing here throws to callers. Storage failures read as misses, and
/// fetch failures are reported through [CacheSnapshot.refreshError] while
/// the cached data stays in place.
class ReadCache {
  ReadCache({
    required CacheStore store,
    required Future<String?> Function() scope,
    DateTime Function()? clock,
  }) : _store = store,
       _scope = scope,
       _clock = clock ?? DateTime.now;

  final CacheStore _store;
  final Future<String?> Function() _scope;
  final DateTime Function() _clock;

  /// Write-through mirror of the store, so a failed persistent write never
  /// hides fresh data from this session.
  final Map<String, CacheEntry> _memory = {};

  /// Storage keys the server has confirmed during this session.
  final Set<String> _confirmed = {};

  final Map<String, Future<void>> _inFlight = {};
  final Map<String, Object?> _lastError = {};
  final Map<String, StreamController<_CacheEvent>> _events = {};

  /// Scope used with no server configured or nobody logged in: kept in
  /// memory only, never persisted.
  static const _unscoped = '';

  Future<String> _currentScope() async {
    try {
      return await _scope() ?? _unscoped;
    } on Object {
      return _unscoped;
    }
  }

  static String _storageKey(String scope, String key) => '$scope|$key';

  static bool _persisted(String storageKey) =>
      !storageKey.startsWith('$_unscoped|');

  Future<String> _storageKeyFor(String key) async =>
      _storageKey(await _currentScope(), key);

  /// The cached snapshot for [resource], without touching the network.
  Future<CacheSnapshot<T>> read<T>(CacheResource<T> resource) async =>
      _read(await _storageKeyFor(resource.key), resource);

  /// Revalidates [resource] against the server and returns the resulting
  /// snapshot. Concurrent calls for the same resource share one request.
  ///
  /// - 200: the body replaces the cached entry.
  /// - 304: the cached entry's `fetchedAt` moves to now.
  /// - 403, or 404: the entry is evicted (access revoked or the resource is
  ///   gone) and the snapshot has no data.
  /// - Anything else (offline, 401, 5xx, an undecodable body): the cached
  ///   entry is kept and the error is reported in
  ///   [CacheSnapshot.refreshError].
  Future<CacheSnapshot<T>> refresh<T>(CacheResource<T> resource) async {
    final storageKey = await _storageKeyFor(resource.key);
    await (_inFlight[storageKey] ??= _revalidate(storageKey, resource)
        .whenComplete(() {
          _inFlight.remove(storageKey);
        }));
    final snapshot = await _read(storageKey, resource);
    return snapshot.copyWith(refreshError: () => _lastError[storageKey]);
  }

  /// Emits the cached snapshot first, then a new snapshot whenever the
  /// entry changes or a revalidation starts or finishes. Revalidates on
  /// listen when nothing usable is cached or the entry is stale.
  Stream<CacheSnapshot<T>> watch<T>(CacheResource<T> resource) {
    late final StreamController<CacheSnapshot<T>> out;
    StreamSubscription<_CacheEvent>? events;
    var cancelled = false;
    var first = true;
    var refreshing = false;
    Object? error;
    var queue = Future<void>.value();

    // Emissions are chained so they reach the listener in event order.
    void emitLatest(String storageKey) {
      queue = queue.then((_) async {
        final snapshot = await _read(storageKey, resource);
        if (cancelled) return;
        out.add(
          snapshot.copyWith(
            isRefreshing: refreshing,
            refreshError: () => error,
          ),
        );
        if (first) {
          first = false;
          if (!snapshot.hasData || snapshot.isStale) {
            unawaited(refresh(resource));
          }
        }
      });
    }

    out = StreamController<CacheSnapshot<T>>(
      onListen: () async {
        final storageKey = await _storageKeyFor(resource.key);
        if (cancelled) return;
        refreshing = _inFlight.containsKey(storageKey);
        error = _lastError[storageKey];
        events = _channel(storageKey).stream.listen((event) {
          switch (event.kind) {
            case _EventKind.refreshStarted:
              refreshing = true;
            case _EventKind.refreshFinished:
              refreshing = false;
              error = event.error;
            case _EventKind.changed:
              break;
          }
          emitLatest(storageKey);
        });
        emitLatest(storageKey);
      },
      onCancel: () {
        cancelled = true;
        return events?.cancel();
      },
    );
    return out.stream;
  }

  /// Replaces [resource]'s cached data with a local edit. The entry keeps
  /// its `fetchedAt` but drops its ETag, so the next revalidation downloads
  /// the server's version instead of confirming the pre-edit one. With no
  /// prior entry, the new one starts out invalidated.
  Future<void> put<T>(CacheResource<T> resource, T value) async {
    final storageKey = await _storageKeyFor(resource.key);
    final current = await _usableEntry(storageKey, resource.policy);
    await _save(
      storageKey,
      CacheEntry(
        data: resource.encode(value),
        fetchedAt: current?.fetchedAt ?? _clock(),
        schemaVersion: resource.policy.schemaVersion,
        invalidated: current?.invalidated ?? true,
      ),
    );
    _emit(storageKey, const _CacheEvent(_EventKind.changed));
  }

  /// Applies [change] to the cached value (or `null` when nothing usable is
  /// cached) and stores the result via [put].
  Future<void> update<T>(
    CacheResource<T> resource,
    T Function(T? current) change,
  ) async {
    final snapshot = await read(resource);
    await put(resource, change(snapshot.hasData ? snapshot.data : null));
  }

  /// Marks the entry for [key] stale, keeping its data.
  Future<void> invalidate(String key) => _invalidateWhere((k) => k == key);

  /// Marks every entry whose key starts with [prefix] stale.
  Future<void> invalidatePrefix(String prefix) =>
      _invalidateWhere((k) => k.startsWith(prefix));

  /// Removes the entry for [key].
  Future<void> evict(String key) => _evictWhere((k) => k == key);

  /// Removes every entry whose key starts with [prefix].
  Future<void> evictPrefix(String prefix) =>
      _evictWhere((k) => k.startsWith(prefix));

  /// Removes every entry for every account and server.
  Future<void> clearAll() async {
    final keys = {..._memory.keys};
    try {
      keys.addAll(await _store.keys());
    } on Object {
      // Whatever is still stored stays unreachable to other scopes anyway.
    }
    for (final storageKey in keys) {
      await _delete(storageKey);
      _emit(storageKey, const _CacheEvent(_EventKind.changed));
    }
    _lastError.clear();
  }

  void dispose() {
    for (final controller in _events.values) {
      controller.close();
    }
    _events.clear();
  }

  Future<CacheSnapshot<T>> _read<T>(
    String storageKey,
    CacheResource<T> resource,
  ) async {
    final entry = await _usableEntry(storageKey, resource.policy);
    if (entry == null) return CacheSnapshot<T>();
    final T data;
    try {
      data = resource.decode(entry.data);
    } on Object {
      return CacheSnapshot<T>();
    }
    return CacheSnapshot<T>(
      data: data,
      fetchedAt: entry.fetchedAt,
      source: _confirmed.contains(storageKey)
          ? CacheSource.server
          : CacheSource.cache,
      isStale: resource.policy.isStale(entry, _clock()),
    );
  }

  Future<void> _revalidate<T>(
    String storageKey,
    CacheResource<T> resource,
  ) async {
    _emit(storageKey, const _CacheEvent(_EventKind.refreshStarted));
    Object? error;
    try {
      final current = await _usableEntry(storageKey, resource.policy);
      final response = await resource.fetch(current?.etag);
      final now = _clock();
      switch (response) {
        case NotModified():
          if (current == null) {
            throw const FormatException('304 without a cached entry.');
          }
          await _save(
            storageKey,
            current.copyWith(fetchedAt: now, invalidated: false),
          );
        case Modified(:final body, :final etag):
          // Validate before caching, so a bad body never replaces good data.
          resource.decode(body);
          await _save(
            storageKey,
            CacheEntry(
              data: body,
              fetchedAt: now,
              schemaVersion: resource.policy.schemaVersion,
              etag: etag,
            ),
          );
      }
      _confirmed.add(storageKey);
    } on Object catch (e) {
      error = e;
      if (_meansGone(e)) await _delete(storageKey);
    }
    _lastError[storageKey] = error;
    _emit(storageKey, _CacheEvent(_EventKind.refreshFinished, error));
  }

  static bool _meansGone(Object error) =>
      error is ForbiddenException ||
      (error is ServerException && error.statusCode == 404);

  Future<CacheEntry?> _usableEntry(
    String storageKey,
    CachePolicy policy,
  ) async {
    final entry = await _entry(storageKey);
    if (entry == null) return null;
    if (!policy.accepts(entry)) {
      await _delete(storageKey);
      return null;
    }
    return entry;
  }

  Future<CacheEntry?> _entry(String storageKey) async {
    final cached = _memory[storageKey];
    if (cached != null || !_persisted(storageKey)) return cached;
    try {
      final stored = await _store.read(storageKey);
      if (stored != null) _memory[storageKey] = stored;
      return stored;
    } on Object {
      return null;
    }
  }

  Future<void> _save(String storageKey, CacheEntry entry) async {
    _memory[storageKey] = entry;
    if (!_persisted(storageKey)) return;
    try {
      await _store.write(storageKey, entry);
    } on Object {
      // Still served from memory for this session.
    }
  }

  Future<void> _delete(String storageKey) async {
    _memory.remove(storageKey);
    _confirmed.remove(storageKey);
    if (!_persisted(storageKey)) return;
    try {
      await _store.remove(storageKey);
    } on Object {
      // A leftover entry is overwritten or evicted again on the next refresh.
    }
  }

  Future<List<String>> _keysInScope(bool Function(String key) test) async {
    final prefix = '${await _currentScope()}|';
    final keys = {..._memory.keys};
    if (_persisted(prefix)) {
      try {
        keys.addAll(await _store.keys());
      } on Object {
        // Only the in-memory entries can be reached.
      }
    }
    return [
      for (final storageKey in keys)
        if (storageKey.startsWith(prefix) &&
            test(storageKey.substring(prefix.length)))
          storageKey,
    ];
  }

  Future<void> _invalidateWhere(bool Function(String key) test) async {
    for (final storageKey in await _keysInScope(test)) {
      final entry = await _entry(storageKey);
      if (entry == null) continue;
      await _save(storageKey, entry.copyWith(invalidated: true));
      _emit(storageKey, const _CacheEvent(_EventKind.changed));
    }
  }

  Future<void> _evictWhere(bool Function(String key) test) async {
    for (final storageKey in await _keysInScope(test)) {
      await _delete(storageKey);
      _emit(storageKey, const _CacheEvent(_EventKind.changed));
    }
  }

  StreamController<_CacheEvent> _channel(String storageKey) =>
      _events.putIfAbsent(storageKey, StreamController<_CacheEvent>.broadcast);

  void _emit(String storageKey, _CacheEvent event) =>
      _events[storageKey]?.add(event);
}
