/// A single day of a trip's itinerary, as returned by
/// `GET /api/trips/:tripId/days` (see [DaysApi]).
///
/// The real response nests each day's place assignments (and notes) inline;
/// this client only needs how many are assigned to render a count, not the
/// assignments themselves — a place model doesn't exist yet ([#5]
/// https://github.com/ryanmac8/trek-native-app/issues/5), so
/// [assignmentCount] is derived from the array's length rather than the
/// array being modeled here.
class Day {
  const Day({
    required this.id,
    required this.tripId,
    required this.dayNumber,
    this.date,
    this.notes,
    this.title,
    this.assignmentCount = 0,
  });

  final int id;
  final int tripId;
  final int dayNumber;
  final DateTime? date;
  final String? notes;
  final String? title;
  final int assignmentCount;

  factory Day.fromJson(Map<String, dynamic> json) {
    final assignments = json['assignments'] as List<dynamic>? ?? const [];
    return Day(
      id: json['id'] as int,
      tripId: json['trip_id'] as int,
      dayNumber: json['day_number'] as int,
      date: _parseDate(json['date']),
      notes: json['notes'] as String?,
      title: json['title'] as String?,
      assignmentCount: assignments.length,
    );
  }

  /// Round-trips a [Day] through the local cache (see
  /// `PreferencesDaysLocalStore`) — [assignmentCount] is persisted directly
  /// since the cache doesn't carry the raw assignment list either.
  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'trip_id': tripId,
    'day_number': dayNumber,
    'date': date?.toIso8601String(),
    'notes': notes,
    'title': title,
    'assignment_count': assignmentCount,
  };

  factory Day.fromCacheJson(Map<String, dynamic> json) {
    return Day(
      id: json['id'] as int,
      tripId: json['trip_id'] as int,
      dayNumber: json['day_number'] as int,
      date: _parseDate(json['date']),
      notes: json['notes'] as String?,
      title: json['title'] as String?,
      assignmentCount: json['assignment_count'] as int? ?? 0,
    );
  }

  static DateTime? _parseDate(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}
