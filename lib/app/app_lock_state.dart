import 'package:flutter/foundation.dart';

/// Biometric app-lock state for the current run. [biometricsAvailable] is
/// checked once at startup (see `TrekApp._initialize`) and cached here
/// rather than re-checked on every navigation, since device capability
/// doesn't change mid-run. [lockEnabled] is the user's persisted
/// preference (see `AppLockPreferenceStorage`), loaded at startup and
/// updated live from Settings. [isUnlocked] is in-memory only and resets
/// to `false` every cold start — set `true` by a successful biometric
/// prompt ([BiometricLockScreen]) or by a fresh password login (which
/// already proved identity, so an immediate second biometric prompt would
/// be redundant).
class AppLockState {
  bool biometricsAvailable = false;
  final ValueNotifier<bool> lockEnabled = ValueNotifier(true);
  final ValueNotifier<bool> isUnlocked = ValueNotifier(false);

  /// Whether the router should send the user to `/lock` right now.
  bool get needsUnlock =>
      biometricsAvailable && lockEnabled.value && !isUnlocked.value;
}
