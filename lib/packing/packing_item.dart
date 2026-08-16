/// A trip's packing-list item, as returned by
/// `GET /api/trips/:tripId/packing` / `POST /api/trips/:tripId/packing`,
/// plus the fields needed to track an offline-created item until it syncs
/// (see [PackingRepository] in `packing_repository.dart`).
///
/// The real response also carries three-tier sharing (`is_private`,
/// `owner_id`, `recipients`), bag assignment (`bag_id`, `weight_grams`),
/// `quantity`, and co-contributors — confirmed against Trek's actual
/// `packing_items` schema and `PackingController`/`packingService.ts`
/// (`server/src/nest/packing/`, `server/src/services/packingService.ts`).
/// This first slice of issue #8 only needs what the list row renders: name,
/// category, and checked state. Sharing, bags, quantity, and templates are
/// a follow-up once this exists to attach them to.
///
/// [id] is null exactly when the item was created locally while offline and
/// hasn't been confirmed by the server yet ([isPending]). [localId] is a
/// stable client-generated key that survives that transition — used to find
/// and replace the pending entry in the local cache once the create syncs,
/// mirrors [BudgetItem]'s pending-write shape.
class PackingItem {
  const PackingItem({
    this.id,
    required this.localId,
    required this.tripId,
    required this.name,
    this.category,
    this.checked = false,
  });

  final int? id;
  final String localId;
  final String tripId;
  final String name;
  final String? category;
  final bool checked;

  /// True for an item created locally that hasn't been confirmed by the
  /// server yet — either still queued (offline) or its create request is in
  /// flight. See [PackingRepository.createItem].
  bool get isPending => id == null;

  factory PackingItem.fromJson(
    Map<String, dynamic> json, {
    required String tripId,
  }) {
    final id = json['id'] as int;
    return PackingItem(
      id: id,
      localId: 'server-$id',
      tripId: tripId,
      name: json['name'] as String,
      category: json['category'] as String?,
      checked: _asBool(json['checked']),
    );
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return false;
  }

  /// Round-trips a [PackingItem] through the local cache (see
  /// `PreferencesPackingLocalStore`) — unlike [fromJson]/the real API shape,
  /// this must also carry [id] being absent (a still-pending item) and the
  /// client-generated [localId].
  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'local_id': localId,
    'trip_id': tripId,
    'name': name,
    'category': category,
    'checked': checked,
  };

  factory PackingItem.fromCacheJson(Map<String, dynamic> json) {
    return PackingItem(
      id: json['id'] as int?,
      localId: json['local_id'] as String,
      tripId: json['trip_id'] as String,
      name: json['name'] as String,
      category: json['category'] as String?,
      checked: json['checked'] as bool? ?? false,
    );
  }
}
