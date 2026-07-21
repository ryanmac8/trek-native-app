/// A trip, as returned by `GET /api/trips`. Deliberately minimal — only
/// the fields [TripListScreen] needs to render a row. Full trip detail
/// (days, places, budget, etc.) is issue #3 onward; this is just enough to
/// give the authenticated `ApiClient` a real caller (see docs/app-shell.md).
class Trip {
  const Trip({
    required this.id,
    required this.title,
    this.startDate,
    this.endDate,
    this.dayCount = 0,
    this.placeCount = 0,
  });

  final int id;
  final String title;
  final DateTime? startDate;
  final DateTime? endDate;
  final int dayCount;
  final int placeCount;

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] as int,
      title: json['title'] as String,
      startDate: _parseDate(json['start_date']),
      endDate: _parseDate(json['end_date']),
      dayCount: json['day_count'] as int? ?? 0,
      placeCount: json['place_count'] as int? ?? 0,
    );
  }

  static DateTime? _parseDate(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}
