/// Data types for Trek's transit + airport search endpoints.
///
/// Confirmed against Trek's backend (`server/src/nest/transit/` and
/// `server/src/nest/airports/`):
///
/// - `GET /api/transit/geocode?q=&lang=&near=` → `{ results: TransitPlace[] }`
///   (`TransitService.geocode`, mapped from a MOTIS/Transitous instance).
/// - `GET /api/transit/plan?from=&to=&time=&arriveBy=&modes=&maxTransfers=` →
///   `{ itineraries: TransitItinerary[] }` (`TransitService.plan`). `from` /
///   `to` are `"lat,lng"` strings.
/// - `GET /api/airports/search?q=` → `Airport[]`;
///   `GET /api/airports/:iata` → `Airport` or `404 { error: 'Airport not
///   found' }` (`AirportsController`).
///
/// The wire shape and the local-cache shape are the same JSON here, so
/// `fromJson` / `toJson` round-trip through [TransitLocalStore].
library;

import 'dart:convert';

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

int _toInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

int? _toIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String? _toStringOrNull(Object? value) => value is String ? value : null;

/// A transit stop / station / place from `GET /api/transit/geocode`.
class TransitPlace {
  const TransitPlace({
    required this.name,
    required this.lat,
    required this.lng,
    this.type = 'PLACE',
    this.area,
  });

  final String name;
  final double lat;
  final double lng;

  /// The provider's classification — `STOP`, `PLACE`, `ADDRESS`, … Kept as a
  /// raw string; the UI only groups on "is this a stop".
  final String type;

  /// The enclosing area name (city / region) the provider matched, when it
  /// gave one.
  final String? area;

  /// `"lat,lng"` — the format `GET /api/transit/plan` expects for `from` /
  /// `to`.
  String get coordinate => '$lat,$lng';

  factory TransitPlace.fromJson(Map<String, dynamic> json) {
    return TransitPlace(
      name: json['name'] as String? ?? '',
      lat: _toDouble(json['lat']),
      lng: _toDouble(json['lng']),
      type: json['type'] as String? ?? 'PLACE',
      area: _toStringOrNull(json['area']),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'lat': lat,
    'lng': lng,
    'type': type,
    'area': area,
  };
}

/// One end of a [TransitLeg] — where it departs from or arrives at.
class TransitLegStop {
  const TransitLegStop({
    required this.name,
    this.lat = 0,
    this.lng = 0,
    this.time,
    this.scheduledTime,
    this.track,
  });

  final String name;
  final double lat;
  final double lng;

  /// Real (delay-adjusted) time at this stop, ISO-8601, or null when the
  /// feed has no realtime data.
  final String? time;

  /// Scheduled time at this stop, ISO-8601, or null.
  final String? scheduledTime;

  /// Platform / track label, when the feed carries one.
  final String? track;

  factory TransitLegStop.fromJson(Map<String, dynamic> json) {
    return TransitLegStop(
      name: json['name'] as String? ?? '',
      lat: _toDouble(json['lat']),
      lng: _toDouble(json['lng']),
      time: _toStringOrNull(json['time']),
      scheduledTime: _toStringOrNull(json['scheduledTime']),
      track: _toStringOrNull(json['track']),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'lat': lat,
    'lng': lng,
    'time': time,
    'scheduledTime': scheduledTime,
    'track': track,
  };
}

/// A single segment of a [TransitItinerary] — a walk or one scheduled
/// vehicle run.
class TransitLeg {
  const TransitLeg({
    required this.mode,
    required this.from,
    required this.to,
    this.duration = 0,
    this.distance,
    this.headsign,
    this.line,
    this.lineColor,
    this.lineTextColor,
    this.agency,
    this.intermediateStops = 0,
  });

  /// `WALK`, `BUS`, `RAIL`, `SUBWAY`, `TRAM`, `FERRY`, … (MOTIS mode
  /// taxonomy, upper-cased by the server).
  final String mode;
  final TransitLegStop from;
  final TransitLegStop to;

  /// Leg run-time in seconds.
  final int duration;

  /// Leg distance in metres, when the provider reported it.
  final int? distance;

  /// The vehicle's destination sign, e.g. "Flughafen".
  final String? headsign;

  /// The public line identifier the provider resolved, e.g. "ICE 72" or
  /// "M4". Null for walk legs.
  final String? line;

  /// `#`-prefixed hex line colours from the GTFS feed, when present.
  final String? lineColor;
  final String? lineTextColor;

  final String? agency;

  /// Number of stops passed through without a transfer.
  final int intermediateStops;

  bool get isWalk => mode == 'WALK';

  factory TransitLeg.fromJson(Map<String, dynamic> json) {
    return TransitLeg(
      mode: (json['mode'] as String? ?? 'WALK').toUpperCase(),
      from: TransitLegStop.fromJson(
        json['from'] as Map<String, dynamic>? ?? const {},
      ),
      to: TransitLegStop.fromJson(
        json['to'] as Map<String, dynamic>? ?? const {},
      ),
      duration: _toInt(json['duration']),
      distance: _toIntOrNull(json['distance']),
      headsign: _toStringOrNull(json['headsign']),
      line: _toStringOrNull(json['line']),
      lineColor: _toStringOrNull(json['lineColor']),
      lineTextColor: _toStringOrNull(json['lineTextColor']),
      agency: _toStringOrNull(json['agency']),
      intermediateStops: _toInt(json['intermediateStops']),
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'from': from.toJson(),
    'to': to.toJson(),
    'duration': duration,
    'distance': distance,
    'headsign': headsign,
    'line': line,
    'lineColor': lineColor,
    'lineTextColor': lineTextColor,
    'agency': agency,
    'intermediateStops': intermediateStops,
  };
}

/// One suggested public-transit journey from `GET /api/transit/plan`.
class TransitItinerary {
  const TransitItinerary({
    required this.startTime,
    required this.endTime,
    this.duration = 0,
    this.transfers = 0,
    this.walkSeconds = 0,
    this.legs = const [],
  });

  /// ISO-8601 departure / arrival timestamps for the whole journey.
  final String startTime;
  final String endTime;

  /// Wall-clock duration in seconds (start → end, so waits count).
  final int duration;
  final int transfers;

  /// Total time spent walking, in seconds.
  final int walkSeconds;

  final List<TransitLeg> legs;

  /// The scheduled (non-walk) legs, in order — what the summary row shows.
  List<TransitLeg> get transitLegs =>
      legs.where((leg) => !leg.isWalk).toList(growable: false);

  factory TransitItinerary.fromJson(Map<String, dynamic> json) {
    final rawLegs = json['legs'] as List<dynamic>? ?? const [];
    return TransitItinerary(
      startTime: json['startTime'] as String? ?? '',
      endTime: json['endTime'] as String? ?? '',
      duration: _toInt(json['duration']),
      transfers: _toInt(json['transfers']),
      walkSeconds: _toInt(json['walkSeconds']),
      legs: rawLegs
          .map((e) => TransitLeg.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'startTime': startTime,
    'endTime': endTime,
    'duration': duration,
    'transfers': transfers,
    'walkSeconds': walkSeconds,
    'legs': legs.map((leg) => leg.toJson()).toList(),
  };
}

/// An airport record from `GET /api/airports/*` (`airportSchema` in Trek's
/// shared package).
class Airport {
  const Airport({
    required this.iata,
    required this.name,
    required this.city,
    required this.country,
    required this.lat,
    required this.lng,
    required this.tz,
    this.icao,
  });

  final String iata;
  final String? icao;
  final String name;
  final String city;
  final String country;
  final double lat;
  final double lng;

  /// IANA timezone identifier, e.g. `Pacific/Auckland`.
  final String tz;

  factory Airport.fromJson(Map<String, dynamic> json) {
    return Airport(
      iata: json['iata'] as String? ?? '',
      icao: _toStringOrNull(json['icao']),
      name: json['name'] as String? ?? '',
      city: json['city'] as String? ?? '',
      country: json['country'] as String? ?? '',
      lat: _toDouble(json['lat']),
      lng: _toDouble(json['lng']),
      tz: json['tz'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'iata': iata,
    'icao': icao,
    'name': name,
    'city': city,
    'country': country,
    'lat': lat,
    'lng': lng,
    'tz': tz,
  };
}

/// The parameters for a `GET /api/transit/plan` route search.
///
/// Only `from` / `to` are required; the server defaults to "leave now" when
/// [departAt] is null and accepts an empty [modes] list as "all transit
/// modes". [modes] values are validated server-side against a whitelist
/// (`SCHEDULED_TRANSIT_MODES`); [maxTransfers] must be 0–10.
class TransitPlanQuery {
  const TransitPlanQuery({
    required this.from,
    required this.to,
    this.departAt,
    this.arriveBy = false,
    this.modes = const [],
    this.maxTransfers,
  });

  /// `"lat,lng"` strings — see [TransitPlace.coordinate].
  final String from;
  final String to;

  /// When to depart (or arrive, if [arriveBy]). Null = leave now.
  final DateTime? departAt;
  final bool arriveBy;
  final List<String> modes;
  final int? maxTransfers;

  Map<String, dynamic> toQueryParameters() => {
    'from': from,
    'to': to,
    if (departAt != null) 'time': departAt!.toUtc().toIso8601String(),
    if (arriveBy) 'arriveBy': 'true',
    if (modes.isNotEmpty) 'modes': modes.join(','),
    if (maxTransfers != null) 'maxTransfers': '$maxTransfers',
  };

  /// Stable key for the local plan cache — independent of map ordering.
  String get cacheKey => jsonEncode({
    'from': from,
    'to': to,
    'time': departAt?.toUtc().toIso8601String(),
    'arriveBy': arriveBy,
    'modes': [...modes]..sort(),
    'maxTransfers': maxTransfers,
  });
}
