import 'package:flutter/foundation.dart';

/// In-memory (deliberately not persisted) biometric app-lock state for the
/// current run. [biometricsAvailable] is checked once at startup (see
/// `TrekApp._initialize`) and cached here rather than re-checked on every
/// navigation, since device capability doesn't change mid-run. [isUnlocked]
/// resets to `false` every cold start — set `true` by a successful
/// biometric prompt ([BiometricLockScreen]) or by a fresh password login
/// (which already proved identity, so an immediate second biometric prompt
/// would be redundant).
class AppLockState {
  bool biometricsAvailable = false;
  final ValueNotifier<bool> isUnlocked = ValueNotifier(false);
}
