/// Data types for Trek's trip and trip-related features.
///
/// Confirmed against Trek's backend (`server/src/nest/trip/`):
///
/// - `GET /api/trips` → `{ results: Trip[] }`
/// - `POST /api/trips` → `{ error?: string; trip?: Trip; requiresMfa?: boolean }`
/// - `GET /api/trips/:id` → `{ trip: Trip }`
/// - `PATCH /api/trips/:id` → `{ error?: string; trip?: Trip; requiresMfa?: boolean }`
/// - `DELETE /api/trips/:id` → `{ error?: string; success: true }`
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A Trek trip — the core container for all trip-related data.
class Trip {
  const Trip({
    required this.id,
    required this.title,
    required this.description,
    this.visibility = 'everyone',
    this.tags = const [],
    this.createdAt,
    this.updatedAt,
    this.members = const [],
  });

  final String id;
  final String title;
  final String? description;
  final String visibility; // 'everyone' | 'me' | 'members'
  final List<String> tags;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Members with access to this trip — for collaboration.
  // TODO: Add TripMember model

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: (json['description'] as dynamic?)?.toString(),
      visibility: json['visibility'] as String? ?? 'everyone',
      tags: (json['tags'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .where((t) => t.isNotEmpty)
          .toList() ?? [],
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      // Members are loaded separately via a nested endpoint
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'visibility': visibility,
        'tags': tags,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  /// Clone the trip with a new ID (for updates).
  Trip clone() => Trip(
        id: 'new-id', // will be replaced by server
        title: title,
        description: description,
        visibility: visibility,
        tags: tags,
        // Don't copy timestamps on create
      );

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

/// A day within a trip — represents a sequence of places visited on a calendar day.
class Day {
  const Day({
    required this.id,
    required this.tripId,
    required this.sequence,
    required this.title,
    this.description,
    this.createdAt,
    this.updatedAt,
    this.places = const [],
    this.notes,
  });

  final String id;
  final String tripId; // Parent trip reference
  final int sequence; // 1 = first day, 2 = second day, etc.
  final String title;
  final String? description;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<PlaceSummary> places; // Embedded references
  final String? notes; // Day-specific notes for this trip

  factory Day.fromJson(Map<String, dynamic> json) {
    return Day(
      id: json['id'] as String? ?? '',
      tripId: json['tripId'] as String? ?? json['trip_id'] as String? ?? '',
      sequence: (json['sequence'] as int?) ?? 0,
      title: json['title'] as String? ?? '',
      description: (json['description'] as dynamic?)?.toString(),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      places: (json['places'] as List<dynamic>?)
          ?.map((e) => PlaceSummary.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      notes: (json['notes'] as dynamic?)?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tripId': id, // Will be resolved to actual trip ID on creation
        'sequence': sequence,
        'title': title,
        'description': description,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'places': places.map((p) => p.toJson()).toList(),
        'notes': notes,
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

  /// Add a place to this day (returns the place ID for further operations).
  Future<String> addPlace(Place place) async {
    // Implementation delegated to local store or API
    throw UnimplementedError();
  }

  /// Remove a place from this day.
  Future<void> removePlace(String placeId) async {
    throw UnimplementedError();
  }

  /// Update the sequence of this day (for reordering).
  Future<void> setSequence(int newSequence) async {
    throw UnimplementedError();
  }
}

/// A summary of a [Place] as it appears in a [Day].
/// Contains only the fields needed for display, not the full Place object.
class PlaceSummary {
  const PlaceSummary({
    required this.id,
    required this.placeId,
    required this.name,
    this.color,
    this.icon,
    required this.sequence,
  });

  final String id; // Generated when assigned to a day
  final String placeId; // Reference to the actual Place record
  final String name;
  final String? color; // Hex color from category, or null
  final String? icon;
  final int sequence; // 1 = first place on this day, 2 = second, etc.

  factory PlaceSummary.fromJson(Map<String, dynamic> json) {
    return PlaceSummary(
      id: json['id'] as String? ?? '',
      placeId: json['placeId'] as String? ?? json['place_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      color: json['color'] as String? ?? json['hex'] as String? ?? null,
      icon: json['icon'] as String? ?? json['emoji'] as String? ?? null,
      sequence: (json['sequence'] as int?) ?? (json['order'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'placeId': placeId,
        'name': name,
        'color': color,
        'icon': icon,
        'sequence': sequence,
      };
}

/// A tag for categorizing trips and placing content.
class Tag {
  const Tag({
    required this.id,
    required this.name,
    this.color,
    this.visible = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? color; // Hex color for UI display
  final bool visible; // Whether the tag should appear in dropdowns
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      color: json['color'] as String? ?? json['hex'] as String? ?? null,
      visible: json['visible'] as bool? ?? true,
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'visible': visible,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
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
}

/// Validation errors for trip operations.
class TripValidationError {
  const TripValidationError({
    required this.code,
    this.message,
  });

  final String code; // e.g., 'too_recent', 'empty_title'
  final String? message;

  factory TripValidationError.fromJson(Map<String, dynamic> json) {
    return TripValidationError(
      code: json['code'] as String? ?? '',
      message: json['message'] as String? ?? null,
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
      };
}

/// Common error response from the Trek API.
class ApiError {
  const ApiError({
    required this.code,
    this.message,
    this.field,
  });

  final String code; // e.g., 'not_found', 'unauthorized', 'conflict'
  final String? message;
  final String? field; // Which field caused the error

  factory ApiError.fromJson(Map<String, dynamic> json) {
    return ApiError(
      code: json['code'] as String? ?? 'unknown',
      message: json['message'] as String? ?? null,
      field: json['field'] as String? ?? null,
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        'field': field,
      };
}
