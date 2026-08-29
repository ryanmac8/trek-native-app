import 'trek_notification.dart';

/// Trek sends in-app notifications with i18n *keys*, not rendered text (see
/// [TrekNotification]). This is the English `notif.*` catalog, copied from
/// Trek's `shared/src/i18n/en/notif.ts`, plus the `{placeholder}`
/// substitution its web client applies. Only English is bundled for now —
/// the app has no locale system yet.
///
/// [renderNotificationText] mirrors the web client's fallback exactly: an
/// unknown key renders as the raw key string rather than throwing, so a
/// notification type the app doesn't know about still shows *something*.
const Map<String, String> notificationStrings = {
  'notif.test.title': '[Test] Notification',
  'notif.test.simple.text': 'This is a simple test notification.',
  'notif.test.boolean.text': 'Do you accept this test notification?',
  'notif.test.navigate.text': 'Click below to navigate to the dashboard.',
  'notif.trip_invite.title': 'Trip Invitation',
  'notif.trip_invite.text': '{actor} invited you to {trip}',
  'notif.booking_change.title': 'Booking Updated',
  'notif.booking_change.text': '{actor} updated a booking in {trip}',
  'notif.trip_reminder.title': 'Trip Reminder',
  'notif.trip_reminder.text': 'Your trip {trip} is coming up soon!',
  'notif.todo_due.title': 'To-do due',
  'notif.todo_due.text': '{todo} in {trip} is due on {due}',
  'notif.vacay_invite.title': 'Vacay Fusion Invite',
  'notif.vacay_invite.text': '{actor} invited you to fuse vacation plans',
  'notif.vacay_share.title': 'Vacay Calendar Shared',
  'notif.vacay_share.text': '{actor} shared their vacation calendar with you',
  'notif.collection_invite.title': 'Collection invite',
  'notif.collection_invite.text': '{actor} invited you to share a collection',
  'notif.photos_shared.title': 'Photos Shared',
  'notif.photos_shared.text': '{actor} shared {count} photo(s) in {trip}',
  'notif.collab_message.title': 'New Message',
  'notif.collab_message.text': '{actor} sent a message in {trip}',
  'notif.packing_tagged.title': 'Packing Assignment',
  'notif.packing_tagged.text': '{actor} assigned you to {category} in {trip}',
  'notif.version_available.title': 'New Version Available',
  'notif.version_available.text': 'TREK {version} is now available',
  'notif.replica_failure.title': 'Storage replica failure',
  'notif.replica_failure.text':
      "Replica write failed on '{backend}': {op} of {key} — {error}",
  'notif.replica_failure.textSuppressed':
      "Replica write failed on '{backend}': {op} of {key} — {error}. "
      '{suppressed} more failures were suppressed since the last '
      'notification.',
  'notif.action.view_trip': 'View Trip',
  'notif.action.view_collab': 'View Messages',
  'notif.action.view_packing': 'View Packing',
  'notif.action.view_photos': 'View Photos',
  'notif.action.view_vacay': 'View Vacay',
  'notif.action.view_collection': 'View Collection',
  'notif.action.view_admin': 'Go to Admin',
  'notif.action.view': 'View',
  'notif.action.accept': 'Accept',
  'notif.action.decline': 'Decline',
  'notif.plugin.title': '{title}',
  'notif.plugin.text': '{body}',
  'notif.generic.title': 'Notification',
  'notif.generic.text': 'You have a new notification',
  'notif.dev.unknown_event.title': '[DEV] Unknown Event',
  'notif.dev.unknown_event.text':
      'Event type "{event}" is not registered in EVENT_NOTIFICATION_CONFIG',
};

/// Resolves [key] against [notificationStrings] and substitutes every
/// `{name}` occurrence with `params['name']`. An unknown key returns the
/// key itself; a placeholder with no matching param is left untouched —
/// both match Trek's web `t()` behaviour.
String renderNotificationText(String key, Map<String, String> params) {
  final template = notificationStrings[key];
  if (template == null) return key;
  var text = template;
  params.forEach((name, value) {
    text = text.replaceAll('{$name}', value);
  });
  return text;
}

/// Title of [notification], rendered from its key + params.
String notificationTitle(TrekNotification notification) =>
    renderNotificationText(notification.titleKey, notification.titleParams);

/// Body of [notification], rendered from its key + params.
String notificationBody(TrekNotification notification) =>
    renderNotificationText(notification.textKey, notification.textParams);

/// Compact "3m" / "2h" / "5d" / "just now" relative-time label for the
/// notification list, matching the web client's format. [now] is injectable
/// for tests. Returns null when [iso] can't be parsed.
String? relativeTimeLabel(String? iso, {DateTime? now}) {
  if (iso == null) return null;
  final time = DateTime.tryParse(iso);
  if (time == null) return null;
  final elapsed = (now ?? DateTime.now()).difference(time);
  final minutes = elapsed.inMinutes;
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '${minutes}m';
  final hours = elapsed.inHours;
  if (hours < 24) return '${hours}h';
  return '${elapsed.inDays}d';
}
