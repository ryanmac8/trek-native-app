import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the first-run welcome screens have been shown, so the
/// router can send a fresh install to `/welcome` exactly once.
///
/// Implementations must never throw: the welcome screens are optional, so a
/// storage failure has to degrade to "skip them" rather than block the user
/// from reaching server setup.
abstract class OnboardingStorage {
  Future<bool> hasSeenWelcome();
  Future<void> markWelcomeSeen();
}

/// Stores the flag in plain local storage (`shared_preferences`) — it's a
/// device-local UI preference, never synced to the Trek server.
class PreferencesOnboardingStorage implements OnboardingStorage {
  PreferencesOnboardingStorage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _welcomeSeenKey = 'trek.onboarding.welcome_seen';

  final SharedPreferencesAsync _preferences;

  // Set as soon as the welcome is dismissed, before the write is attempted,
  // so a failed write can't bounce the user back to `/welcome` for the
  // rest of this session.
  bool _seenThisSession = false;

  @override
  Future<bool> hasSeenWelcome() async {
    if (_seenThisSession) return true;
    try {
      return await _preferences.getBool(_welcomeSeenKey) ?? false;
    } catch (error) {
      debugPrint('OnboardingStorage: read failed, skipping welcome: $error');
      return true;
    }
  }

  @override
  Future<void> markWelcomeSeen() async {
    _seenThisSession = true;
    try {
      await _preferences.setBool(_welcomeSeenKey, true);
    } catch (error) {
      debugPrint('OnboardingStorage: write failed: $error');
    }
  }
}
