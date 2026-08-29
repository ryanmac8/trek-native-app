import 'package:flutter_test/flutter_test.dart';
import 'package:trek/notifications/trek_notification.dart';

void main() {
  group('TrekNotification.fromJson', () {
    test('parses a wire row with JSON-string params and integer is_read', () {
      final notification = TrekNotification.fromJson({
        'id': 12,
        'type': 'navigate',
        'title_key': 'notif.trip_invite.title',
        'title_params': '{"actor":"Sam","trip":"New Zealand"}',
        'text_key': 'notif.trip_invite.text',
        'text_params': '{"actor":"Sam","trip":"New Zealand"}',
        'navigate_target': '/trips/20',
        'is_read': 0,
        'created_at': '2026-08-29T10:00:00.000Z',
        'sender_username': 'sam',
        'sender_avatar': null,
      });

      expect(notification.id, 12);
      expect(notification.type, 'navigate');
      expect(notification.titleParams['actor'], 'Sam');
      expect(notification.textParams['trip'], 'New Zealand');
      expect(notification.navigateTarget, '/trips/20');
      expect(notification.isRead, isFalse);
      expect(notification.senderUsername, 'sam');
    });

    test('tolerates params already decoded to a map', () {
      final notification = TrekNotification.fromJson({
        'id': 1,
        'type': 'simple',
        'title_key': 'notif.generic.title',
        'title_params': {'count': 3},
        'text_key': 'notif.generic.text',
        'text_params': const <String, dynamic>{},
        'is_read': true,
      });

      expect(notification.titleParams['count'], '3');
      expect(notification.textParams, isEmpty);
      expect(notification.isRead, isTrue);
    });

    test('treats is_read 1 / "1" / "true" as read, everything else unread', () {
      TrekNotification withRead(Object? value) => TrekNotification.fromJson({
        'id': 1,
        'type': 'simple',
        'title_key': 'k',
        'text_key': 'k',
        'is_read': value,
      });

      expect(withRead(1).isRead, isTrue);
      expect(withRead('1').isRead, isTrue);
      expect(withRead('true').isRead, isTrue);
      expect(withRead(0).isRead, isFalse);
      expect(withRead(null).isRead, isFalse);
    });

    test('falls back to generic keys when the row omits them', () {
      final notification = TrekNotification.fromJson({'id': 5, 'is_read': 0});

      expect(notification.titleKey, 'notif.generic.title');
      expect(notification.textKey, 'notif.generic.text');
      expect(notification.type, 'simple');
    });

    test('a malformed params string degrades to empty, not a throw', () {
      final notification = TrekNotification.fromJson({
        'id': 1,
        'type': 'simple',
        'title_key': 'k',
        'title_params': 'not json',
        'text_key': 'k',
        'is_read': 0,
      });

      expect(notification.titleParams, isEmpty);
    });
  });

  group('cache round-trip', () {
    test('toCacheJson -> fromCacheJson preserves every modelled field', () {
      const original = TrekNotification(
        id: 7,
        type: 'navigate',
        titleKey: 'notif.collab_message.title',
        titleParams: {'actor': 'Jo'},
        textKey: 'notif.collab_message.text',
        textParams: {'actor': 'Jo', 'trip': 'Kyoto'},
        navigateTarget: '/trips/9',
        isRead: true,
        createdAt: '2026-08-29T09:00:00.000Z',
        senderUsername: 'jo',
        senderAvatar: 'https://example.com/a.png',
      );

      final restored = TrekNotification.fromCacheJson(original.toCacheJson());

      expect(restored.id, original.id);
      expect(restored.type, original.type);
      expect(restored.titleParams, original.titleParams);
      expect(restored.textParams, original.textParams);
      expect(restored.navigateTarget, original.navigateTarget);
      expect(restored.isRead, isTrue);
      expect(restored.createdAt, original.createdAt);
      expect(restored.senderAvatar, original.senderAvatar);
    });
  });

  test('copyWith only overrides isRead', () {
    const notification = TrekNotification(
      id: 1,
      type: 'simple',
      titleKey: 'k',
      textKey: 'k',
    );

    final read = notification.copyWith(isRead: true);

    expect(read.isRead, isTrue);
    expect(read.id, 1);
    expect(notification.isRead, isFalse);
  });
}
