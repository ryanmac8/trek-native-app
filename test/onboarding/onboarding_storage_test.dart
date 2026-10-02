import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/onboarding/onboarding_storage.dart';

/// [SharedPreferencesAsync] whose every read and write throws — simulates
/// the platform store being unavailable.
class _ThrowingPreferences implements SharedPreferencesAsync {
  @override
  Future<bool?> getBool(String key) async =>
      throw StateError('simulated preferences failure');

  @override
  Future<void> setBool(String key, bool value) async =>
      throw StateError('simulated preferences failure');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('PreferencesOnboardingStorage', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('reports the welcome as unseen on a fresh install', () async {
      expect(await PreferencesOnboardingStorage().hasSeenWelcome(), isFalse);
    });

    test('persists the seen flag across instances', () async {
      await PreferencesOnboardingStorage().markWelcomeSeen();

      expect(await PreferencesOnboardingStorage().hasSeenWelcome(), isTrue);
    });

    test('treats a failed read as seen so the welcome never blocks', () async {
      final storage = PreferencesOnboardingStorage(
        preferences: _ThrowingPreferences(),
      );

      expect(await storage.hasSeenWelcome(), isTrue);
    });

    test('still reports seen for the session when the write fails', () async {
      final storage = PreferencesOnboardingStorage(
        preferences: _ThrowingPreferences(),
      );

      await storage.markWelcomeSeen();

      expect(await storage.hasSeenWelcome(), isTrue);
    });
  });
}
