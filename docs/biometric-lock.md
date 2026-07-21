# Biometric App Lock

[Issue #26](https://github.com/ryanmac8/trek-native-app/issues/26): Face ID / Touch ID / Android biometric unlock, gating re-entry to an already-authenticated session. This does not replace Trek's server-side login — it only decides whether the *local device* lets you back into an app that already has a valid session token stored.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/auth/biometric_auth_service.dart](../lib/auth/biometric_auth_service.dart) | `BiometricAuthService` interface + `DeviceBiometricAuthService`, wrapping [`local_auth`](https://pub.dev/packages/local_auth). `isAvailable()` checks the device has biometrics enrolled and supports the prompt; `authenticate()` shows it. Neither ever throws — both degrade to `false` on any platform error, the same pattern `WifiNetworkInfo` uses. |
| [lib/app/app_lock_state.dart](../lib/app/app_lock_state.dart) | `AppLockState` — `biometricsAvailable` (checked once at startup, cached) and `isUnlocked` (a `ValueNotifier<bool>`, in-memory only). |
| [lib/features/auth/biometric_lock_screen.dart](../lib/features/auth/biometric_lock_screen.dart) | `BiometricLockScreen` — the `/lock` route. Prompts automatically on appearance; on success sets `AppLockState.isUnlocked`, which the router picks up via `refreshListenable` on its own. On failure, offers "Try again" or "Log out instead". |

## How gating works

`AppLockState.biometricsAvailable` is checked once in `TrekApp._initialize()` (alongside `AuthService.restoreSession()`) and cached for the run — device capability doesn't change mid-session, so there's no reason to re-check it on every navigation the way the router's other redirect conditions are (local, but cheap) reads. See [app-shell.md](app-shell.md#navigation) for the full redirect order.

`AppLockState.isUnlocked` starts `false` every cold start — deliberately not persisted, so opening the app fresh always requires unlocking again if biometrics are available. It's set `true` by:
- A successful biometric prompt (`BiometricLockScreen`).
- A fresh password or MFA login (`LoginScreen`/`MfaScreen`) — typing a password or code already proves identity, so an immediate biometric prompt right after would be redundant.

There's no re-lock on backgrounding/resuming in this first version — only cold start. A `WidgetsBindingObserver`-based re-lock-on-resume is a reasonable future enhancement, not built here because it has real edge cases (Face ID timeouts, app-switcher screenshot exposure windows) that deserve their own design pass rather than being bolted on speculatively.

## Platform setup

- **iOS**: `NSFaceIDUsageDescription` in `ios/Runner/Info.plist` (required by Apple — the app is rejected without it).
- **Android**: `MainActivity` extends `FlutterFragmentActivity`, not `FlutterActivity` — Android's `BiometricPrompt` requires a `FragmentActivity` host. `android.permission.USE_BIOMETRIC` is declared in `AndroidManifest.xml`.

## What this doesn't do

- Doesn't add a fallback local PIN/passcode — "Log out instead" (a full password re-login) is the only fallback if biometrics fail or aren't set up.
- Doesn't let the user opt out once biometrics are available on their device — there's no settings screen yet ([#27](https://github.com/ryanmac8/trek-native-app/issues/27)) to add a toggle to.
