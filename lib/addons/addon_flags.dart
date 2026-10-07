/// Ids of Trek's server-side add-ons — the instance-wide feature flags an
/// admin switches on and off in Trek's admin panel. Mirrors `ADDON_IDS` in
/// Trek's `server/src/addons.ts`, plus `naver_list_import`, which is seeded
/// but not part of that constant.
abstract final class AddonIds {
  /// "Lists": gates both packing lists and todos.
  static const packing = 'packing';

  /// "Costs": the trip budget.
  static const budget = 'budget';
  static const documents = 'documents';
  static const vacay = 'vacay';
  static const atlas = 'atlas';
  static const collab = 'collab';
  static const journey = 'journey';
  static const roadtrip = 'roadtrip';
  static const collections = 'collections';
  static const mcp = 'mcp';
  static const airtrail = 'airtrail';
  static const dawarich = 'dawarich';
  static const llmParsing = 'llm_parsing';
  static const naverListImport = 'naver_list_import';

  /// Not a row of its own: the Trek web client treats "memories" as on
  /// whenever any photo provider is enabled.
  static const memories = 'memories';
}

/// One enabled entry from `GET /api/addons`. The server only lists enabled
/// add-ons, so [enabled] is effectively always `true` in practice.
///
/// [type] is `trip`, `global`, `integration`, or `photo_provider` (photo
/// providers such as Immich are listed only while the Journey add-on is on).
/// Photo-provider-only fields (`config`, `fields`) are not modeled.
class ServerAddon {
  const ServerAddon({
    required this.id,
    required this.name,
    required this.type,
    this.icon,
    this.enabled = true,
  });

  factory ServerAddon.fromJson(Map<String, dynamic> json) {
    return ServerAddon(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      type: json['type'] as String? ?? '',
      icon: json['icon'] as String?,
      enabled: json['enabled'] != false && json['enabled'] != 0,
    );
  }

  final String id;
  final String name;
  final String type;
  final String? icon;
  final bool enabled;

  static const photoProviderType = 'photo_provider';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'icon': icon,
    'enabled': enabled,
  };
}

/// The Collab add-on's sub-feature switches. On the server these are
/// opt-out (an absent setting means on), so a missing key parses as `true`.
class CollabFeatures {
  const CollabFeatures({
    this.chat = true,
    this.notes = true,
    this.links = true,
    this.polls = true,
    this.whatsnext = true,
  });

  factory CollabFeatures.fromJson(Map<String, dynamic>? json) {
    bool flag(String key) => json?[key] != false;
    return CollabFeatures(
      chat: flag('chat'),
      notes: flag('notes'),
      links: flag('links'),
      polls: flag('polls'),
      whatsnext: flag('whatsnext'),
    );
  }

  final bool chat;
  final bool notes;
  final bool links;
  final bool polls;
  final bool whatsnext;

  Map<String, dynamic> toJson() => {
    'chat': chat,
    'notes': notes,
    'links': links,
    'polls': polls,
    'whatsnext': whatsnext,
  };
}

/// The Trek instance's feature flags: which add-ons are enabled, the Collab
/// sub-features, and whether packing bag tracking is on. Parsed from the
/// `GET /api/addons` body, which has the same shape as [toJson].
class AddonFlags {
  const AddonFlags({
    required this.addons,
    this.collabFeatures = const CollabFeatures(),
    this.bagTracking = false,
  });

  factory AddonFlags.fromJson(Map<String, dynamic> json) {
    final rawAddons = json['addons'];
    final rawCollab = json['collabFeatures'];
    return AddonFlags(
      addons: [
        if (rawAddons is List)
          for (final entry in rawAddons)
            if (entry is Map<String, dynamic> && entry['id'] is String)
              ServerAddon.fromJson(entry),
      ],
      collabFeatures: CollabFeatures.fromJson(
        rawCollab is Map<String, dynamic> ? rawCollab : null,
      ),
      bagTracking: json['bagTracking'] == true,
    );
  }

  /// What a fresh Trek install has enabled (`seedAddons` in Trek's
  /// `server/src/db/seeds.ts`). Used until the app has fetched — or cached —
  /// the real instance's flags, so a first launch while offline shows the
  /// stock feature set rather than hiding everything.
  static const freshInstallDefaults = AddonFlags(
    addons: [
      ServerAddon(id: AddonIds.packing, name: 'Lists', type: 'trip'),
      ServerAddon(id: AddonIds.budget, name: 'Costs', type: 'trip'),
      ServerAddon(id: AddonIds.documents, name: 'Documents', type: 'trip'),
      ServerAddon(id: AddonIds.collab, name: 'Collab', type: 'trip'),
      ServerAddon(id: AddonIds.vacay, name: 'Vacay', type: 'global'),
      ServerAddon(id: AddonIds.atlas, name: 'Atlas', type: 'global'),
      ServerAddon(
        id: AddonIds.naverListImport,
        name: 'Naver List Import',
        type: 'integration',
      ),
    ],
  );

  final List<ServerAddon> addons;
  final CollabFeatures collabFeatures;
  final bool bagTracking;

  /// Whether the add-on [id] is enabled on this instance. [AddonIds.memories]
  /// is on when any photo provider is enabled, matching the web client.
  bool isEnabled(String id) {
    if (id == AddonIds.memories) {
      return addons.any(
        (a) => a.type == ServerAddon.photoProviderType && a.enabled,
      );
    }
    return addons.any((a) => a.id == id && a.enabled);
  }

  Map<String, dynamic> toJson() => {
    'addons': [for (final addon in addons) addon.toJson()],
    'collabFeatures': collabFeatures.toJson(),
    'bagTracking': bagTracking,
  };
}

/// [AddonFlags] plus when they were fetched from the server — the shape kept
/// in the local cache.
class CachedAddonFlags {
  const CachedAddonFlags({required this.flags, required this.fetchedAt});

  factory CachedAddonFlags.fromJson(Map<String, dynamic> json) {
    return CachedAddonFlags(
      flags: AddonFlags.fromJson(json['flags'] as Map<String, dynamic>),
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
    );
  }

  final AddonFlags flags;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => {
    'flags': flags.toJson(),
    'fetchedAt': fetchedAt.toIso8601String(),
  };
}
