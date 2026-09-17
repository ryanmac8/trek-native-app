import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../network/api_exception.dart';

import 'trip_api.dart';
import 'trip_local_store.dart';

/// Repository for trip data with offline-first caching and background sync.
///
/// Implements the pattern from docs/offline-first.md:
/// - Reads go from local cache first, then refresh from server in background
/// - Writes go to local cache first, then sync to server with retry
class TripRepository {
  TripRepository({
    required TripApi tripApi,
    required TripLocalStore localStore,
    required http.Client httpClient,
  })  : _api = tripApi,
        _store = localStore,
        _client = httpClient;

  final TripApi _api;
  final TripLocalStore _store;
  final http.Client _client;

  /// Refresh trip data from the server.
  ///
  /// Calls list/trip endpoints and updates the local store.
  Future<void> refresh() async {
    await _syncTrips();
    await _syncDays();
    await _syncPlaces();
    await _syncTags();
  }

  /// Sync a single trip with all its related data.
  ///
  /// Uses the trip ID from the store, fetches from server, then saves back.
  Future<void> _syncTrips() async {
    // Get all trips from server
    final serverTrips = await _api.list();

    // Build a map of server trips by ID
    final serverTripMap = Map<String, Trip>.fromEntries(
      serverTrips.map((t) => MapEntry(t.id, t)),
    );

    // Get all local trips
    final localTrips = _store.readTrips();

    // For each local trip, check if it exists on server
    for (final localTrip in localTrips) {
      final serverTrip = serverTripMap[localTrip.id];

      if (serverTrip == null) {
        // Trip doesn't exist on server, delete locally
        _store.removeTrip(localTrip.id);
      } else {
        // Update local trip with server data
        // TODO: Implement proper merge logic
        _updateTripFromServer(localTrip.id, serverTrip);
      }
    }

    // Filter out any server trips that don't exist locally (user deleted)
    final keptLocalTripIds = localTrips.map((t) => t.id).toSet();
    serverTripMap.removeWhere((id, _) => !keptLocalTripIds.contains(id));
  }

  /// Update a local trip with data from the server.
  void _updateTripFromServer(String localId, Trip serverTrip) {
    final localTrip = _store.getTrip(localId);
    if (localTrip == null) return;

    // Merge server data into local trip
    localTrip.title = serverTrip.title ?? localTrip.title;
    localTrip.description = serverTrip.description ?? localTrip.description;
    localTrip.visibility = serverTrip.visibility ?? localTrip.visibility;
    // TODO: Merge tags
    // TODO: Merge timestamps
    // TODO: Persist to store
  }

  Future<void> _syncDays() async {
    // Implementation for syncing days
    throw UnimplementedError();
  }

  Future<void> _syncPlaces() async {
    // Implementation for syncing places
    throw UnimplementedError();
  }

  Future<void> _syncTags() async {
    // Implementation for syncing tags
    throw UnimplementedError();
  }

  /// Get all trips from local cache.
  List<Trip> get all => _store.readTrips();

  /// Get a specific trip by ID from cache.
  Trip? get(String id) {
    final trips = _store.readTrips();
    return trips.firstWhere((t) => t.id == id, orElse: () => Trip(id: id));
  }

  /// Check if a trip exists in cache.
  bool has(String id) {
    final trips = _store.readTrips();
    return trips.any((t) => t.id == id);
  }

  /// Get all tags from cache.
  List<Tag> get tags => _store.readTags();
}
