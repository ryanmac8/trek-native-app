/// How a country ended up on the Atlas, mirroring Trek's `VisitStatus`
/// (`@trek/shared`'s `visitStatusSchema`):
///
/// - [visited]: at least one source is a trip that has already started, or a
///   manual mark.
/// - [planned]: every source is a trip starting in the future.
/// - [idea]: every source is a trip with no dates at all.
enum VisitStatus {
  visited,
  planned,
  idea;

  /// Unknown or missing values read as [visited] — the only kind of entry
  /// Trek's zero-trip response contains (manually marked countries), and
  /// the status it assigned to every country before statuses existed.
  static VisitStatus parse(Object? value) => switch (value) {
    'planned' => VisitStatus.planned,
    'idea' => VisitStatus.idea,
    _ => VisitStatus.visited,
  };
}

/// One entry of the stats response's `countries` array.
class AtlasCountry {
  const AtlasCountry({
    required this.code,
    required this.placeCount,
    required this.tripCount,
    required this.status,
    this.firstVisit,
    this.lastVisit,
  });

  factory AtlasCountry.fromJson(Map<String, dynamic> json) {
    return AtlasCountry(
      code: json['code'] as String,
      placeCount: _int(json['placeCount']),
      tripCount: _int(json['tripCount']),
      status: VisitStatus.parse(json['status']),
      firstVisit: json['firstVisit'] as String?,
      lastVisit: json['lastVisit'] as String?,
    );
  }

  /// ISO 3166-1 alpha-2 code, upper-case (e.g. `NZ`).
  final String code;
  final int placeCount;
  final int tripCount;
  final VisitStatus status;

  /// `YYYY-MM-DD`, or `null` when no dated trip backs this country.
  final String? firstVisit;
  final String? lastVisit;

  /// The country's flag emoji, built from its two regional-indicator
  /// letters. Falls back to the plain code for anything that isn't two
  /// ASCII letters.
  String get flag => countryFlag(code);

  Map<String, dynamic> toJson() => {
    'code': code,
    'placeCount': placeCount,
    'tripCount': tripCount,
    'status': status.name,
    'firstVisit': firstVisit,
    'lastVisit': lastVisit,
  };
}

/// The most recent trip that has ended (`lastTrip` in the response).
class AtlasLastTrip {
  const AtlasLastTrip({
    required this.id,
    required this.title,
    this.startDate,
    this.endDate,
    this.countryCode,
  });

  factory AtlasLastTrip.fromJson(Map<String, dynamic> json) {
    return AtlasLastTrip(
      id: _int(json['id']),
      title: json['title'] as String? ?? '',
      startDate: json['start_date'] as String?,
      endDate: json['end_date'] as String?,
      countryCode: json['countryCode'] as String?,
    );
  }

  final int id;
  final String title;
  final String? startDate;
  final String? endDate;

  /// The first of the trip's places that resolved to a country, if any.
  final String? countryCode;

  /// Whole calendar days since [endDate] relative to [today], or `null` if
  /// the trip has no end date.
  int? daysSinceEnd(DateTime today) {
    final end = parseTrekDate(endDate);
    if (end == null) return null;
    return calendarDaysBetween(end, today);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'start_date': startDate,
    'end_date': endDate,
    if (countryCode != null) 'countryCode': countryCode,
  };
}

/// The soonest trip that hasn't started yet (`nextTrip` in the response).
class AtlasNextTrip {
  const AtlasNextTrip({required this.id, required this.title, this.startDate});

  factory AtlasNextTrip.fromJson(Map<String, dynamic> json) {
    return AtlasNextTrip(
      id: _int(json['id']),
      title: json['title'] as String? ?? '',
      startDate: json['start_date'] as String?,
    );
  }

  final int id;
  final String title;
  final String? startDate;

  /// Whole calendar days from [today] until [startDate] — 0 on the start
  /// day itself, negative once it has passed, `null` without a start date.
  ///
  /// Computed on the device rather than read from the server's `daysUntil`,
  /// which is a snapshot of the moment the stats were fetched and would go
  /// stale in the offline cache.
  int? daysUntil(DateTime today) {
    final start = parseTrekDate(startDate);
    if (start == null) return null;
    return calendarDaysBetween(today, start);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'start_date': startDate,
  };
}

/// `GET /api/addons/atlas/stats` — the signed-in user's cross-trip travel
/// statistics.
///
/// Trek answers a user with no trips with a reduced shape (`countries`,
/// `trips: []`, and `stats` with only `totalTrips`/`totalPlaces`/
/// `totalCountries`/`totalDays`), so every field other than `countries` and
/// `stats` is optional here and missing counters read as 0.
class AtlasStats {
  const AtlasStats({
    required this.countries,
    required this.totalTrips,
    required this.totalPlaces,
    required this.totalCountries,
    required this.totalCountriesPlanned,
    required this.totalCountriesIdea,
    required this.totalDays,
    required this.totalCities,
    required this.continents,
    required this.continentsPlanned,
    required this.streak,
    required this.tripsThisYear,
    this.mostVisited,
    this.lastTrip,
    this.nextTrip,
    this.firstYear,
  });

  factory AtlasStats.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? const {};
    final mostVisited = json['mostVisited'];
    final lastTrip = json['lastTrip'];
    final nextTrip = json['nextTrip'];
    return AtlasStats(
      countries: [
        for (final entry in json['countries'] as List<dynamic>? ?? const [])
          AtlasCountry.fromJson(entry as Map<String, dynamic>),
      ],
      totalTrips: _int(stats['totalTrips']),
      totalPlaces: _int(stats['totalPlaces']),
      totalCountries: _int(stats['totalCountries']),
      totalCountriesPlanned: _int(stats['totalCountriesPlanned']),
      totalCountriesIdea: _int(stats['totalCountriesIdea']),
      totalDays: _int(stats['totalDays']),
      totalCities: _int(stats['totalCities']),
      mostVisited: mostVisited is Map<String, dynamic>
          ? AtlasCountry.fromJson(mostVisited)
          : null,
      continents: _counts(json['continents']),
      continentsPlanned: _counts(json['continentsPlanned']),
      lastTrip: lastTrip is Map<String, dynamic>
          ? AtlasLastTrip.fromJson(lastTrip)
          : null,
      nextTrip: nextTrip is Map<String, dynamic>
          ? AtlasNextTrip.fromJson(nextTrip)
          : null,
      streak: _int(json['streak']),
      firstYear: json['firstYear'] is num
          ? (json['firstYear'] as num).toInt()
          : null,
      tripsThisYear: _int(json['tripsThisYear']),
    );
  }

  /// Every country on the Atlas, including planned and idea-only entries.
  final List<AtlasCountry> countries;

  final int totalTrips;
  final int totalPlaces;

  /// Visited countries only — planned and idea-only ones are counted
  /// separately.
  final int totalCountries;
  final int totalCountriesPlanned;
  final int totalCountriesIdea;

  /// Sum of each dated trip's inclusive day span.
  final int totalDays;

  /// Distinct cities, derived server-side from place addresses.
  final int totalCities;

  /// The visited country with the most places.
  final AtlasCountry? mostVisited;

  /// Visited countries per continent (`Europe`, `Asia`, …, `Other`).
  final Map<String, int> continents;

  /// Planned countries per continent.
  final Map<String, int> continentsPlanned;

  final AtlasLastTrip? lastTrip;
  final AtlasNextTrip? nextTrip;

  /// Consecutive calendar years, counting back from the current one, with
  /// at least one trip starting in them.
  final int streak;

  /// Year of the earliest dated trip.
  final int? firstYear;

  /// Trips starting in the current calendar year.
  final int tripsThisYear;

  /// Nothing to show at all: no trips and no manually marked countries.
  bool get isEmpty => totalTrips == 0 && countries.isEmpty;

  Map<String, dynamic> toJson() => {
    'countries': [for (final c in countries) c.toJson()],
    'stats': {
      'totalTrips': totalTrips,
      'totalPlaces': totalPlaces,
      'totalCountries': totalCountries,
      'totalCountriesPlanned': totalCountriesPlanned,
      'totalCountriesIdea': totalCountriesIdea,
      'totalDays': totalDays,
      'totalCities': totalCities,
    },
    'mostVisited': mostVisited?.toJson(),
    'continents': continents,
    'continentsPlanned': continentsPlanned,
    'lastTrip': lastTrip?.toJson(),
    'nextTrip': nextTrip?.toJson(),
    'streak': streak,
    'firstYear': firstYear,
    'tripsThisYear': tripsThisYear,
  };
}

/// A cached [AtlasStats] snapshot plus when it was fetched.
class CachedAtlasStats {
  const CachedAtlasStats({required this.stats, required this.fetchedAt});

  factory CachedAtlasStats.fromJson(Map<String, dynamic> json) {
    return CachedAtlasStats(
      stats: AtlasStats.fromJson(json['stats'] as Map<String, dynamic>),
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
    );
  }

  final AtlasStats stats;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => {
    'stats': stats.toJson(),
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
  };
}

/// Parses Trek's `YYYY-MM-DD` date strings into a date-only [DateTime].
DateTime? parseTrekDate(String? value) {
  if (value == null || value.length < 10) return null;
  final parsed = DateTime.tryParse(value.substring(0, 10));
  if (parsed == null) return null;
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}

/// Whole calendar days from [from] to [to], ignoring time of day and
/// time zone offsets (both are reduced to their year/month/day).
int calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// A flag emoji for an ISO 3166-1 alpha-2 [code], or the code itself if it
/// isn't two ASCII letters.
String countryFlag(String code) {
  final upper = code.toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(upper)) return upper;
  const regionalIndicatorA = 0x1F1E6;
  return String.fromCharCodes([
    for (final unit in upper.codeUnits)
      regionalIndicatorA + unit - 'A'.codeUnitAt(0),
  ]);
}

int _int(Object? value) => value is num ? value.toInt() : 0;

Map<String, int> _counts(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: _int(entry.value),
  };
}
