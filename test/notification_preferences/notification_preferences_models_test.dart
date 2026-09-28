import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trek/notification_preferences/notification_preferences_models.dart';

import 'notification_preferences_fixtures.dart';

void main() {
  group('NotificationPreferencesMatrix.fromJson', () {
    test('parses preferences, channels, event types, and combos', () {
      final matrix = NotificationPreferencesMatrix.fromJson(
        matrixJson(
          preferences: {
            'trip_invite': {'email': false},
          },
        ),
      );

      expect(matrix.eventTypes, [
        'trip_invite',
        'booking_change',
        'collab_message',
        'synology_session_cleared',
      ]);
      expect(matrix.channels.map((c) => c.id), [
        'inapp',
        'email',
        'webhook',
        'ntfy',
        'plugin:matrix',
      ]);
      expect(matrix.isEnabled('trip_invite', 'email'), isFalse);
      expect(matrix.isEnabled('trip_invite', 'inapp'), isTrue);
      expect(matrix.implementedCombos['synology_session_cleared'], ['inapp']);
    });

    test('a missing cell defaults to enabled', () {
      final matrix = NotificationPreferencesMatrix.fromJson({
        'preferences': <String, dynamic>{},
        'channels': <dynamic>[],
        'event_types': ['trip_invite'],
        'implemented_combos': {
          'trip_invite': ['inapp'],
        },
      });
      expect(matrix.isEnabled('trip_invite', 'inapp'), isTrue);
    });
  });

  test('visibleChannels drops inactive channels', () {
    final matrix = NotificationPreferencesMatrix.fromJson(matrixJson());
    expect(matrix.visibleChannels.map((c) => c.id), [
      'inapp',
      'email',
      'webhook',
      'plugin:matrix',
    ]);
  });

  test('channelsFor only lists channels implemented for the event', () {
    final matrix = NotificationPreferencesMatrix.fromJson(matrixJson());
    expect(matrix.channelsFor('synology_session_cleared').map((c) => c.id), [
      'inapp',
    ]);
    expect(matrix.channelsFor('trip_invite'), hasLength(4));
  });

  test('withCells overlays changed cells without mutating the original', () {
    final matrix = NotificationPreferencesMatrix.fromJson(matrixJson());
    final changed = matrix.withCells({
      'collab_message': {'inapp': false},
    });
    expect(changed.isEnabled('collab_message', 'inapp'), isFalse);
    expect(matrix.isEnabled('collab_message', 'inapp'), isTrue);
  });

  group('NotificationChannel.displayLabel', () {
    test('uses the English string for a built-in label key', () {
      final matrix = NotificationPreferencesMatrix.fromJson(matrixJson());
      expect(matrix.channels.map((c) => c.displayLabel), [
        'In-App',
        'Email',
        'Webhook',
        'Ntfy',
        'Matrix chat',
      ]);
    });

    test('falls back to the channel id', () {
      const channel = NotificationChannel(
        id: 'plugin:x',
        source: 'plugin',
        active: true,
        configured: true,
      );
      expect(channel.displayLabel, 'plugin:x');
    });
  });

  test('notificationEventLabel names known and unknown events', () {
    expect(notificationEventLabel('trip_invite'), 'Trip invitations');
    expect(notificationEventLabel('collab_message'), 'Chat messages (Collab)');
    expect(notificationEventLabel('new_future_event'), 'New future event');
  });

  test('CachedNotificationPreferences round-trips through JSON', () {
    final cached = CachedNotificationPreferences(
      serverMatrix: NotificationPreferencesMatrix.fromJson(matrixJson()),
      fetchedAt: DateTime.utc(2026, 9, 28, 9),
      pending: {
        'trip_invite': {'webhook': false},
      },
    );

    final restored = CachedNotificationPreferences.fromJson(
      jsonDecode(jsonEncode(cached.toJson())) as Map<String, dynamic>,
    );

    expect(restored.fetchedAt, DateTime.utc(2026, 9, 28, 9));
    expect(restored.pendingCount, 1);
    expect(restored.serverMatrix.isEnabled('trip_invite', 'webhook'), isTrue);
    expect(restored.matrix.isEnabled('trip_invite', 'webhook'), isFalse);
    expect(restored.serverMatrix.channels.last.label, 'Matrix chat');
  });
}
