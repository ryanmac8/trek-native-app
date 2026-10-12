import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../share_intake/shared_map_link.dart';
import 'share_import_api.dart';

/// A shared map link the user chose to add to a trip, waiting to be sent
/// because the server couldn't be reached.
class PendingPlaceImport {
  const PendingPlaceImport({
    required this.id,
    required this.serverUrl,
    required this.tripId,
    required this.tripTitle,
    required this.url,
    required this.provider,
    this.name,
    this.suggestedName,
    this.lat,
    this.lng,
  });

  factory PendingPlaceImport.fromJson(Map<String, dynamic> json) {
    return PendingPlaceImport(
      id: json['id'] as String,
      serverUrl: json['server_url'] as String,
      tripId: (json['trip_id'] as num).toInt(),
      tripTitle: json['trip_title'] as String? ?? '',
      url: json['url'] as String,
      provider: MapLinkProvider.values.byName(json['provider'] as String),
      name: json['name'] as String?,
      suggestedName: json['suggested_name'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
    );
  }

  /// Local-only identifier, so a flush can remove exactly the entry it sent.
  final String id;

  /// The configured public server URL at the time — an import is only ever
  /// sent to the server it was made against.
  final String serverUrl;
  final int tripId;
  final String tripTitle;
  final String url;
  final MapLinkProvider provider;

  /// The name the user entered, if any.
  final String? name;

  /// The name parsed from the shared text ([SharedMapLink.suggestedName]),
  /// used if neither the user nor the server's resolver gave one.
  final String? suggestedName;

  /// Coordinates parsed from the link locally (see [SharedMapLink]), used
  /// if the server can't resolve it.
  final double? lat;
  final double? lng;

  Map<String, dynamic> toJson() => {
    'id': id,
    'server_url': serverUrl,
    'trip_id': tripId,
    'trip_title': tripTitle,
    'url': url,
    'provider': provider.name,
    'name': name,
    'suggested_name': suggestedName,
    'lat': lat,
    'lng': lng,
  };
}

/// Durable local state for sharing map links into trips: the last-fetched
/// trip list per server (so the picker works offline) and the queue of
/// imports not yet sent.
abstract class ShareImportStore {
  Future<List<ShareTargetTrip>?> readTrips(String serverUrl);
  Future<void> writeTrips(String serverUrl, List<ShareTargetTrip> trips);
  Future<List<PendingPlaceImport>> readPending();
  Future<void> writePending(List<PendingPlaceImport> pending);
}

class PreferencesShareImportStore implements ShareImportStore {
  PreferencesShareImportStore({SharedPreferencesAsync? preferences})
    : _injected = preferences;

  final SharedPreferencesAsync? _injected;

  // Lazy, so building the provider never throws — a platform failure
  // surfaces from the first read/write, where callers already handle it.
  late final SharedPreferencesAsync _preferences =
      _injected ?? SharedPreferencesAsync();

  static const _tripsKeyPrefix = 'trek.share_import.trips.';
  static const _pendingKey = 'trek.share_import.pending';

  @override
  Future<List<ShareTargetTrip>?> readTrips(String serverUrl) async {
    final raw = await _preferences.getString('$_tripsKeyPrefix$serverUrl');
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(ShareTargetTrip.fromJson)
          .toList();
    } catch (error) {
      debugPrint('ShareImportStore: dropping unreadable trip cache: $error');
      return null;
    }
  }

  @override
  Future<void> writeTrips(String serverUrl, List<ShareTargetTrip> trips) {
    return _preferences.setString(
      '$_tripsKeyPrefix$serverUrl',
      jsonEncode(trips.map((trip) => trip.toJson()).toList()),
    );
  }

  @override
  Future<List<PendingPlaceImport>> readPending() async {
    final raw = await _preferences.getString(_pendingKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(PendingPlaceImport.fromJson)
          .toList();
    } catch (error) {
      debugPrint('ShareImportStore: dropping unreadable queue: $error');
      return [];
    }
  }

  @override
  Future<void> writePending(List<PendingPlaceImport> pending) {
    return _preferences.setString(
      _pendingKey,
      jsonEncode(pending.map((item) => item.toJson()).toList()),
    );
  }
}
