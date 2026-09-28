import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/notification_preferences/notification_preferences_local_store.dart';
import 'package:trek/notification_preferences/notification_preferences_models.dart';

import 'notification_preferences_fixtures.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  CachedNotificationPreferences sample() => CachedNotificationPreferences(
    serverMatrix: NotificationPreferencesMatrix.fromJson(matrixJson()),
    fetchedAt: DateTime.utc(2026, 9, 28, 9),
    pending: {
      'trip_invite': {'email': false},
    },
  );

  test('writes and reads back a snapshot, pending cells included', () async {
    final store = PreferencesNotificationPreferencesLocalStore();
    await store.write('a', sample());

    final read = await store.read('a');

    expect(read!.fetchedAt, DateTime.utc(2026, 9, 28, 9));
    expect(read.pending, {
      'trip_invite': {'email': false},
    });
    expect(read.matrix.visibleChannels, hasLength(4));
  });

  test('scopes are independent', () async {
    final store = PreferencesNotificationPreferencesLocalStore();
    await store.write('a', sample());

    expect(await store.read('b'), isNull);
  });

  test('a corrupt entry reads as a cache miss', () async {
    await SharedPreferencesAsync().setString(
      'trek.notificationPreferences.a',
      '{"matrix": 12',
    );

    expect(
      await PreferencesNotificationPreferencesLocalStore().read('a'),
      isNull,
    );
  });
}
