/// A trip, as returned by `GET /api/trips` / `POST /api/trips`, plus the
/// fields needed to track an offline-created trip until it syncs (see
/// [TripsRepository] in `trips_repository.dart`).
///
/// [id] is null exactly when the trip was created locally while offline and
/// hasn't been confirmed by the server yet ([isPending]). [localId] is a
/// stable client-generated key that survives that transition — used to find
/// and replace the pending entry in the local cache once the create syncs,
/// without depending on the server id existing yet.
class Trip {
  const Trip({
    this.id,
    required this.localId,
    required this.title,
    this.description,
    this.startDate,
    this.endDate,
    this.currency,
    this.dayCount = 0,
    this.placeCount = 0,
  });

  final int? id;
  final String localId;
  final String title;
  final String? description;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? currency;
  final int dayCount;
  final int placeCount;

  /// True for a trip created locally that hasn't been confirmed by the
  /// server yet — either still queued (offline) or its create request is in
  /// flight. See [TripsRepository.createTrip].
  bool get isPending => id == null;

  factory Trip.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as int;
    return Trip(
      id: id,
      localId: 'server-$id',
      title: json['title'] as String,
      description: json['description'] as String?,
      startDate: _parseDate(json['start_date']),
      endDate: _parseDate(json['end_date']),
      currency: json['currency'] as String?,
      dayCount: json['day_count'] as int? ?? 0,
      placeCount: json['place_count'] as int? ?? 0,
    );
  }

  /// Round-trips a [Trip] through the local cache (see
  /// `PreferencesTripsLocalStore`) — unlike [fromJson]/the real API shape,
  /// this must also carry [id] being absent (a still-pending trip) and the
  /// client-generated [localId].
  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'local_id': localId,
    'title': title,
    'description': description,
    'start_date': startDate?.toIso8601String(),
    'end_date': endDate?.toIso8601String(),
    'currency': currency,
    'day_count': dayCount,
    'place_count': placeCount,
  };

  factory Trip.fromCacheJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] as int?,
      localId: json['local_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      startDate: _parseDate(json['start_date']),
      endDate: _parseDate(json['end_date']),
      currency: json['currency'] as String?,
      dayCount: json['day_count'] as int? ?? 0,
      placeCount: json['place_count'] as int? ?? 0,
    );
  }

  static DateTime? _parseDate(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}
