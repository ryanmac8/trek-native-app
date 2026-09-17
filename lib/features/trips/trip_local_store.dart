import 'dart:convert';

import 'package:shared_preferences/shared_preferences';

import '../trip_models.dart';

/// Local (offline) cache for trips data.
///
/// Design pattern: key-based store with normalized JSON structure.
/// Each trip is keyed by its [Trip.id], keyed under the `trips` list.
///
/// Example cache structure:
/// ```json
/// {
///   "trips": [
///     {"id": "trip-1", "title": "Vacation", "description": "...", ...},
///     {"id": "trip-2", "title": "Hiking", "description": "...", ...}
///   ],
///   "trip-tags": [
///     {"id": "tag-1", "name": "Summer", ...},
///     {"id": "tag-2", "name": "Adventure", ...}
///   ],
///   "trip-days": {
///     "trip-1": [
///       {"id": "day-1", "tripId": "trip-1", "sequence": 1, ...},
///       {"id": "day-2", "tripId": "trip-1", "sequence": 2, ...}
///     ],
///     "trip-2": [...]
///   },
///   "trip-places": {
///     "trip-1": [
///       {"id": "place-1", "placeId": "world-1", "name": "...", ...},
///       {"id": "place-2", "placeId": "world-2", "name": "...", ...}
///     ]
///   },
///   "trip-tags-links": {
///     "trip-1": ["tag-1", "tag-2"],
///     "trip-2": ["tag-1"]
///   },
///   "trip-notes": {
///     "trip-1": "Notes for trip 1...",
///     "trip-2": "Notes for trip 2..."
///   },
///   "days": {
///     "day-1": {
///       "places": [
///         {"id": "place-1", "placeId": "world-1", "name": "...", ...}
///       ],
///       "notes": "Day 1 notes..."
///     }
///   }
/// }
/// ```
///
/// All writes go through [write] which handles synchronization.
/// All reads go through [read] which first checks local cache,
/// then falls back to server if cache miss.
class TripLocalStore {
  TripLocalStore({String cacheKey = 'trek_trips'}) : _cacheKey = cacheKey;

  final String _cacheKey;
  late final Map<String, dynamic> _data;

  /// Initialize the cache by reading from local storage.
  Future<void> initialize() async {
    // In production, this would load from SharedPreferences
    // For now, use empty state
    _data = {
      'trips': <Map<String, dynamic>>[],
      'trip-tags': <Map<String, dynamic>>[],
      'trip-tags-links': <String, List<String>>{},
      'trip-notes': <String, String>{},
    };
  }

  /// Write a list of trips to local storage.
  Future<void> writeTrips(List<Trip> trips) async {
    final tripsList = trips.map((t) {
      return t.toJson();
    }).toList();
    _data['trips'] = tripsList;
    // TODO: Persist to SharedPreferences
  }

  /// Write a list of tags to local storage.
  Future<void> writeTags(List<Tag> tags) async {
    final tagsList = tags.map((t) {
      return t.toJson();
    }).toList();
    _data['trip-tags'] = tagsList;
  }

  /// Write trip-tag assignments to local storage.
  Future<void> writeTagAssignments(Map<String, List<String>> assignments) async {
    _data['trip-tags-links'] = assignments;
  }

  /// Write trip notes to local storage.
  Future<void> writeNotes(Map<String, String> notes) async {
    _data['trip-notes'] = notes;
  }

  /// Write a day to local storage.
  Future<void> writeDay(Day day) async {
    final days = _data['trip-days'] as Map<String, dynamic>? ?? {};
    days[day.id] = _normalizeDay(day);
    _data['trip-days'] = Map.from(days);
  }

  /// Write an itinerary (sequence of days) to local storage.
  Future<void> writeItinerary(String tripId, List<Day> days) async {
    final daysMap = Map<String, List<Map<String, dynamic>>>();
    for (final day in days) {
      daysMap[day.id] = _normalizeDay(day);
    }
    _data['trip-days'] = Map.of(_data['trip-days'] as Map<String, dynamic>? ?? {}, Map<String, List<Map<String, dynamic>>>);
    _data['trip-days'][tripId] = daysMap[tripId] ?? [];
  }

  /// Write a place assignment to a specific day.
  Future<void> writeDayPlace(String tripId, String dayId, Place place) async {
    final days = _data['trip-days'] as Map<String, dynamic>? ?? {};
    final dayData = Map.of(days[dayId] as List<Map<String, dynamic>>? ?? []);
    dayData.add(_normalizePlace(place));
    days[dayId] = dayData;
    _data['trip-days'] = days;
  }

  /// Remove a place from a day.
  Future<void> removeDayPlace(String tripId, String dayId, String placeId) async {
    final days = _data['trip-days'] as Map<String, dynamic>? ?? {};
    final dayData = List<Map<String, dynamic>>.from(days[dayId] ?? []);
    dayData.removeWhere((p) => p['id'] == placeId);
    days[dayId] = dayData;
    _data['trip-days'] = days;
  }

  /// Update a day's sequence.
  Future<void> updateDaySequence(String tripId, String dayId, int newSequence) async {
    // TODO: Handle sequence updates
  }

  Map<String, dynamic> _normalizeDay(Day day) {
    return {
      'id': day.id,
      'tripId': day.tripId,
      'sequence': day.sequence,
      'title': day.title,
      'description': day.description,
      'notes': day.notes,
      // Places reference uses placeId, not full place data
      'places': day.places.map((p) => p.toJson()).toList(),
    };
  }

  Map<String, dynamic> _normalizePlace(Place place) {
    return {
      'id': 'local-${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}',
      'placeId': place.id,
      'name': place.name,
      'color': place.color,
      'icon': place.icon,
      'category': place.category.name,
      'sequence': place.sequence,
    };
  }

  /// Read all trips from cache.
  List<Trip> readTrips() {
    final data = _data['trips'] as List<Map<String, dynamic>>? ?? [];
    return data.map((json) => Trip.fromJson(json)).toList();
  }

  /// Read all tags from cache.
  List<Tag> readTags() {
    final data = _data['trip-tags'] as List<Map<String, dynamic>>? ?? [];
    return data.map((json) => Tag.fromJson(json)).toList();
  }

  /// Read tag assignments for a specific trip.
  List<String> readTagAssignments(String tripId) {
    final assignments = _data['trip-tags-links'] as Map<String, List<String>>? ?? {};
    return assignments[tripId] ?? [];
  }

  /// Read notes for a specific trip.
  String? readNotes(String tripId) {
    return _data['trip-notes'][tripId];
  }

  /// Read all days for a specific trip.
  List<Day> readDays(String tripId) {
    final days = Map<String, List<Map<String, dynamic>>>();
    final daysData = _data['trip-days'] as Map<String, dynamic>? ?? {};
    final tripDays = daysData[tripId] as List<Map<String, dynamic>>? ?? [];
    return tripDays.map((d) => Day.fromJson(d)).toList();
  }

  Future<List<Day>> readDaysAsync(String tripId) async {
    // For testing
    return [];
  }

  /// Read all places assigned to a specific day in a trip.
  List<PlaceSummary> readDayPlaces(String tripId, String dayId) {
    final data = _data['trip-days'] as Map<String, dynamic>? ?? {};
    final dayData = data[dayId];
    if (dayData == null) return [];
    // Filter by day sequence if dayId doesn't match
    return (dayData as List<Map<String, dynamic>>)
        .where((p) => p['id'] != dayId)
        .map((json) => PlaceSummary.fromJson(json))
        .toList();
  }

  /// Check if a trip exists in cache.
  bool hasTrip(String tripId) {
    final trips = readTrips();
    return trips.any((t) => t.id == tripId);
  }

  /// Check if a day exists for a trip.
  bool hasDay(String tripId, String dayId) {
    final data = _data['trip-days'] as Map<String, dynamic>? ?? {};
    final days = data[tripId] as List<Map<String, dynamic>>? ?? [];
    return days.any((d) => d['id'] == dayId);
  }
}

/// A [Place] represents a specific location in the world.
///
/// This is distinct from a [PlaceSummary] which is what appears in a day.
/// [Place] is the canonical record of a place in the "places pool" (unassigned places).
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.category,
    this.sequence,
    this.color,
    this.icon,
    this.notes,
  });

  final String id;
  final String name;
  final String category; // Category name or ID
  final int? sequence; // Only set if assigned to a day (e.g., day 1, place 3)
  final String? color; // Hex color for UI
  final String? icon; // Emoji or icon name
  final String? notes; // User notes about this place

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? 'misc',
      sequence: (json['sequence'] as int?) ?? null,
      color: json['color'] as String? ?? null,
      icon: json['icon'] as String? ?? null,
      notes: (json['notes'] as dynamic?)?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'sequence': sequence,
        'color': color,
        'icon': icon,
        'notes': notes,
      };
}
