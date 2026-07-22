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
    this.isArchived = false,
    this.hasPendingEdit = false,
    this.hasPendingArchiveSync = false,
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
  final bool isArchived;

  /// True once a local edit ([TripsRepository.editTrip]) has been applied to
  /// this trip but hasn't yet been confirmed by the server — retried by the
  /// next [TripsRepository.refreshTrips] call.
  final bool hasPendingEdit;

  /// Same idea as [hasPendingEdit], but for an archive/unarchive toggle
  /// ([TripsRepository.setArchived]) specifically — tracked separately so a
  /// retry only resends the field it actually changed, since the server
  /// checks `trip_edit` and `trip_archive` as distinct permissions.
  final bool hasPendingArchiveSync;

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
      isArchived: _parseBool(json['is_archived']),
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
    'is_archived': isArchived,
    'has_pending_edit': hasPendingEdit,
    'has_pending_archive_sync': hasPendingArchiveSync,
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
      isArchived: json['is_archived'] as bool? ?? false,
      hasPendingEdit: json['has_pending_edit'] as bool? ?? false,
      hasPendingArchiveSync: json['has_pending_archive_sync'] as bool? ?? false,
    );
  }

  Trip copyWith({
    String? localId,
    bool? isArchived,
    bool? hasPendingEdit,
    bool? hasPendingArchiveSync,
  }) => Trip(
    id: id,
    localId: localId ?? this.localId,
    title: title,
    description: description,
    startDate: startDate,
    endDate: endDate,
    currency: currency,
    dayCount: dayCount,
    placeCount: placeCount,
    isArchived: isArchived ?? this.isArchived,
    hasPendingEdit: hasPendingEdit ?? this.hasPendingEdit,
    hasPendingArchiveSync: hasPendingArchiveSync ?? this.hasPendingArchiveSync,
  );

  static DateTime? _parseDate(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }

  /// `is_archived` (and other boolean-ish columns) arrive from the server
  /// as a SQLite integer (`0`/`1`), not a JSON boolean — confirmed against
  /// the real `/api/trips` response shape.
  static bool _parseBool(Object? value) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    return false;
  }
}
