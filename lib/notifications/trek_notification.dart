import 'dart:convert';

/// A single in-app notification for the signed-in user, as returned by
/// `GET /api/notifications/in-app` (see [NotificationsApi]).
///
/// Confirmed against Trek's `notifications` table
/// (`server/src/db/schema.ts`) and `NotificationsService.listInApp`
/// (`server/src/nest/notifications/`): the row is `id`, `type`, `scope`,
/// `target`, `sender_id`, `recipient_id`, the `title_key` / `title_params`
/// and `text_key` / `text_params` pairs, the `positive_*` / `negative_*` /
/// `navigate_*` columns, `response`, `is_read`, and `created_at`, with the
/// sender's `username` / `avatar` joined in. The list is ordered by
/// `created_at` descending.
///
/// The server sends notification text **untranslated** — `*_key` is an
/// i18n key and `*_params` is that key's `{placeholder}` substitutions.
/// The client renders them; see `renderNotificationText` in
/// `notification_text.dart`. `title_params` / `text_params` arrive as JSON
/// strings (the column default is `'{}'`) but are tolerated as maps too,
/// matching Trek's own web client.
///
/// This first slice models only what the notifications list renders. The
/// boolean-response columns (`positive_text_key`, `negative_callback`, …),
/// `scope` / `target`, and the realtime delivery envelope are left out
/// until a screen needs them.
class TrekNotification {
  const TrekNotification({
    required this.id,
    required this.type,
    required this.titleKey,
    this.titleParams = const {},
    required this.textKey,
    this.textParams = const {},
    this.navigateTarget,
    this.isRead = false,
    this.createdAt,
    this.senderUsername,
    this.senderAvatar,
  });

  final int id;

  /// One of `simple`, `boolean`, `navigate` (a DB `CHECK` constraint).
  /// Only `navigate` carries a [navigateTarget]; this slice renders all
  /// three the same way and ignores the boolean yes/no actions.
  final String type;

  final String titleKey;
  final Map<String, String> titleParams;
  final String textKey;
  final Map<String, String> textParams;

  /// In-app route to open when a `navigate` notification is tapped (e.g.
  /// `/trips/42`). Null for `simple` / `boolean` notifications. Not acted
  /// on yet — the native routes it points at mostly don't exist.
  final String? navigateTarget;

  final bool isRead;

  /// UTC ISO-8601 timestamp string from the server. Kept as a string; the
  /// list parses it for display and tolerates an unparseable value.
  final String? createdAt;

  final String? senderUsername;
  final String? senderAvatar;

  TrekNotification copyWith({bool? isRead}) {
    return TrekNotification(
      id: id,
      type: type,
      titleKey: titleKey,
      titleParams: titleParams,
      textKey: textKey,
      textParams: textParams,
      navigateTarget: navigateTarget,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      senderUsername: senderUsername,
      senderAvatar: senderAvatar,
    );
  }

  /// Parses a `*_params` value that is either a JSON object string (the
  /// wire shape — the column stores JSON text) or an already-decoded map
  /// (tolerated for forward compatibility, as Trek's web client does).
  /// Values are coerced to strings so the renderer can substitute them.
  static Map<String, String> _params(Object? value) {
    Object? decoded = value;
    if (value is String) {
      if (value.trim().isEmpty) return const {};
      try {
        decoded = jsonDecode(value);
      } catch (_) {
        return const {};
      }
    }
    if (decoded is Map) {
      return decoded.map((key, v) => MapEntry('$key', '$v'));
    }
    return const {};
  }

  /// Accepts the SQLite-flavoured `is_read` (`0` / `1`), a real bool, or a
  /// numeric string.
  static bool _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return false;
  }

  static String? _string(Object? value) => value as String?;

  factory TrekNotification.fromJson(Map<String, dynamic> json) {
    return TrekNotification(
      id: json['id'] as int,
      type: json['type'] as String? ?? 'simple',
      titleKey: json['title_key'] as String? ?? 'notif.generic.title',
      titleParams: _params(json['title_params']),
      textKey: json['text_key'] as String? ?? 'notif.generic.text',
      textParams: _params(json['text_params']),
      navigateTarget: _string(json['navigate_target']),
      isRead: _bool(json['is_read']),
      createdAt: _string(json['created_at']),
      senderUsername: _string(json['sender_username']),
      senderAvatar: _string(json['sender_avatar']),
    );
  }

  /// Cache shape: the params are already-decoded maps and `is_read` is a
  /// real bool, so [fromJson]'s tolerant parsing round-trips this cleanly.
  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'type': type,
    'title_key': titleKey,
    'title_params': titleParams,
    'text_key': textKey,
    'text_params': textParams,
    'navigate_target': navigateTarget,
    'is_read': isRead,
    'created_at': createdAt,
    'sender_username': senderUsername,
    'sender_avatar': senderAvatar,
  };

  factory TrekNotification.fromCacheJson(Map<String, dynamic> json) =>
      TrekNotification.fromJson(json);
}
