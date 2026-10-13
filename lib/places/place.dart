/// The category embedded on a [Place], as returned by
/// `GET /api/trips/:tripId/places` (see [PlacesApi]) — a trimmed projection
/// of a categories row (id/name/color/icon), confirmed against Trek's real
/// `placeCategorySchema`. `null` on a place with no `category_id` set.
///
/// Named `PlaceCategoryRef` (not `PlaceCategory`) to avoid colliding with
/// the design system's `PlaceCategory` enum
/// ([lib/design/place_category_colors.dart]), which models the fixed
/// default-category tokens rather than a place's actual assigned category.
class PlaceCategoryRef {
  const PlaceCategoryRef({required this.id, this.name, this.color, this.icon});

  final int id;
  final String? name;

  /// A hex color string (e.g. `#3b82f6`), matching the default categories'
  /// seed colors in Trek's backend (`server/src/db/seeds.ts`).
  final String? color;
  final String? icon;

  factory PlaceCategoryRef.fromJson(Map<String, dynamic> json) {
    return PlaceCategoryRef(
      id: json['id'] as int,
      name: json['name'] as String?,
      color: json['color'] as String?,
      icon: json['icon'] as String?,
    );
  }

  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'name': name,
    'color': color,
    'icon': icon,
  };

  factory PlaceCategoryRef.fromCacheJson(Map<String, dynamic> json) =>
      PlaceCategoryRef.fromJson(json);
}

/// Where a cached [Place] stands relative to the server — local-only state,
/// never sent by or to Trek.
enum PlaceSyncStatus {
  /// Matches the last version the server returned.
  synced,

  /// Has a local create/edit not yet accepted by the server.
  pending,

  /// A local edit was rejected with a 409 because someone else changed the
  /// place first; waiting for the user to keep theirs or take the server's.
  conflict,
}

/// A place in a trip's place pool, as returned by
/// `GET /api/trips/:tripId/places` (see [PlacesApi]).
///
/// The real response is much wider (lat/lng, website, phone, image,
/// reservation fields, tags, provider-derived import columns — see Trek's
/// `placeSchema`); this models what the pool row and the place form use.
/// [updatedAt] is Trek's `updated_at`, kept verbatim as the optimistic-
/// concurrency token sent back as `X-Base-Updated-At` on an edit.
class Place {
  const Place({
    required this.id,
    required this.tripId,
    required this.name,
    this.description,
    this.address,
    this.category,
    this.price,
    this.currency,
    this.notes,
    this.updatedAt,
    this.syncStatus = PlaceSyncStatus.synced,
  });

  /// Server id, or a negative temporary id for a place created locally that
  /// the server hasn't accepted yet.
  final int id;
  final int tripId;
  final String name;
  final String? description;
  final String? address;
  final PlaceCategoryRef? category;
  final double? price;
  final String? currency;
  final String? notes;
  final String? updatedAt;
  final PlaceSyncStatus syncStatus;

  bool get isLocalOnly => id < 0;

  factory Place.fromJson(Map<String, dynamic> json) {
    final categoryJson = json['category'] as Map<String, dynamic>?;
    return Place(
      id: json['id'] as int,
      tripId: json['trip_id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      address: json['address'] as String?,
      category: categoryJson != null
          ? PlaceCategoryRef.fromJson(categoryJson)
          : null,
      price: (json['price'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      notes: json['notes'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  /// Round-trips a [Place] through the local cache (see
  /// `PreferencesPlacesLocalStore`).
  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'trip_id': tripId,
    'name': name,
    'description': description,
    'address': address,
    'category': category?.toCacheJson(),
    'price': price,
    'currency': currency,
    'notes': notes,
    'updated_at': updatedAt,
    'sync_status': syncStatus.name,
  };

  factory Place.fromCacheJson(Map<String, dynamic> json) {
    final categoryJson = json['category'] as Map<String, dynamic>?;
    final status = json['sync_status'] as String?;
    return Place(
      id: json['id'] as int,
      tripId: json['trip_id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      address: json['address'] as String?,
      category: categoryJson != null
          ? PlaceCategoryRef.fromCacheJson(categoryJson)
          : null,
      price: (json['price'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      notes: json['notes'] as String?,
      updatedAt: json['updated_at'] as String?,
      syncStatus: PlaceSyncStatus.values.firstWhere(
        (value) => value.name == status,
        orElse: () => PlaceSyncStatus.synced,
      ),
    );
  }

  /// This place with [fields] — a request body in Trek's wire format, as
  /// built by [PlaceInput] — applied on top. Only the keys present in
  /// [fields] change; an explicit `null` clears that field.
  Place applyFields(Map<String, dynamic> fields, {PlaceSyncStatus? status}) {
    T? pick<T>(String key, T? current) =>
        fields.containsKey(key) ? fields[key] as T? : current;
    return Place(
      id: id,
      tripId: tripId,
      name: (fields['name'] as String?) ?? name,
      description: pick('description', description),
      address: pick('address', address),
      category: category,
      price: fields.containsKey('price')
          ? (fields['price'] as num?)?.toDouble()
          : price,
      currency: pick('currency', currency),
      notes: pick('notes', notes),
      updatedAt: updatedAt,
      syncStatus: status ?? syncStatus,
    );
  }

  Place withSyncStatus(PlaceSyncStatus status) =>
      applyFields(const {}, status: status);
}

/// The user-editable fields of a place, as entered in the place form. Turns
/// into Trek's request bodies for `POST`/`PUT /api/trips/:tripId/places`.
class PlaceInput {
  const PlaceInput({
    required this.name,
    this.description,
    this.address,
    this.price,
    this.currency,
    this.notes,
  });

  factory PlaceInput.fromPlace(Place place) => PlaceInput(
    name: place.name,
    description: place.description,
    address: place.address,
    price: place.price,
    currency: place.currency,
    notes: place.notes,
  );

  final String name;
  final String? description;
  final String? address;
  final double? price;
  final String? currency;
  final String? notes;

  Map<String, dynamic> _all() => {
    'name': name.trim(),
    'description': _blankToNull(description),
    'address': _blankToNull(address),
    'price': price,
    'currency': _blankToNull(currency)?.toUpperCase(),
    'notes': _blankToNull(notes),
  };

  /// `POST` body: only the fields that have a value.
  Map<String, dynamic> toCreateJson() =>
      Map.of(_all())..removeWhere((key, value) => value == null);

  /// `PUT` body: only the fields that differ from [original], so an offline
  /// edit replayed later doesn't overwrite fields it never touched. A field
  /// the user cleared is sent as `null`. Empty when nothing changed.
  Map<String, dynamic> changesFrom(Place original) {
    final before = PlaceInput.fromPlace(original)._all();
    final after = _all();
    return {
      for (final entry in after.entries)
        if (entry.value != before[entry.key]) entry.key: entry.value,
    };
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
