/// The slice of a Trek trip the home-screen widget needs: a row of
/// `GET /api/trips` (`{ trips: [...] }`, non-archived by default) reduced
/// to its id, title, and date range.
///
/// Dates are Trek's plain `YYYY-MM-DD` strings (no time zone), kept as-is
/// so the native widget can compare them against the device's local date.
/// A trip may have no dates at all.
class WidgetTrip {
  const WidgetTrip({
    required this.id,
    required this.title,
    this.startDate,
    this.endDate,
  });

  factory WidgetTrip.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    return WidgetTrip(
      id: id is int ? id : int.parse('$id'),
      title: (json['title'] as String?)?.trim() ?? '',
      startDate: _parseDate(json['start_date']),
      endDate: _parseDate(json['end_date']),
    );
  }

  final int id;
  final String title;
  final String? startDate;
  final String? endDate;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'start_date': startDate,
    'end_date': endDate,
  };

  static final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}');

  /// Keeps only the `YYYY-MM-DD` prefix of a date value; anything that
  /// isn't one (null, empty, malformed) is treated as "no date".
  static String? _parseDate(Object? value) {
    if (value is! String) return null;
    final match = _datePattern.firstMatch(value);
    return match?.group(0);
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetTrip &&
      other.id == id &&
      other.title == title &&
      other.startDate == startDate &&
      other.endDate == endDate;

  @override
  int get hashCode => Object.hash(id, title, startDate, endDate);

  @override
  String toString() => 'WidgetTrip($id, $title, $startDate..$endDate)';
}

/// Formats [date]'s local calendar day as Trek's `YYYY-MM-DD`.
String formatTrekDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The trips the "Next trip" widget may show on or after [today], in the
/// order it should pick them: every trip that is running or still ahead
/// (its end date — or its start date, if it has no end date — is on or
/// after [today]), sorted by start date, then id. Undated trips are left
/// out.
///
/// This matches Trek's own "active trip" order (`TripsService.activeTrip`:
/// a trip running today, else the next one to start) for as long as the
/// list stays unchanged: trips already running always started before the
/// ones still ahead. The native widget therefore only has to take the
/// first entry whose end is not yet in the past to stay correct on later
/// days without the app running or a network connection.
///
/// At most [limit] trips are returned.
List<WidgetTrip> nextTripCandidates(
  Iterable<WidgetTrip> trips,
  DateTime today, {
  int limit = 5,
}) {
  final todayString = formatTrekDate(today);
  final candidates = trips.where((trip) {
    final start = trip.startDate;
    if (start == null) return false;
    final lastDay = trip.endDate ?? start;
    return lastDay.compareTo(todayString) >= 0;
  }).toList();
  candidates.sort((a, b) {
    final byStart = a.startDate!.compareTo(b.startDate!);
    return byStart != 0 ? byStart : a.id.compareTo(b.id);
  });
  return candidates.take(limit).toList();
}
