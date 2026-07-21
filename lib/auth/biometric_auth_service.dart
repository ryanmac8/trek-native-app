import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Gates re-entry to an already-authenticated session behind Face ID/
/// Touch ID/Android biometrics — see [BiometricLockScreen]. This does not
/// replace Trek's own login; it only unlocks local access to a session
/// token that's already stored (see [AuthService]).
abstract class BiometricAuthService {
  /// Whether the device has biometrics enrolled and supports the
  /// authentication prompt. `false` means "skip the lock screen" — never
  /// treated as an error, the same way [WifiNetworkInfo] degrades to the
  /// public server URL when it can't read the SSID.
  Future<bool> isAvailable();

  /// Prompts for biometric authentication. Returns `false` (never throws)
  /// on cancellation, failure, or any platform error — callers only need
  /// to branch on the boolean.
  Future<bool> authenticate();
}

class DeviceBiometricAuthService implements BiometricAuthService {
  DeviceBiometricAuthService({LocalAuthentication? localAuth})
    : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  Future<bool> isAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final deviceSupported = await _localAuth.isDeviceSupported();
      debugPrint(
        'BiometricAuthService.isAvailable: canCheckBiometrics=$canCheck, '
        'isDeviceSupported=$deviceSupported',
      );
      return canCheck && deviceSupported;
    } catch (error) {
      debugPrint('BiometricAuthService.isAvailable failed: $error');
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      final result = await _localAuth.authenticate(
        localizedReason: 'Unlock Trek',
        // false (the default) lets the OS offer device passcode/PIN/pattern
        // as a fallback within the same native prompt if biometrics fail —
        // `biometricOnly: true` would suppress that fallback entirely.
        // Retry automatically on foregrounding instead of failing outright
        // if the OS interrupts the prompt by backgrounding the app.
        persistAcrossBackgrounding: true,
      );
      debugPrint('BiometricAuthService.authenticate result: $result');
      return result;
    } catch (error) {
      debugPrint('BiometricAuthService.authenticate failed: $error');
      return false;
    }
  }
}
