import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'trek_notification.dart';

/// Local persistence for the notifications inbox (see
/// docs/offline-first.md). Holds two things:
///
/// - the cached notification list, so the inbox paints instantly and works
///   offline;
/// - a **pending-reads outbox**: ids the user has marked read locally that
///   haven't been confirmed by the server yet, so an offline "mark read"
///   survives an app restart and is retried on the next refresh.
///
/// Scoped to the signed-in user implicitly — the session's bearer token
/// decides whose notifications the API returns, and the app has a single
/// active session. Clearing the session should clear this cache; that hook
/// lands with the wider logout-cleanup work.
abstract class NotificationsLocalStore {
  Future<List<TrekNotification>> readNotifications();
  Future<void> writeNotifications(List<TrekNotification> notifications);

  Future<Set<int>> readPendingReads();
  Future<void> writePendingReads(Set<int> ids);
}

/// Stores the cached list and the pending-reads outbox as JSON in
/// `shared_preferences`. None of this is secret, so plain (non-secure)
/// storage is fine — same reasoning as the reservations cache.
class PreferencesNotificationsLocalStore implements NotificationsLocalStore {
  PreferencesNotificationsLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static const _listKey = 'trek.notifications.cache';
  static const _pendingReadsKey = 'trek.notifications.pending_reads';

  @override
  Future<List<TrekNotification>> readNotifications() async {
    final raw = await _preferences.getString(_listKey);
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => TrekNotification.fromCacheJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> writeNotifications(List<TrekNotification> notifications) async {
    final encoded = jsonEncode(
      notifications.map((n) => n.toCacheJson()).toList(),
    );
    await _preferences.setString(_listKey, encoded);
  }

  @override
  Future<Set<int>> readPendingReads() async {
    final raw = await _preferences.getStringList(_pendingReadsKey);
    if (raw == null) return <int>{};
    return raw.map(int.parse).toSet();
  }

  @override
  Future<void> writePendingReads(Set<int> ids) async {
    await _preferences.setStringList(
      _pendingReadsKey,
      ids.map((id) => '$id').toList(),
    );
  }
}
