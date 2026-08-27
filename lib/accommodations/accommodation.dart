/// A lodging block for a trip, as returned by
/// `GET /api/trips/:tripId/accommodations` (see [AccommodationsApi]).
///
/// Confirmed against Trek's `accommodationSchema`
/// (`shared/src/reservation/reservation.schema.ts`) and the
/// `listAccommodations` query (`server/src/services/dayService.ts`): the
/// row is the `day_accommodations` table (`place_id`, the `start_day_id` /
/// `end_day_id` bounds, the `check_in` / `check_in_end` / `check_out` date
/// strings, `confirmation`, `notes`) plus the place columns joined in
/// (`place_name`, `place_address`, and `place_image` / `place_lat` /
/// `place_lng`, which this slice doesn't model yet) and `reservation_title`
/// from the linked reservation, if any.
///
/// [placeId] is null when the linked place has been deleted
/// (`ON DELETE SET NULL`). [startDayId] / [endDayId] are always present but
/// are only day *ids* — resolving them to calendar dates needs the trip's
/// day list, which isn't modeled client-side yet (issue #4), so the list
/// row leans on [checkIn] / [checkOut] instead.
class Accommodation {
  const Accommodation({
    required this.id,
    required this.tripId,
    this.placeId,
    this.placeName,
    this.placeAddress,
    required this.startDayId,
    required this.endDayId,
    this.checkIn,
    this.checkInEnd,
    this.checkOut,
    this.confirmation,
    this.notes,
    this.reservationTitle,
  });

  final int id;
  final int tripId;
  final int? placeId;
  final String? placeName;
  final String? placeAddress;
  final int startDayId;
  final int endDayId;

  /// `YYYY-MM-DD` date strings the user entered for the stay, independent
  /// of the day-id bounds. [checkInEnd] is the late end of a check-in
  /// window when the arrival date is a range rather than a single day.
  final String? checkIn;
  final String? checkInEnd;
  final String? checkOut;
  final String? confirmation;
  final String? notes;

  /// Title of the reservation Trek auto-links to an accommodation, when one
  /// exists — shown as context, not editable from here.
  final String? reservationTitle;

  factory Accommodation.fromJson(Map<String, dynamic> json) {
    return Accommodation(
      id: json['id'] as int,
      tripId: json['trip_id'] as int,
      placeId: json['place_id'] as int?,
      placeName: json['place_name'] as String?,
      placeAddress: json['place_address'] as String?,
      startDayId: json['start_day_id'] as int,
      endDayId: json['end_day_id'] as int,
      checkIn: json['check_in'] as String?,
      checkInEnd: json['check_in_end'] as String?,
      checkOut: json['check_out'] as String?,
      confirmation: json['confirmation'] as String?,
      notes: json['notes'] as String?,
      reservationTitle: json['reservation_title'] as String?,
    );
  }

  /// Round-trips an [Accommodation] through the local cache (see
  /// `PreferencesAccommodationsLocalStore`). The wire and cache shapes are
  /// the same snake-cased keys, so this just mirrors [fromJson].
  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'trip_id': tripId,
    'place_id': placeId,
    'place_name': placeName,
    'place_address': placeAddress,
    'start_day_id': startDayId,
    'end_day_id': endDayId,
    'check_in': checkIn,
    'check_in_end': checkInEnd,
    'check_out': checkOut,
    'confirmation': confirmation,
    'notes': notes,
    'reservation_title': reservationTitle,
  };

  factory Accommodation.fromCacheJson(Map<String, dynamic> json) =>
      Accommodation.fromJson(json);
}
