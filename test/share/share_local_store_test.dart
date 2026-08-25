import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/share/share_link.dart';
import 'package:trek/share/share_local_store.dart';

void main() {
  group('PreferencesShareLocalStore', () {
    late InMemorySharedPreferencesAsync backend;
    late PreferencesShareLocalStore store;

    setUp(() {
      backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      store = PreferencesShareLocalStore();
    });

    test('read() returns null when nothing has been cached', () async {
      expect(await store.read('20'), isNull);
    });

    test("write() then read() round-trips a trip's share link", () async {
      const link = ShareLink(
        tripId: '20',
        token: 'abc123',
        shareBudget: true,
        shareCollab: true,
      );

      await store.write('20', link);
      final result = await store.read('20');

      expect(result?.token, 'abc123');
      expect(result?.shareBudget, isTrue);
      expect(result?.shareCollab, isTrue);
    });

    test('write(tripId, null) clears the cache for that trip', () async {
      await store.write('20', const ShareLink(tripId: '20', token: 'abc123'));

      await store.write('20', null);

      expect(await store.read('20'), isNull);
    });

    test(
      'write() overwrites what was previously cached for that trip',
      () async {
        await store.write('20', const ShareLink(tripId: '20', token: 'a'));
        await store.write('20', const ShareLink(tripId: '20', token: 'b'));

        expect((await store.read('20'))?.token, 'b');
      },
    );

    test('caches for different trips are independent', () async {
      await store.write('20', const ShareLink(tripId: '20', token: 'a'));
      await store.write('21', const ShareLink(tripId: '21', token: 'b'));

      expect((await store.read('20'))?.token, 'a');
      expect((await store.read('21'))?.token, 'b');
    });

    test(
      'a pending (offline-enabled) link round-trips with a null token',
      () async {
        const link = ShareLink(tripId: '20', needsSync: true);

        await store.write('20', link);
        final result = await store.read('20');

        expect(result?.token, isNull);
        expect(result?.needsSync, isTrue);
      },
    );
  });
}
