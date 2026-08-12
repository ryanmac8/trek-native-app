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

/// A place in a trip's place pool, as returned by
/// `GET /api/trips/:tripId/places` (see [PlacesApi]).
///
/// The real response is much wider (description, address, lat/lng, website,
/// phone, image, reservation fields, tags, provider-derived import columns —
/// see Trek's `placeSchema`), but this first read-only slice of issue #5
/// only needs what the pool row renders: name, category, price/currency,
/// and notes. The rest can be added once place detail/edit exists.
class Place {
  const Place({
    required this.id,
    required this.tripId,
    required this.name,
    this.category,
    this.price,
    this.currency,
    this.notes,
  });

  final int id;
  final int tripId;
  final String name;
  final PlaceCategoryRef? category;
  final double? price;
  final String? currency;
  final String? notes;

  factory Place.fromJson(Map<String, dynamic> json) {
    final categoryJson = json['category'] as Map<String, dynamic>?;
    return Place(
      id: json['id'] as int,
      tripId: json['trip_id'] as int,
      name: json['name'] as String,
      category: categoryJson != null
          ? PlaceCategoryRef.fromJson(categoryJson)
          : null,
      price: (json['price'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      notes: json['notes'] as String?,
    );
  }

  /// Round-trips a [Place] through the local cache (see
  /// `PreferencesPlacesLocalStore`).
  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'trip_id': tripId,
    'name': name,
    'category': category?.toCacheJson(),
    'price': price,
    'currency': currency,
    'notes': notes,
  };

  factory Place.fromCacheJson(Map<String, dynamic> json) {
    final categoryJson = json['category'] as Map<String, dynamic>?;
    return Place(
      id: json['id'] as int,
      tripId: json['trip_id'] as int,
      name: json['name'] as String,
      category: categoryJson != null
          ? PlaceCategoryRef.fromCacheJson(categoryJson)
          : null,
      price: (json['price'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      notes: json['notes'] as String?,
    );
  }
}
