import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/notifications/notifications_local_store.dart';
import 'package:trek/notifications/trek_notification.dart';

void main() {
  group('PreferencesNotificationsLocalStore', () {
    late InMemorySharedPreferencesAsync backend;
    late PreferencesNotificationsLocalStore store;

    setUp(() {
      backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      store = PreferencesNotificationsLocalStore();
    });

    TrekNotification notification(int id, {bool isRead = false}) =>
        TrekNotification(
          id: id,
          type: 'simple',
          titleKey: 'notif.generic.title',
          textKey: 'notif.generic.text',
          isRead: isRead,
        );

    test('readNotifications() is empty before anything is cached', () async {
      expect(await store.readNotifications(), isEmpty);
    });

    test('writeNotifications() then readNotifications() round-trips', () async {
      await store.writeNotifications([
        notification(1),
        notification(2, isRead: true),
      ]);

      final restored = await store.readNotifications();

      expect(restored.map((n) => n.id), [1, 2]);
      expect(restored[1].isRead, isTrue);
    });

    test('writeNotifications() overwrites the previous list', () async {
      await store.writeNotifications([notification(1)]);
      await store.writeNotifications([notification(9)]);

      expect((await store.readNotifications()).single.id, 9);
    });

    test('pending reads round-trip as a set of ids', () async {
      expect(await store.readPendingReads(), isEmpty);

      await store.writePendingReads({3, 7, 12});

      expect(await store.readPendingReads(), {3, 7, 12});
    });
  });
}
