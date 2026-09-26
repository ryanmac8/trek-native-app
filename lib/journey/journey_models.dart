/// Models for Trek's Journey addon (`/api/journeys`), read-only for now.
/// See docs/journey.md for the wire contract.
///
/// Each model's `fromJson` parses Trek's wire shape; `toJson` writes the
/// same keys back, so a cached snapshot round-trips through `fromJson`.
library;

/// A snapshot plus when it was fetched from the server, so the UI can say
/// how stale an offline copy is.
class CachedJourney<T> {
  const CachedJourney({required this.value, required this.fetchedAt});

  final T value;
  final DateTime fetchedAt;
}

/// `journeys.status` — any other value from a newer server reads as
/// [JourneyStatus.active] rather than failing the whole list.
enum JourneyStatus {
  draft,
  active,
  completed,
  archived;

  static JourneyStatus parse(Object? raw) => JourneyStatus.values.firstWhere(
    (s) => s.name == raw,
    orElse: () => JourneyStatus.active,
  );

  String get label => switch (this) {
    JourneyStatus.draft => 'Draft',
    JourneyStatus.active => 'Active',
    JourneyStatus.completed => 'Completed',
    JourneyStatus.archived => 'Archived',
  };
}

/// The viewer's role on a journey (`my_role` / `journey_contributors.role`).
enum JourneyRole {
  owner,
  editor,
  viewer;

  static JourneyRole? parse(Object? raw) {
    for (final role in JourneyRole.values) {
      if (role.name == raw) return role;
    }
    return null;
  }

  String get label => switch (this) {
    JourneyRole.owner => 'Owner',
    JourneyRole.editor => 'Editor',
    JourneyRole.viewer => 'Viewer',
  };
}

/// One row of `GET /api/journeys` — journeys the user owns or contributes
/// to, newest-updated first.
class JourneySummary {
  const JourneySummary({
    required this.id,
    required this.ownerId,
    required this.title,
    this.subtitle,
    this.coverGradient,
    required this.status,
    required this.entryCount,
    required this.photoCount,
    required this.placeCount,
    this.tripDateMin,
    this.tripDateMax,
    required this.updatedAt,
  });

  final int id;

  /// `user_id` — the journey's creator.
  final int ownerId;
  final String title;
  final String? subtitle;

  /// A CSS gradient string (e.g. `linear-gradient(...)`) or `null`.
  final String? coverGradient;
  final JourneyStatus status;

  /// Written entries (skeleton suggestions excluded).
  final int entryCount;
  final int photoCount;

  /// Distinct non-empty entry location names.
  final int placeCount;

  /// Earliest `start_date` / latest `end_date` across linked trips
  /// (`YYYY-MM-DD`), or `null` with no linked trips.
  final String? tripDateMin;
  final String? tripDateMax;

  /// `updated_at` in epoch milliseconds.
  final int updatedAt;

  factory JourneySummary.fromJson(Map<String, dynamic> json) => JourneySummary(
    id: json['id'] as int,
    ownerId: json['user_id'] as int,
    title: json['title'] as String? ?? '',
    subtitle: _nonEmpty(json['subtitle']),
    coverGradient: _nonEmpty(json['cover_gradient']),
    status: JourneyStatus.parse(json['status']),
    entryCount: _int(json['entry_count']),
    photoCount: _int(json['photo_count']),
    placeCount: _int(json['place_count']),
    tripDateMin: _nonEmpty(json['trip_date_min']),
    tripDateMax: _nonEmpty(json['trip_date_max']),
    updatedAt: _int(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': ownerId,
    'title': title,
    'subtitle': subtitle,
    'cover_gradient': coverGradient,
    'status': status.name,
    'entry_count': entryCount,
    'photo_count': photoCount,
    'place_count': placeCount,
    'trip_date_min': tripDateMin,
    'trip_date_max': tripDateMax,
    'updated_at': updatedAt,
  };
}

/// `GET /api/journeys` → `{ journeys: [...] }`.
class JourneyList {
  const JourneyList(this.journeys);

  final List<JourneySummary> journeys;

  factory JourneyList.fromJson(Map<String, dynamic> json) => JourneyList([
    for (final j in json['journeys'] as List? ?? const [])
      JourneySummary.fromJson(j as Map<String, dynamic>),
  ]);

  Map<String, dynamic> toJson() => {
    'journeys': [for (final j in journeys) j.toJson()],
  };
}

/// `entries[].type`: a written entry, a quick check-in, or a skeleton —
/// a placeholder the server derives from a linked trip's itinerary for the
/// user to write up.
enum JourneyEntryType {
  entry,
  checkin,
  skeleton;

  static JourneyEntryType parse(Object? raw) => JourneyEntryType.values
      .firstWhere((t) => t.name == raw, orElse: () => JourneyEntryType.entry);
}

class JourneyEntry {
  const JourneyEntry({
    required this.id,
    required this.type,
    this.title,
    this.story,
    required this.entryDate,
    this.entryTime,
    this.locationName,
    this.mood,
    this.weather,
    this.tags = const [],
    this.pros = const [],
    this.cons = const [],
    required this.photoCount,
    this.sourceTripName,
  });

  final int id;
  final JourneyEntryType type;
  final String? title;
  final String? story;

  /// `YYYY-MM-DD`.
  final String entryDate;

  /// `HH:MM`, or `null`.
  final String? entryTime;
  final String? locationName;
  final String? mood;
  final String? weather;
  final List<String> tags;
  final List<String> pros;
  final List<String> cons;

  /// Number of photos attached to the entry (the photos themselves aren't
  /// cached or shown yet).
  final int photoCount;

  /// Title of the linked trip a skeleton was derived from.
  final String? sourceTripName;

  factory JourneyEntry.fromJson(Map<String, dynamic> json) {
    final prosCons = json['pros_cons'];
    return JourneyEntry(
      id: json['id'] as int,
      type: JourneyEntryType.parse(json['type']),
      title: _nonEmpty(json['title']),
      story: _nonEmpty(json['story']),
      entryDate: json['entry_date'] as String,
      entryTime: _nonEmpty(json['entry_time']),
      locationName: _nonEmpty(json['location_name']),
      mood: _nonEmpty(json['mood']),
      weather: _nonEmpty(json['weather']),
      tags: _strings(json['tags']),
      pros: prosCons is Map ? _strings(prosCons['pros']) : const [],
      cons: prosCons is Map ? _strings(prosCons['cons']) : const [],
      photoCount: json['photos'] is List
          ? (json['photos'] as List).length
          : _int(json['photo_count']),
      sourceTripName: _nonEmpty(json['source_trip_name']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'story': story,
    'entry_date': entryDate,
    'entry_time': entryTime,
    'location_name': locationName,
    'mood': mood,
    'weather': weather,
    'tags': tags,
    'pros_cons': pros.isEmpty && cons.isEmpty
        ? null
        : {'pros': pros, 'cons': cons},
    'photo_count': photoCount,
    'source_trip_name': sourceTripName,
  };
}

/// A trip linked to a journey (`trips[]`).
class JourneyTrip {
  const JourneyTrip({
    required this.tripId,
    required this.title,
    this.startDate,
    this.endDate,
    required this.placeCount,
  });

  final int tripId;
  final String title;
  final String? startDate;
  final String? endDate;
  final int placeCount;

  factory JourneyTrip.fromJson(Map<String, dynamic> json) => JourneyTrip(
    tripId: json['trip_id'] as int,
    title: json['title'] as String? ?? '',
    startDate: _nonEmpty(json['start_date']),
    endDate: _nonEmpty(json['end_date']),
    placeCount: _int(json['place_count']),
  );

  Map<String, dynamic> toJson() => {
    'trip_id': tripId,
    'title': title,
    'start_date': startDate,
    'end_date': endDate,
    'place_count': placeCount,
  };
}

/// A journey contributor (`contributors[]`). Only the fields shown are
/// kept — avatars aren't cached.
class JourneyContributor {
  const JourneyContributor({
    required this.userId,
    required this.username,
    required this.role,
  });

  final int userId;
  final String username;
  final JourneyRole role;

  factory JourneyContributor.fromJson(Map<String, dynamic> json) =>
      JourneyContributor(
        userId: json['user_id'] as int,
        username: json['username'] as String? ?? '',
        role: JourneyRole.parse(json['role']) ?? JourneyRole.viewer,
      );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'username': username,
    'role': role.name,
  };
}

/// `GET /api/journeys/:id` — one journey with its entries, linked trips,
/// contributors, and stats. Gallery photos aren't kept (only counted in
/// [statPhotos]).
class JourneyDetail {
  const JourneyDetail({
    required this.id,
    required this.title,
    this.subtitle,
    required this.status,
    required this.entries,
    required this.trips,
    required this.contributors,
    required this.statEntries,
    required this.statPhotos,
    required this.statPlaces,
    required this.hideSkeletons,
    this.myRole,
  });

  final int id;
  final String title;
  final String? subtitle;
  final JourneyStatus status;

  /// Sorted by date, then the server's sort order — as the server returns
  /// them. Dismissed suggestions are already left out server-side.
  final List<JourneyEntry> entries;
  final List<JourneyTrip> trips;
  final List<JourneyContributor> contributors;
  final int statEntries;
  final int statPhotos;
  final int statPlaces;

  /// The viewer's per-journey preference to hide skeleton suggestions.
  final bool hideSkeletons;
  final JourneyRole? myRole;

  /// [entries] with skeletons dropped when [hideSkeletons] is set.
  List<JourneyEntry> get visibleEntries => hideSkeletons
      ? [
          for (final e in entries)
            if (e.type != JourneyEntryType.skeleton) e,
        ]
      : entries;

  factory JourneyDetail.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? const {};
    return JourneyDetail(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      subtitle: _nonEmpty(json['subtitle']),
      status: JourneyStatus.parse(json['status']),
      entries: [
        for (final e in json['entries'] as List? ?? const [])
          JourneyEntry.fromJson(e as Map<String, dynamic>),
      ],
      trips: [
        for (final t in json['trips'] as List? ?? const [])
          JourneyTrip.fromJson(t as Map<String, dynamic>),
      ],
      contributors: [
        for (final c in json['contributors'] as List? ?? const [])
          JourneyContributor.fromJson(c as Map<String, dynamic>),
      ],
      statEntries: _int(stats['entries']),
      statPhotos: _int(stats['photos']),
      statPlaces: _int(stats['places']),
      hideSkeletons: _bool(json['hide_skeletons']),
      myRole: JourneyRole.parse(json['my_role']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'status': status.name,
    'entries': [for (final e in entries) e.toJson()],
    'trips': [for (final t in trips) t.toJson()],
    'contributors': [for (final c in contributors) c.toJson()],
    'stats': {
      'entries': statEntries,
      'photos': statPhotos,
      'places': statPlaces,
    },
    'hide_skeletons': hideSkeletons,
    'my_role': myRole?.name,
  };
}

String? _nonEmpty(Object? raw) =>
    raw is String && raw.trim().isNotEmpty ? raw : null;

int _int(Object? raw) => raw is num ? raw.toInt() : 0;

bool _bool(Object? raw) => raw == true || raw == 1;

List<String> _strings(Object? raw) => raw is List
    ? [
        for (final s in raw)
          if (s is String && s.isNotEmpty) s,
      ]
    : const [];
