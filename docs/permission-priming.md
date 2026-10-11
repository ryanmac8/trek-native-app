# Permission Priming

Part of [issue #28](https://github.com/ryanmac8/trek-native-app/issues/28) (onboarding). Before the app triggers an OS permission prompt, it shows its own bottom sheet explaining what the permission is for. The system prompt only appears after the user taps "Continue". iOS shows its prompt only once per permission, and Android stops showing it after the user picks "Don't ask again". Priming means that one chance is used only after the user has opted in.

## Pieces

All under [lib/permissions/](../lib/permissions/):

| File | Contents |
| --- | --- |
| `app_permission.dart` | `AppPermission` enum: each permission the app requests, plus its priming copy (icon, title, rationale, and the message shown when the permission is blocked) |
| `permission_gateway.dart` | `PermissionGateway` (status / request / open Settings) and `AppPermissionStatus` (`granted`, `denied`, `permanentlyDenied`, `restricted`). `DevicePermissionGateway` wraps `permission_handler` and maps its statuses, counting iOS `limited`/`provisional` as `granted`. Platform errors read as `denied` and are never thrown. |
| `priming_storage.dart` | `PrimingStorage` records when the user last tapped "Not now", per permission. `PreferencesPrimingStorage` keeps this in `shared_preferences` (`trek.permission_priming.<name>.declined_at`, epoch ms, UTC), and storage failures are swallowed. |
| `priming_sheet.dart` | `showPermissionPrimingSheet` ("Continue" / "Not now") and `showPermissionBlockedSheet` ("Open Settings" / "Not now", or just "OK" when the permission is restricted) |
| `permission_primer.dart` | `PermissionPrimer.ensure(context, permission, {userInitiated})` runs the flow below and returns a `PrimingOutcome` |

Providers in [lib/app/providers.dart](../lib/app/providers.dart): `permissionGatewayProvider`, `primingStorageProvider`, `permissionPrimerProvider`.

## Flow

`PermissionPrimer.ensure`:

| Current OS status | `userInitiated` | Result |
| --- | --- | --- |
| `granted` | any | No UI. Returns `granted`. |
| `permanentlyDenied` / `restricted` | `true` | Shows the blocked sheet. "Open Settings" opens the app's system Settings page. Returns `blocked`. |
| `permanentlyDenied` / `restricted` | `false` | No UI. Returns `blocked`. |
| `denied`, and "Not now" was tapped less than `cooldown` ago (default 14 days) | `false` | No UI. Returns `snoozed`. |
| `denied` | otherwise | Shows the priming sheet. "Continue" shows the OS prompt: `granted` clears the stored decline, a refusal returns `denied`, and "don't ask again" returns `blocked`. "Not now" or swiping the sheet away records the decline and returns `dismissed`, without spending the OS prompt. |

Pass `userInitiated: true` when the user has just turned on the feature that needs the permission. Pass `false` for prompts the app raises on its own, which are subject to the cooldown.

The flow is device-local and never touches the network or account data, so it behaves the same offline.

## Permissions

| `AppPermission` | OS permission | Platform declarations | Used by |
| --- | --- | --- | --- |
| `location` | `permission_handler` `locationWhenInUse` | iOS: `NSLocationWhenInUseUsageDescription` (`Info.plist`) + `PERMISSION_LOCATION_WHENINUSE=1` (`Podfile`). Android: `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION` (`AndroidManifest.xml`) | `ServerSetupScreen`. On "Continue" with both a private URL and at least one trusted Wi-Fi network, the config is saved first and then location is primed (`userInitiated: true`). If permission isn't granted, an info snackbar says the public URL will be used, and setup continues to login either way. |

Location is needed because both OSes reveal the current Wi-Fi SSID only to apps that hold location access, and `ServerConfigResolver` uses the SSID to pick the private server URL (see [networking-auth.md](networking-auth.md#server-configuration)). On iOS the SSID also requires the "Access WiFi Information" entitlement, which the Xcode project doesn't have yet. Until it's added, granting location on iOS still returns a `null` SSID.

`permission_handler` compiles out every iOS permission whose `PERMISSION_*` macro isn't set in the `Podfile`. When a permission is requested without its platform declarations, the OS reports it as denied. Adding an `AppPermission` value therefore always means adding its `Info.plist` key, `Podfile` macro, and Android `<uses-permission>` in the same change.
