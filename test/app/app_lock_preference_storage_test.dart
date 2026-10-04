import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trek/app/app_lock_preference_storage.dart';

/// A [SharedPreferencesAsync] whose reads always throw — simulates a
/// corrupted or unreadable preferences file.
class _ThrowingPreferences implements SharedPreferencesAsync {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('simulated preferences failure'));
}

void main() {
  late InMemorySharedPreferencesAsync backend;

  setUp(() {
    backend = InMemorySharedPreferencesAsync.empty();
    SharedPreferencesAsyncPlatform.instance = backend;
  });

  test('defaults to enabled when nothing has been stored', () async {
    final storage = PreferencesAppLockPreferenceStorage();

    expect(await storage.readEnabled(), isTrue);
  });

  test('round-trips an explicit choice', () async {
    final storage = PreferencesAppLockPreferenceStorage();

    await storage.writeEnabled(false);
    expect(await storage.readEnabled(), isFalse);

    await storage.writeEnabled(true);
    expect(await storage.readEnabled(), isTrue);
  });

  test('persists across storage instances (app restarts)', () async {
    await PreferencesAppLockPreferenceStorage().writeEnabled(false);

    expect(await PreferencesAppLockPreferenceStorage().readEnabled(), isFalse);
  });

  test('fails closed (enabled) when the read throws', () async {
    final storage = PreferencesAppLockPreferenceStorage(
      preferences: _ThrowingPreferences(),
    );

    expect(await storage.readEnabled(), isTrue);
  });

  test('surfaces write failures to the caller', () async {
    final storage = PreferencesAppLockPreferenceStorage(
      preferences: _ThrowingPreferences(),
    );

    expect(storage.writeEnabled(false), throwsStateError);
  });
}
