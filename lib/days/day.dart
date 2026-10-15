import 'day_note.dart';

/// A single day of a trip's itinerary, as returned by
/// `GET /api/trips/:tripId/days` (see [DaysApi]).
///
/// The real response nests each day's place assignments and day notes
/// inline. Day notes are modeled in full ([noteItems]); for assignments
/// this client only needs how many there are to render a count, not the
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
    this.noteItems = const [],
  });

  final int id;
  final int tripId;
  final int dayNumber;
  final DateTime? date;
  final String? notes;
  final String? title;
  final int assignmentCount;

  /// The day's notes (the response's `notes_items`), in the server's
  /// display order — see [DayNote.compare].
  final List<DayNote> noteItems;

  factory Day.fromJson(Map<String, dynamic> json) {
    final assignments = json['assignments'] as List<dynamic>? ?? const [];
    final notes = json['notes_items'] as List<dynamic>? ?? const [];
    return Day(
      id: json['id'] as int,
      tripId: json['trip_id'] as int,
      dayNumber: json['day_number'] as int,
      date: _parseDate(json['date']),
      notes: json['notes'] as String?,
      title: json['title'] as String?,
      assignmentCount: assignments.length,
      noteItems:
          notes
              .map((note) => DayNote.fromJson(note as Map<String, dynamic>))
              .toList()
            ..sort(DayNote.compare),
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
    'notes_items': noteItems.map((note) => note.toCacheJson()).toList(),
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
      noteItems: (json['notes_items'] as List<dynamic>? ?? const [])
          .map((note) => DayNote.fromCacheJson(note as Map<String, dynamic>))
          .toList(),
    );
  }

  Day withNoteItems(List<DayNote> noteItems) {
    return Day(
      id: id,
      tripId: tripId,
      dayNumber: dayNumber,
      date: date,
      notes: notes,
      title: title,
      assignmentCount: assignmentCount,
      noteItems: List<DayNote>.unmodifiable(
        List<DayNote>.of(noteItems)..sort(DayNote.compare),
      ),
    );
  }

  static DateTime? _parseDate(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}
