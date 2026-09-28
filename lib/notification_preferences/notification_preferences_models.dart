/// One column of Trek's notification preferences matrix — a delivery
/// channel (`ChannelDescriptor` in Trek's
/// `server/src/nest/notifications/notification-events.ts`).
///
/// Built-in channels (`inapp`, `email`, `webhook`, `ntfy`) carry an i18n
/// [labelKey]; plugin channels (`plugin:<id>`) carry a literal [label].
class NotificationChannel {
  const NotificationChannel({
    required this.id,
    required this.source,
    required this.active,
    required this.configured,
    this.labelKey,
    this.label,
    this.settingsPath,
  });

  factory NotificationChannel.fromJson(Map<String, dynamic> json) {
    return NotificationChannel(
      id: json['id'] as String,
      source: json['source'] as String? ?? 'builtin',
      active: json['active'] as bool? ?? false,
      configured: json['configured'] as bool? ?? false,
      labelKey: json['labelKey'] as String?,
      label: json['label'] as String?,
      settingsPath: json['settingsPath'] as String?,
    );
  }

  /// `inapp`, `email`, `webhook`, `ntfy`, or `plugin:<id>`.
  final String id;

  /// `builtin` or `plugin`.
  final String source;

  /// Whether the server admin has switched this channel on. Inactive
  /// channels are not shown.
  final bool active;

  /// Whether the signed-in user has entered credentials for this channel
  /// (e.g. a webhook URL or ntfy topic). A preference for an unconfigured
  /// channel is stored but nothing is delivered over it.
  final bool configured;

  final String? labelKey;
  final String? label;
  final String? settingsPath;

  static const _builtinLabels = {
    'settings.notificationPreferences.inapp': 'In-App',
    'settings.notificationPreferences.email': 'Email',
    'settings.notificationPreferences.webhook': 'Webhook',
    'settings.notificationPreferences.ntfy': 'Ntfy',
  };

  /// Human-readable column name: the plugin's literal label, the English
  /// string for a built-in's [labelKey] (from Trek's
  /// `shared/src/i18n/en/settings.ts`), or the raw [id] as a fallback.
  String get displayLabel => label ?? _builtinLabels[labelKey] ?? id;

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'active': active,
    'configured': configured,
    if (labelKey != null) 'labelKey': labelKey,
    if (label != null) 'label': label,
    if (settingsPath != null) 'settingsPath': settingsPath,
  };
}

/// English labels for Trek's notification event types (`NotifEventType`),
/// from `shared/src/i18n/en/settings.ts`.
const _eventLabels = {
  'trip_invite': 'Trip invitations',
  'booking_change': 'Booking changes',
  'trip_reminder': 'Trip reminders',
  'todo_due': 'Todo due soon',
  'vacay_invite': 'Vacay fusion invitations',
  'vacay_share': 'Vacay calendar shares',
  'collection_invite': 'Collection invitations',
  'photos_shared': 'Shared photos (Immich)',
  'collab_message': 'Chat messages (Collab)',
  'packing_tagged': 'Packing list: assignments',
  'synology_session_cleared': 'Synology session cleared',
  'plugin_notification': 'Plugin notifications',
};

/// A readable label for a notification event type. Event types this app
/// doesn't know yet (added by a newer server) fall back to the key with
/// underscores replaced by spaces.
String notificationEventLabel(String eventType) {
  final known = _eventLabels[eventType];
  if (known != null) return known;
  final words = eventType.replaceAll('_', ' ');
  return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
}

/// `event type → channel id → enabled`.
typedef PreferenceCells = Map<String, Map<String, bool>>;

/// The user-scope notification preferences matrix from
/// `GET /api/notifications/preferences` (`PreferencesMatrix` in Trek's
/// `notification-preferences.service.ts`).
class NotificationPreferencesMatrix {
  const NotificationPreferencesMatrix({
    required this.preferences,
    required this.channels,
    required this.eventTypes,
    required this.implementedCombos,
  });

  factory NotificationPreferencesMatrix.fromJson(Map<String, dynamic> json) {
    return NotificationPreferencesMatrix(
      preferences: _decodeCells(json['preferences']),
      channels: [
        for (final c in json['channels'] as List<dynamic>? ?? const [])
          NotificationChannel.fromJson(c as Map<String, dynamic>),
      ],
      eventTypes: [
        for (final e in json['event_types'] as List<dynamic>? ?? const [])
          e as String,
      ],
      implementedCombos: {
        for (final entry
            in (json['implemented_combos'] as Map<String, dynamic>? ?? const {})
                .entries)
          entry.key: [
            for (final c in entry.value as List<dynamic>) c as String,
          ],
      },
    );
  }

  /// Every stored cell. The server fills in `true` for cells with no
  /// explicit opt-out row.
  final PreferenceCells preferences;

  /// Column descriptors, in display order (in-app first).
  final List<NotificationChannel> channels;

  /// The rows to show, in display order. Admin-only events are already
  /// excluded by the server for the user scope.
  final List<String> eventTypes;

  /// Which channels can deliver each event (`event type → channel ids`).
  final Map<String, List<String>> implementedCombos;

  /// A cell's value; a missing cell means enabled, matching the server's
  /// "no row = enabled" default.
  bool isEnabled(String eventType, String channelId) =>
      preferences[eventType]?[channelId] ?? true;

  /// Channels worth showing: active, and able to deliver at least one of
  /// [eventTypes] — the same filter Trek's web client applies.
  List<NotificationChannel> get visibleChannels => [
    for (final channel in channels)
      if (channel.active &&
          eventTypes.any(
            (e) => implementedCombos[e]?.contains(channel.id) ?? false,
          ))
        channel,
  ];

  /// The visible channels that can deliver [eventType], in column order.
  List<NotificationChannel> channelsFor(String eventType) {
    final implemented = implementedCombos[eventType] ?? const [];
    return [
      for (final channel in visibleChannels)
        if (implemented.contains(channel.id)) channel,
    ];
  }

  /// A copy with [overrides] applied on top of [preferences].
  NotificationPreferencesMatrix withCells(PreferenceCells overrides) {
    if (overrides.isEmpty) return this;
    final merged = copyCells(preferences);
    overrides.forEach((event, cells) {
      merged.putIfAbsent(event, () => {}).addAll(cells);
    });
    return NotificationPreferencesMatrix(
      preferences: merged,
      channels: channels,
      eventTypes: eventTypes,
      implementedCombos: implementedCombos,
    );
  }

  Map<String, dynamic> toJson() => {
    'preferences': preferences,
    'channels': [for (final c in channels) c.toJson()],
    'event_types': eventTypes,
    'implemented_combos': implementedCombos,
  };
}

PreferenceCells _decodeCells(Object? json) {
  if (json is! Map<String, dynamic>) return {};
  return {
    for (final entry in json.entries)
      if (entry.value is Map<String, dynamic>)
        entry.key: {
          for (final cell in (entry.value as Map<String, dynamic>).entries)
            if (cell.value is bool) cell.key: cell.value as bool,
        },
  };
}

/// A deep copy of [cells], safe to mutate.
PreferenceCells copyCells(PreferenceCells cells) => {
  for (final entry in cells.entries) entry.key: Map.of(entry.value),
};

/// Number of individual cells in [cells].
int countCells(PreferenceCells cells) =>
    cells.values.fold(0, (sum, row) => sum + row.length);

/// The locally cached preferences for one account: the last matrix the
/// server returned, when it was fetched, and the cells changed on this
/// device that the server hasn't confirmed yet.
class CachedNotificationPreferences {
  const CachedNotificationPreferences({
    required this.serverMatrix,
    required this.fetchedAt,
    this.pending = const {},
  });

  factory CachedNotificationPreferences.fromJson(Map<String, dynamic> json) {
    return CachedNotificationPreferences(
      serverMatrix: NotificationPreferencesMatrix.fromJson(
        json['matrix'] as Map<String, dynamic>,
      ),
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      pending: _decodeCells(json['pending']),
    );
  }

  /// The matrix as last confirmed by the server.
  final NotificationPreferencesMatrix serverMatrix;

  final DateTime fetchedAt;

  /// Unsynced local changes, coalesced per cell (the latest value wins).
  final PreferenceCells pending;

  /// What the screen shows: [serverMatrix] with [pending] applied.
  NotificationPreferencesMatrix get matrix => serverMatrix.withCells(pending);

  bool get hasPending => pending.isNotEmpty;

  int get pendingCount => countCells(pending);

  CachedNotificationPreferences copyWith({
    NotificationPreferencesMatrix? serverMatrix,
    DateTime? fetchedAt,
    PreferenceCells? pending,
  }) {
    return CachedNotificationPreferences(
      serverMatrix: serverMatrix ?? this.serverMatrix,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      pending: pending ?? this.pending,
    );
  }

  Map<String, dynamic> toJson() => {
    'matrix': serverMatrix.toJson(),
    'fetchedAt': fetchedAt.toIso8601String(),
    'pending': pending,
  };
}
