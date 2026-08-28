/// A booking record for a trip — a flight, train, restaurant, tour, and so
/// on — as returned by `GET /api/trips/:tripId/reservations` (see
/// [ReservationsApi]).
///
/// Confirmed against Trek's `reservationSchema`
/// (`shared/src/reservation/reservation.schema.ts`) and the
/// `ReservationsService.list` query (`server/src/nest/reservations/`): the
/// row is the `reservations` table (`title`, `type`, `status`,
/// `reservation_time` / `reservation_end_time`, `location`,
/// `confirmation_number`, `notes`, `url`, the `day_id` link) plus the
/// `day_number` and `place_name` columns joined in. The list is ordered by
/// `reservation_time` ascending, then `created_at`.
///
/// This first slice models only the fields the Bookings list row renders.
/// The wide provider-ish extras — `metadata`, multi-leg `endpoints`,
/// `travelers`, `day_positions`, the linked-accommodation columns, and the
/// AirTrail sync fields — are intentionally left out until a screen needs
/// them.
///
/// [type] and [status] are never null: the server column defaults are
/// `'other'` and `'pending'`, and this mirrors that when a key is absent.
class Reservation {
  const Reservation({
    required this.id,
    required this.tripId,
    required this.title,
    this.type = 'other',
    this.status = 'pending',
    this.reservationTime,
    this.reservationEndTime,
    this.location,
    this.confirmationNumber,
    this.notes,
    this.url,
    this.dayId,
    this.dayNumber,
    this.placeName,
  });

  final int id;
  final int tripId;
  final String title;

  /// Free-form booking kind — `flight`, `train`, `hotel`, `restaurant`,
  /// `activity`, `car`, `ferry`, `taxi`, … The server never constrains it
  /// to an enum, so treat unknown values as "other".
  final String type;

  /// One of `pending`, `confirmed`, `cancelled` (the values Trek's own
  /// clients write). Not constrained server-side either.
  final String status;

  /// Start / end timestamps the user entered, as free-form strings (the
  /// column is TEXT — usually `YYYY-MM-DD HH:mm` or an ISO string, but not
  /// guaranteed). Null for a booking with no specific time.
  final String? reservationTime;
  final String? reservationEndTime;

  final String? location;
  final String? confirmationNumber;
  final String? notes;
  final String? url;

  /// The day this booking is pinned to, if any. [dayId] is the raw id;
  /// [dayNumber] is the 1-based day index joined in for display (resolving
  /// an id to a calendar date needs the trip's day list — issue #4 — which
  /// isn't modeled client-side yet).
  final int? dayId;
  final int? dayNumber;

  /// Name of the linked place, joined in when `place_id` is set.
  final String? placeName;

  static String? _asString(Object? value) => value as String?;

  factory Reservation.fromJson(Map<String, dynamic> json) {
    return Reservation(
      id: json['id'] as int,
      tripId: json['trip_id'] as int,
      title: json['title'] as String,
      type: json['type'] as String? ?? 'other',
      status: json['status'] as String? ?? 'pending',
      reservationTime: _asString(json['reservation_time']),
      reservationEndTime: _asString(json['reservation_end_time']),
      location: _asString(json['location']),
      confirmationNumber: _asString(json['confirmation_number']),
      notes: _asString(json['notes']),
      url: _asString(json['url']),
      dayId: json['day_id'] as int?,
      dayNumber: json['day_number'] as int?,
      placeName: _asString(json['place_name']),
    );
  }

  /// Round-trips a [Reservation] through the local cache (see
  /// `PreferencesReservationsLocalStore`). The wire and cache shapes are
  /// the same snake-cased keys, so this just mirrors [fromJson].
  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'trip_id': tripId,
    'title': title,
    'type': type,
    'status': status,
    'reservation_time': reservationTime,
    'reservation_end_time': reservationEndTime,
    'location': location,
    'confirmation_number': confirmationNumber,
    'notes': notes,
    'url': url,
    'day_id': dayId,
    'day_number': dayNumber,
    'place_name': placeName,
  };

  factory Reservation.fromCacheJson(Map<String, dynamic> json) =>
      Reservation.fromJson(json);
}
