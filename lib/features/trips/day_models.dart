/// Data types for the Day feature within trips.
library;

import 'package:flutter/foundation.dart';

import 'trip_models.dart';

/// A day within a trip — represents a sequence of places visited on a calendar day.
class Day {
  const Day({
    required this.id,
    required this.tripId,
    required this.sequence,
    required this.title,
    this.description,
    this.startDate,
    this.endDate,
    this.createdAt,
    this.updatedAt,
    this.notes,
    this.places = const [],
    this.assignments = const [],
  });

  final String id;
  final String tripId; // Parent trip reference
  final int sequence; // 1 = first day, 2 = second day, etc.
  final String title; // Day title (e.g., "Arrival", "Hiking Trail", "Beach Day")
  final String? description;
  final DateTime? startDate; // When the day starts
  final DateTime? endDate; // When the day ends
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? notes; // Day-specific notes for this trip
  final List<PlaceSummary> places; // Places on this day
  final List<AssignmentSummary> assignments; // People doing activities on this day

  factory Day.fromJson(Map<String, dynamic> json) {
    return Day(
      id: json['id'] as String? ?? '',
      tripId: json['tripId'] as String? ?? json['trip_id'] as String? ?? '',
      sequence: (json['sequence'] as int?) ?? 0,
      title: json['title'] as String? ?? '',
      description: (json['description'] as dynamic?)?.toString(),
      startDate: _parseDateTime(json['startDate']),
      endDate: _parseDateTime(json['endDate']),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      notes: (json['notes'] as dynamic?)?.toString(),
      places: (json['places'] as List<dynamic>?)
          ?.map((e) => PlaceSummary.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      assignments: (json['assignments'] as List<dynamic>?)
          ?.map((e) => AssignmentSummary.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tripId': id, // Will be resolved to actual trip ID on creation
        'sequence': sequence,
        'title': title,
        'description': description,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'notes': notes,
        'places': places.map((p) => p.toJson()).toList(),
        'assignments': assignments.map((a) => a.toJson()).toList(),
      };

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    if (value is DateTime) return value;
    return null;
  }

  /// Clone the day with a new ID (for updates).
  Day clone() => Day(
        id: 'new-id',
        tripId: tripId,
        title: title,
        description: description,
        sequence: sequence,
      );
}

/// A place assignment to a day — links a place to a specific day.
class PlaceAssignment {
  const PlaceAssignment({
    required this.id,
    required this.dayId,
    required this.place,
    this.sequence,
    this.sequenceField,
    this.endTime,
  });

  final String id;
  final String dayId; // Parent day reference
  final Place place; // The place details
  final int? sequence; // Order within the day (1, 2, 3...)
  final String? sequenceField; // Which field to sort by (e.g., "sequence", "time")
  final DateTime? endTime; // When the activity ends
}

/// A summary of a [Place] as it appears in a [Day].
class PlaceSummary {
  const PlaceSummary({
    required this.id,
    required this.placeId,
    required this.name,
    this.color,
    this.icon,
    required this.sequence,
    this.notes,
    this.endTime,
  });

  final String id; // Generated when assigned to a day
  final String placeId; // Reference to the actual Place record
  final String name;
  final String? color; // Hex color from category
  final String? icon; // Emoji or icon name
  final int sequence; // 1 = first place on this day
  final String? notes;
  final DateTime? endTime;
}

/// An activity assignment on a day (e.g., a person going on a walk).
class AssignmentSummary {
  const AssignmentSummary({
    required this.id,
    required this.dayId,
    this.actor,
    this.type = 'walk',
    this.placeId,
    this.startTime,
    this.endTime,
    this.notes,
  });

  final String id;
  final String dayId;
  final String? actor; // Person doing the activity (ID)
  final String type; // 'walk', 'hike', 'boat', etc.
  final String? placeId; // Where the activity happens
  final DateTime? startTime;
  final DateTime? endTime;
  final String? notes;
}

/// A map of the Trek shared schemas that provides trip-related types.
///
/// This is used to deserialize responses from the Trek backend's shared schema.
/// See https://github.com/liketrek/TREK
class TripApiSharedSchema {
  /// A trip from the shared schema.
  Map<String, dynamic> tripFromShared(Map<String, dynamic> json) {
    return {
      'id': json['id'] as String? ?? '',
      'title': json['title'] as String? ?? '',
      'description': (json['description'] as dynamic?)?.toString(),
      'visibility': json['visibility'] as String? ?? 'everyone',
      'createdAt': _parseDateTime(json['createdAt']),
      'updatedAt': _parseDateTime(json['updatedAt']),
      // Member references are handled separately
    };
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    if (value is DateTime) return value;
    return null;
  }
}
