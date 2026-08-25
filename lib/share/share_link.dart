/// A trip's public, read-only share link, as returned by
/// `GET`/`POST`/`DELETE /api/trips/:tripId/share-link`, plus the fields
/// needed to track an offline enable/update/disable until it syncs (see
/// [ShareRepository] in `share_repository.dart`).
///
/// Unlike the other trip-scoped resources in this app, there's at most one
/// [ShareLink] per trip rather than a list, so [ShareLocalStore] caches a
/// single nullable value: `null` means sharing is off (or has never been
/// touched) as far as the client knows.
///
/// [token] is null exactly when sharing has never been confirmed enabled by
/// the server — either it was just requested locally while offline
/// ([needsSync]) with no token assigned yet, or it's genuinely off. The five
/// `share*` flags mirror Trek's `share_tokens` columns — confirmed against
/// `server/src/nest/share/` and `server/src/services/shareService.ts` — and
/// gate which sections of the trip (map/itinerary, bookings, packing,
/// budget, collab chat) a visitor with the link can see.
///
/// [needsSync] marks an enable or permissions update not yet confirmed by
/// the server; [pendingDelete] marks a disable not yet confirmed. Both are
/// retried by [ShareRepository.refreshShareLink].
class ShareLink {
  const ShareLink({
    required this.tripId,
    this.token,
    this.createdAt,
    this.shareMap = true,
    this.shareBookings = true,
    this.sharePacking = false,
    this.shareBudget = false,
    this.shareCollab = false,
    this.needsSync = false,
    this.pendingDelete = false,
  });

  final String tripId;
  final String? token;
  final String? createdAt;
  final bool shareMap;
  final bool shareBookings;
  final bool sharePacking;
  final bool shareBudget;
  final bool shareCollab;
  final bool needsSync;
  final bool pendingDelete;

  /// True once sharing is (or is about to be, pending sync) visible to
  /// whoever holds the link — i.e. not disabled and not still awaiting its
  /// very first sync with no local intent recorded.
  bool get isEnabled => !pendingDelete && (token != null || needsSync);

  ShareLink copyWith({bool? needsSync, bool? pendingDelete}) {
    return ShareLink(
      tripId: tripId,
      token: token,
      createdAt: createdAt,
      shareMap: shareMap,
      shareBookings: shareBookings,
      sharePacking: sharePacking,
      shareBudget: shareBudget,
      shareCollab: shareCollab,
      needsSync: needsSync ?? this.needsSync,
      pendingDelete: pendingDelete ?? this.pendingDelete,
    );
  }

  /// Parses `GET /api/trips/:tripId/share-link`'s body — the only response
  /// that carries every field. [ShareApi.createOrUpdateShareLink]'s `POST`
  /// response only carries `token`, so it can't use this factory; see its
  /// doc comment.
  factory ShareLink.fromJson(
    Map<String, dynamic> json, {
    required String tripId,
  }) {
    return ShareLink(
      tripId: tripId,
      token: json['token'] as String?,
      createdAt: json['created_at'] as String?,
      shareMap: _asBool(json['share_map'], defaultValue: true),
      shareBookings: _asBool(json['share_bookings'], defaultValue: true),
      sharePacking: _asBool(json['share_packing']),
      shareBudget: _asBool(json['share_budget']),
      shareCollab: _asBool(json['share_collab']),
    );
  }

  static bool _asBool(Object? value, {bool defaultValue = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return defaultValue;
  }

  /// Round-trips a [ShareLink] through the local cache (see
  /// `PreferencesShareLocalStore`) — unlike [fromJson], this must also carry
  /// [needsSync]/[pendingDelete].
  Map<String, dynamic> toCacheJson() => {
    'trip_id': tripId,
    'token': token,
    'created_at': createdAt,
    'share_map': shareMap,
    'share_bookings': shareBookings,
    'share_packing': sharePacking,
    'share_budget': shareBudget,
    'share_collab': shareCollab,
    'needs_sync': needsSync,
    'pending_delete': pendingDelete,
  };

  factory ShareLink.fromCacheJson(Map<String, dynamic> json) {
    return ShareLink(
      tripId: json['trip_id'] as String,
      token: json['token'] as String?,
      createdAt: json['created_at'] as String?,
      shareMap: json['share_map'] as bool? ?? true,
      shareBookings: json['share_bookings'] as bool? ?? true,
      sharePacking: json['share_packing'] as bool? ?? false,
      shareBudget: json['share_budget'] as bool? ?? false,
      shareCollab: json['share_collab'] as bool? ?? false,
      needsSync: json['needs_sync'] as bool? ?? false,
      pendingDelete: json['pending_delete'] as bool? ?? false,
    );
  }
}
