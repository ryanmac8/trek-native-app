import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A trip invite the app has seen but not yet completed on the server.
///
/// [server] is the configured public server URL the invite was opened
/// against — invite tokens only mean something to the server that issued
/// them. [acceptQueued] is `true` once the user has confirmed the join
/// (so it's sent without asking again once the server is reachable);
/// `false` means the link was opened but the user hasn't confirmed yet
/// (e.g. it arrived while signed out). [tripId]/[tripTitle] are the last
/// preview seen for it, if any, so the invite can still be described
/// while offline.
class PendingInvite {
  const PendingInvite({
    required this.token,
    required this.server,
    this.acceptQueued = false,
    this.tripId,
    this.tripTitle,
  });

  factory PendingInvite.fromJson(Map<String, dynamic> json) => PendingInvite(
    token: json['token'] as String,
    server: json['server'] as String,
    acceptQueued: json['accept_queued'] as bool? ?? false,
    tripId: (json['trip_id'] as num?)?.toInt(),
    tripTitle: json['trip_title'] as String?,
  );

  final String token;
  final String server;
  final bool acceptQueued;
  final int? tripId;
  final String? tripTitle;

  PendingInvite copyWith({bool? acceptQueued, int? tripId, String? tripTitle}) {
    return PendingInvite(
      token: token,
      server: server,
      acceptQueued: acceptQueued ?? this.acceptQueued,
      tripId: tripId ?? this.tripId,
      tripTitle: tripTitle ?? this.tripTitle,
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'server': server,
    'accept_queued': acceptQueued,
    if (tripId != null) 'trip_id': tripId,
    if (tripTitle != null) 'trip_title': tripTitle,
  };
}

/// Durable local list of [PendingInvite]s, keyed by (server, token).
abstract class PendingInviteStore {
  Future<List<PendingInvite>> readAll();

  /// Inserts [invite], or replaces the entry with the same server + token.
  Future<void> put(PendingInvite invite);

  Future<void> remove({required String server, required String token});
}

/// [PendingInviteStore] backed by `shared_preferences` (a single JSON list)
/// — invite tokens grant trip membership but only to an already signed-in
/// user, the same exposure as the trip data this app caches in plain local
/// storage.
class PreferencesPendingInviteStore implements PendingInviteStore {
  PreferencesPendingInviteStore({SharedPreferencesAsync? preferences})
    : _injectedPreferences = preferences;

  static const _key = 'trek.trip_invites.pending';

  // Created on first use rather than in the constructor: the router holds
  // this store from app start, and most launches never touch it.
  SharedPreferencesAsync? _injectedPreferences;
  SharedPreferencesAsync get _preferences =>
      _injectedPreferences ??= SharedPreferencesAsync();

  @override
  Future<List<PendingInvite>> readAll() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => PendingInvite.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Object {
      // A corrupt entry shouldn't wedge every future invite; start over.
      await _preferences.remove(_key);
      return [];
    }
  }

  @override
  Future<void> put(PendingInvite invite) async {
    final all = await readAll();
    final index = all.indexWhere(
      (e) => e.server == invite.server && e.token == invite.token,
    );
    if (index == -1) {
      all.add(invite);
    } else {
      all[index] = invite;
    }
    await _write(all);
  }

  @override
  Future<void> remove({required String server, required String token}) async {
    final all = await readAll();
    all.removeWhere((e) => e.server == server && e.token == token);
    await _write(all);
  }

  Future<void> _write(List<PendingInvite> all) async {
    if (all.isEmpty) {
      await _preferences.remove(_key);
    } else {
      await _preferences.setString(
        _key,
        jsonEncode(all.map((e) => e.toJson()).toList()),
      );
    }
  }
}
