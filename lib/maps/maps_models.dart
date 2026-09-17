/// Data types for Trek's maps/geocoding endpoints.
///
/// Confirmed against Trek's backend (`server/src/nest/maps/maps.controller.ts`
/// and `server/src/nest/maps/maps.service.ts`, plus the Zod contract in
/// `@trek/shared/maps/maps.schema.ts`). Both endpoints below are JWT-guarded
/// (`@UseGuards(JwtAuthGuard)` on `MapsController`).
///
/// The full `/api/maps` surface also covers text search, autocomplete, place
/// details and photos — those return open, provider-shaped records (Google
/// vs. OpenStreetMap fields differ) and are left for a follow-up slice of
/// [#17](https://github.com/ryanmac8/trek-native-app/issues/17). Reverse
/// geocoding and URL resolution both have a small, fixed response shape,
/// which is what makes them a reasonable first cut.
library;

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

String? _toStringOrNull(Object? value) => value is String ? value : null;

/// A latitude/longitude pair.
class LatLng {
  const LatLng(this.lat, this.lng);

  final double lat;
  final double lng;

  /// Rounded to 5 decimal places (~1.1m) so two lookups for effectively the
  /// same pin share a cache entry.
  String get cacheKey => '${lat.toStringAsFixed(5)}_${lng.toStringAsFixed(5)}';

  factory LatLng.fromJson(Map<String, dynamic> json) =>
      LatLng(_toDouble(json['lat']), _toDouble(json['lng']));

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  @override
  bool operator ==(Object other) =>
      other is LatLng && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}

/// `GET /api/maps/reverse?lat=&lng=&lang=` result — a best-effort name plus
/// full address for a coordinate (`MapsController.reverse`).
///
/// The server never throws for this endpoint: a lookup failure (including no
/// network path to the geocoder) comes back 200 with `{ name: null, address:
/// null }` rather than a non-2xx response, so there is no error field here —
/// [isEmpty] is how a caller tells "nothing found" from a real answer.
class ReverseGeocodeResult {
  const ReverseGeocodeResult({this.name, this.address});

  final String? name;
  final String? address;

  bool get isEmpty => name == null && address == null;

  factory ReverseGeocodeResult.fromJson(Map<String, dynamic> json) {
    return ReverseGeocodeResult(
      name: _toStringOrNull(json['name']),
      address: _toStringOrNull(json['address']),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'address': address};
}

/// `POST /api/maps/resolve-url { url }` result — a place resolved from a
/// shared Google Maps URL (`MapsController.resolveUrl`). A URL that can't be
/// resolved is a non-2xx response (a [ValidationException] from `ApiClient`),
/// not a null result, so every field here is populated whenever this exists.
class ResolvedPlace {
  const ResolvedPlace({
    required this.point,
    this.name,
    this.address,
    this.googleFtid,
  });

  final LatLng point;
  final String? name;
  final String? address;

  /// Google's stable "feature id" for the place, when the URL resolved to a
  /// specific POI rather than a bare coordinate. Not used yet — kept for when
  /// adding this result to a trip's place pool wants to dedupe against a
  /// place already there.
  final String? googleFtid;

  factory ResolvedPlace.fromJson(Map<String, dynamic> json) {
    return ResolvedPlace(
      point: LatLng.fromJson(json),
      name: _toStringOrNull(json['name']),
      address: _toStringOrNull(json['address']),
      googleFtid: _toStringOrNull(json['google_ftid']),
    );
  }

  Map<String, dynamic> toJson() => {
    ...point.toJson(),
    'name': name,
    'address': address,
    if (googleFtid != null) 'google_ftid': googleFtid,
  };
}
