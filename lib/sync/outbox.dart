import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'pending_write.dart';

/// Durable persistence for the [Outbox] queue, so writes made offline
/// survive the app being killed before they sync.
abstract class OutboxStore {
  Future<List<PendingWrite>> read();
  Future<void> write(List<PendingWrite> writes);
}

/// Stores the whole queue as one JSON list in `shared_preferences`. Queued
/// payloads are trip data, not secrets, so plain storage is fine. A corrupt
/// value reads as an empty queue rather than crashing startup.
class PreferencesOutboxStore implements OutboxStore {
  PreferencesOutboxStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const key = 'trek.sync.outbox';

  final SharedPreferencesAsync _preferences;

  @override
  Future<List<PendingWrite>> read() async {
    final raw = await _preferences.getString(key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((json) => PendingWrite.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> write(List<PendingWrite> writes) async {
    if (writes.isEmpty) {
      await _preferences.remove(key);
      return;
    }
    await _preferences.setString(
      key,
      jsonEncode(writes.map((write) => write.toJson()).toList()),
    );
  }
}

/// FIFO queue of local writes waiting to reach the server (see
/// docs/offline-sync.md). Feature repositories apply a change to their own
/// local cache first, then [enqueue] it here; [SyncEngine] drains the queue
/// in order.
///
/// Every mutation is serialized and persisted to [OutboxStore] before its
/// future completes. [changes] emits the pending count after each one.
class Outbox {
  Outbox({required OutboxStore store, DateTime Function()? clock})
    : _store = store,
      _clock = clock ?? DateTime.now;

  final OutboxStore _store;
  final DateTime Function() _clock;
  final _changes = StreamController<int>.broadcast();

  List<PendingWrite>? _writes;
  Future<void> _lock = Future.value();
  String? _inFlightId;
  int _idCounter = 0;

  /// Emits the number of pending writes after every change.
  Stream<int> get changes => _changes.stream;

  /// Snapshot of the queue, oldest first.
  Future<List<PendingWrite>> pending() =>
      _locked(() async => List.unmodifiable(await _load()));

  /// Queues a write. If [coalesceKey] matches a queued write of the same
  /// [kind] that isn't currently being pushed, the two collapse into the
  /// earlier write's slot: [payload]'s fields are merged over the queued
  /// payload (per-field last-write-wins), or replace it outright when
  /// [replace] is true. Otherwise the write is appended.
  Future<PendingWrite> enqueue(
    String kind,
    Map<String, dynamic> payload, {
    String? coalesceKey,
    bool replace = false,
  }) {
    return _locked(() async {
      final writes = await _load();
      if (coalesceKey != null) {
        final index = writes.indexWhere(
          (write) =>
              write.coalesceKey == coalesceKey &&
              write.kind == kind &&
              write.id != _inFlightId,
        );
        if (index != -1) {
          final existing = writes[index];
          final merged = existing.copyWith(
            payload: replace ? payload : {...existing.payload, ...payload},
          );
          writes[index] = merged;
          await _save(writes);
          return merged;
        }
      }
      final write = PendingWrite(
        id: '${_clock().microsecondsSinceEpoch}-${_idCounter++}',
        kind: kind,
        payload: payload,
        coalesceKey: coalesceKey,
        createdAt: _clock(),
      );
      writes.add(write);
      await _save(writes);
      return write;
    });
  }

  /// Drops every queued write matching [test] and returns how many were
  /// removed — e.g. a repository cancelling the queued create and edits of
  /// an item deleted before it ever synced.
  Future<int> removeWhere(bool Function(PendingWrite write) test) {
    return _locked(() async {
      final writes = await _load();
      final before = writes.length;
      writes.removeWhere(test);
      final removed = before - writes.length;
      if (removed > 0) await _save(writes);
      return removed;
    });
  }

  /// Empties the queue.
  Future<void> clear() => _locked(() async {
    final writes = await _load();
    writes.clear();
    await _save(writes);
  });

  /// Marks [id] as being pushed, so [enqueue] won't merge new changes into
  /// a write whose payload has already been sent. Pass null when done.
  void markInFlight(String? id) => _inFlightId = id;

  /// Removes the write with [id], if still queued.
  Future<void> remove(String id) =>
      removeWhere((write) => write.id == id).then((_) {});

  /// Replaces the queued write that has [write]'s id (e.g. to record a
  /// failed attempt). No-op if it has since been removed.
  Future<void> update(PendingWrite write) {
    return _locked(() async {
      final writes = await _load();
      final index = writes.indexWhere((w) => w.id == write.id);
      if (index == -1) return;
      writes[index] = write;
      await _save(writes);
    });
  }

  Future<List<PendingWrite>> _load() async =>
      _writes ??= List.of(await _store.read());

  Future<void> _save(List<PendingWrite> writes) async {
    await _store.write(writes);
    _changes.add(writes.length);
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> dispose() => _changes.close();
}
