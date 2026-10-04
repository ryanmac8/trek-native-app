import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the user wants the biometric app lock on. A purely
/// local, per-device preference — Trek's server has no notion of it.
abstract class AppLockPreferenceStorage {
  /// Whether app lock is enabled. Defaults to `true` when nothing has been
  /// stored yet, and also when the read fails — an unreadable preference
  /// fails closed (locked) rather than silently dropping the lock.
  Future<bool> readEnabled();

  /// Throws if the preference couldn't be written, so the caller can keep
  /// its UI in sync with what's actually persisted.
  Future<void> writeEnabled(bool enabled);
}

/// Stores the preference in plain local storage (`shared_preferences`) —
/// it isn't a secret, so it doesn't need `SecureTokenStorage`.
class PreferencesAppLockPreferenceStorage implements AppLockPreferenceStorage {
  PreferencesAppLockPreferenceStorage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const enabledKey = 'trek.app_lock.enabled';

  final SharedPreferencesAsync _preferences;

  @override
  Future<bool> readEnabled() async {
    try {
      return await _preferences.getBool(enabledKey) ?? true;
    } catch (error) {
      debugPrint('AppLockPreferenceStorage: read failed: $error');
      return true;
    }
  }

  @override
  Future<void> writeEnabled(bool enabled) =>
      _preferences.setBool(enabledKey, enabled);
}
