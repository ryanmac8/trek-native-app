import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:trek/permissions/app_permission.dart';
import 'package:trek/permissions/priming_storage.dart';

/// Backend whose every call throws — simulates a broken preferences store.
final class _ThrowingPreferences extends InMemorySharedPreferencesAsync {
  _ThrowingPreferences() : super.empty();

  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) =>
      throw PlatformException(code: 'boom');

  @override
  Future<bool> setInt(
    String key,
    int value,
    SharedPreferencesOptions options,
  ) => throw PlatformException(code: 'boom');

  @override
  Future<bool> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) => throw PlatformException(code: 'boom');
}

void main() {
  group('PreferencesPrimingStorage', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('nothing recorded reads as null', () async {
      expect(
        await PreferencesPrimingStorage().declinedAt(AppPermission.location),
        isNull,
      );
    });

    test('round-trips a decline time and clears it', () async {
      final storage = PreferencesPrimingStorage();
      final at = DateTime.utc(2026, 10, 11, 9, 30);

      await storage.recordDecline(AppPermission.location, at);
      expect(
        await PreferencesPrimingStorage().declinedAt(AppPermission.location),
        at,
      );

      await storage.clearDecline(AppPermission.location);
      expect(await storage.declinedAt(AppPermission.location), isNull);
    });

    test('storage failures never throw', () async {
      SharedPreferencesAsyncPlatform.instance = _ThrowingPreferences();
      final storage = PreferencesPrimingStorage();

      expect(await storage.declinedAt(AppPermission.location), isNull);
      await storage.recordDecline(AppPermission.location, DateTime.now());
      await storage.clearDecline(AppPermission.location);
    });
  });
}
