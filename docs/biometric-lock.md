# Biometric App Lock

[Issue #26](https://github.com/ryanmac8/trek-native-app/issues/26): Face ID / Touch ID / Android biometric unlock, gating re-entry to an already-authenticated session. This does not replace Trek's server-side login — it only decides whether the *local device* lets you back into an app that already has a valid session token stored.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/auth/biometric_auth_service.dart](../lib/auth/biometric_auth_service.dart) | `BiometricAuthService` interface + `DeviceBiometricAuthService`, wrapping [`local_auth`](https://pub.dev/packages/local_auth). `isAvailable()` checks the device has biometrics enrolled and supports the prompt; `authenticate()` shows it. Neither ever throws — both degrade to `false` on any platform error, the same pattern `WifiNetworkInfo` uses. |
| [lib/app/app_lock_state.dart](../lib/app/app_lock_state.dart) | `AppLockState` — `biometricsAvailable` (checked once at startup, cached), `lockEnabled` (the user's persisted on/off choice, a `ValueNotifier<bool>`), `isUnlocked` (a `ValueNotifier<bool>`, in-memory only), and the derived `needsUnlock` the router checks. |
| [lib/app/app_lock_preference_storage.dart](../lib/app/app_lock_preference_storage.dart) | `AppLockPreferenceStorage` + `PreferencesAppLockPreferenceStorage` — persists the on/off choice in `shared_preferences` under `trek.app_lock.enabled`. |
| [lib/features/settings/settings_screen.dart](../lib/features/settings/settings_screen.dart) | The "App lock" switch on the Settings hub — see [Turning app lock on and off](#turning-app-lock-on-and-off). |
| [lib/features/auth/biometric_lock_screen.dart](../lib/features/auth/biometric_lock_screen.dart) | `BiometricLockScreen` — the `/lock` route. Prompts automatically on appearance; on success sets `AppLockState.isUnlocked`, which the router picks up via `refreshListenable` on its own. On failure, offers "Try again" or "Log out instead". |

## How gating works

The router sends an authenticated user to `/lock` when `AppLockState.needsUnlock` is true: biometrics are available, `lockEnabled` is on, and `isUnlocked` is still false.

`AppLockState.biometricsAvailable` is checked once in `TrekApp._initialize()` (alongside `AuthService.restoreSession()`) and cached for the run — device capability doesn't change mid-session, so there's no reason to re-check it on every navigation the way the router's other redirect conditions are (local, but cheap) reads. See [app-shell.md](app-shell.md#navigation) for the full redirect order.

`AppLockState.isUnlocked` starts `false` every cold start — deliberately not persisted, so opening the app fresh always requires unlocking again if biometrics are available. It's set `true` by:
- A successful biometric prompt (`BiometricLockScreen`).
- A fresh password or MFA login (`LoginScreen`/`MfaScreen`) — typing a password or code already proves identity, so an immediate biometric prompt right after would be redundant.

There's no re-lock on backgrounding/resuming in this first version — only cold start. A `WidgetsBindingObserver`-based re-lock-on-resume is a reasonable future enhancement, not built here because it has real edge cases (Face ID timeouts, app-switcher screenshot exposure windows) that deserve their own design pass rather than being bolted on speculatively.

## Turning app lock on and off

App lock is on by default whenever the device has biometrics set up. The Settings hub's "App lock" switch changes that:

- **Off** — writes `false` to `AppLockPreferenceStorage` and sets `lockEnabled` to `false`. No prompt; the user is already inside the app.
- **On** — first shows the biometric prompt (`BiometricAuthService.authenticate()`). Only on success is `true` written and `lockEnabled` set, and `isUnlocked` is set `true` at the same time so the router doesn't bounce the user to `/lock` straight away. A failed or cancelled prompt leaves app lock off, which avoids turning on a lock the user can't then get past.
- If the write fails, `lockEnabled` keeps its previous value and an error snackbar is shown, so the switch always matches what's persisted.
- On a device without biometrics, the switch is shown off and disabled.

The preference is purely local and per-device. Trek's server has no equivalent setting, so it never touches the network and works offline. `TrekApp._initialize()` reads it at startup next to the biometrics check. `readEnabled()` never throws: if nothing is stored, or the read fails, it returns `true`, so an unreadable preference keeps the app locked rather than dropping the lock. The router's `refreshListenable` includes `lockEnabled`, so a change takes effect at once.

## Platform setup

- **iOS**: `NSFaceIDUsageDescription` in `ios/Runner/Info.plist` (required by Apple — the app is rejected without it).
- **Android**: `MainActivity` extends `FlutterFragmentActivity`, not `FlutterActivity` — Android's `BiometricPrompt` requires a `FragmentActivity` host. `android.permission.USE_BIOMETRIC` is declared in `AndroidManifest.xml`.

## Passcode fallback

`authenticate()` leaves `biometricOnly` at its default (`false`), so the OS offers the device's own passcode/PIN/pattern as a fallback within the same native prompt if biometrics fail or aren't set up — this is `local_auth`'s built-in behavior, not something built here. "Log out instead" (a full password re-login) is a separate, further fallback for when the user doesn't want to or can't use the device passcode either (e.g. switching accounts on a shared device).
