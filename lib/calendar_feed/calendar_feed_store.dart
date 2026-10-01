import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'calendar_feed.dart';

/// Local cache of [CalendarFeedSnapshot]s, keyed by account and feed.
abstract class CalendarFeedStore {
  Future<CalendarFeedSnapshot?> read(String account, CalendarFeedScope scope);
  Future<void> write(
    String account,
    CalendarFeedScope scope,
    CalendarFeedSnapshot snapshot,
  );
}

/// Keeps snapshots in platform secure storage: a feed URL's token is the
/// only credential Trek's public `.ics` route asks for, so it's treated
/// like one rather than written to plain preferences.
class SecureCalendarFeedStore implements CalendarFeedStore {
  SecureCalendarFeedStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String account, CalendarFeedScope scope) =>
      'trek.calendar_feed.${base64Url.encode(utf8.encode(account))}'
      '.${scope.cacheKey}';

  @override
  Future<CalendarFeedSnapshot?> read(
    String account,
    CalendarFeedScope scope,
  ) async {
    final raw = await _storage.read(key: _key(account, scope));
    if (raw == null) return null;
    try {
      return CalendarFeedSnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> write(
    String account,
    CalendarFeedScope scope,
    CalendarFeedSnapshot snapshot,
  ) {
    return _storage.write(
      key: _key(account, scope),
      value: jsonEncode(snapshot.toJson()),
    );
  }
}
