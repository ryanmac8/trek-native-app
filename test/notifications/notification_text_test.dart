import 'package:flutter_test/flutter_test.dart';
import 'package:trek/notifications/notification_text.dart';

void main() {
  group('renderNotificationText', () {
    test('substitutes every {placeholder} occurrence', () {
      final text = renderNotificationText('notif.trip_invite.text', {
        'actor': 'Sam',
        'trip': 'New Zealand',
      });

      expect(text, 'Sam invited you to New Zealand');
    });

    test('returns the key itself when it is unknown', () {
      expect(
        renderNotificationText('notif.something.unheard_of', const {}),
        'notif.something.unheard_of',
      );
    });

    test('leaves a placeholder untouched when no param matches it', () {
      final text = renderNotificationText('notif.trip_invite.text', {
        'actor': 'Sam',
      });

      expect(text, 'Sam invited you to {trip}');
    });
  });

  group('relativeTimeLabel', () {
    final now = DateTime.utc(2026, 8, 29, 12, 0, 0);

    test('"just now" under a minute', () {
      expect(
        relativeTimeLabel('2026-08-29T11:59:30.000Z', now: now),
        'just now',
      );
    });

    test('minutes, then hours, then days', () {
      expect(relativeTimeLabel('2026-08-29T11:45:00.000Z', now: now), '15m');
      expect(relativeTimeLabel('2026-08-29T09:00:00.000Z', now: now), '3h');
      expect(relativeTimeLabel('2026-08-25T12:00:00.000Z', now: now), '4d');
    });

    test('null for a missing or unparseable timestamp', () {
      expect(relativeTimeLabel(null, now: now), isNull);
      expect(relativeTimeLabel('whenever', now: now), isNull);
    });
  });
}
