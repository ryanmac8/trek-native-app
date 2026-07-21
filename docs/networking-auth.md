# Networking & Auth

Covers [issue #1](https://github.com/ryanmac8/trek-native-app/issues/1): the HTTP client, error handling, server config, token storage, the login/MFA/logout flow, and the authenticated `ApiClient` used for the rest of the API. No request/response models for the rest of the data model yet beyond `TripsApi`'s minimal read (see [app-shell.md](app-shell.md)).

## Pieces

| File | Purpose |
| --- | --- |
| [lib/config/server_config.dart](../lib/config/server_config.dart) | `ServerConfig` — the user's public and (optional) private server URLs, plus the Wi-Fi SSIDs that should use the private one. `ServerConfigStorage`/`PreferencesServerConfigStorage` persist it via `shared_preferences` (plain storage; not a secret). |
| [lib/config/wifi_network_info.dart](../lib/config/wifi_network_info.dart) | `WifiNetworkInfo` — the current Wi-Fi SSID, or `null` if unavailable. `DeviceWifiNetworkInfo` is the real implementation, backed by `network_info_plus`. |
| [lib/config/server_config_resolver.dart](../lib/config/server_config_resolver.dart) | `ServerConfigResolver.resolveBaseUrl()` — combines `ServerConfigStorage` and `WifiNetworkInfo` into the single base URL to use for the current network. |
| [lib/network/api_exception.dart](../lib/network/api_exception.dart) | Typed exceptions: `NetworkException`, `UnauthorizedException`, `ForbiddenException`, `ValidationException`, `ServerException` (with status code) — each optionally carries Trek's `code` field (e.g. `AUTH_REQUIRED`). |
| [lib/network/api_client.dart](../lib/network/api_client.dart) | Wraps `package:http`. Resolves paths against a base URL (fixed via `baseUrl`, or resolved per-request via `getBaseUrl`), JSON-encodes/decodes bodies, attaches a bearer token via an injected `getAccessToken` callback, and maps non-2xx responses to the exceptions above. |
| [lib/auth/session_token.dart](../lib/auth/session_token.dart) | `SessionToken` — Trek's single session JWT, decoding its `exp` claim client-side. |
| [lib/auth/token_storage.dart](../lib/auth/token_storage.dart) | `TokenStorage` interface + `SecureTokenStorage`, which persists the token in the iOS Keychain / Android Keystore via `flutter_secure_storage`. |
| [lib/auth/auth_service.dart](../lib/auth/auth_service.dart) | `login`, `verifyMfaLogin`, `logout`, `currentAccessToken` (expiry-aware, local-only check), `handleUnauthorized`, and the `isAuthenticated`/`needsReconnect` listenables. |
| [lib/features/auth/reconnect_screen.dart](../lib/features/auth/reconnect_screen.dart) | `ReconnectScreen` — the `/reconnect` route, re-running `login`/`verifyMfaLogin` in place when `needsReconnect` is set. |

## Server configuration

Trek is self-hosted — there is no fixed vendor-run API URL. `ServerConfig` holds a `publicUrl` (always reachable — a domain behind a reverse proxy, dynamic DNS, etc.) and a list of `privateEndpoints`, each a local-network address (e.g. `http://192.168.1.50:3000`) paired with the one Wi-Fi network name it should be used on — so e.g. separate home and office LAN addresses can coexist. `ServerConfig.validateUrl` validates and normalizes a user-entered address for the public URL or any endpoint's URL. `ServerConfig.resolveBaseUrl(currentSsid)` returns the URL of whichever private endpoint's Wi-Fi network matches `currentSsid`, otherwise the public URL. New endpoints are added from `NetworkingSettingsScreen`'s "Add endpoint" dialog, which pings the candidate URL's `/api/health` (`ServerHealthCheck`) before it's saved — advisory only, so a LAN address that's genuinely unreachable right now (e.g. added while away from home) can still be saved for later, via "Save anyway".

`ServerConfigResolver` wires this to the device: it reads the stored `ServerConfig`, asks `WifiNetworkInfo` for the current SSID, and returns the resolved URL — passed as `ApiClient`'s `getBaseUrl`, so the effective server address is re-evaluated on every request rather than fixed at app startup.

Reading a real Wi-Fi SSID requires OS permissions the app does not yet request (that's a UI concern, pending #2/#27):
- **Android:** `ACCESS_FINE_LOCATION` is declared in `AndroidManifest.xml`, but the runtime permission prompt isn't wired up yet.
- **iOS:** `NSLocationWhenInUseUsageDescription` is declared in `Info.plist`, but the app doesn't yet request location authorization, and the `com.apple.developer.networking.wifi-info` entitlement (Xcode's "Access WiFi Information" capability) hasn't been added to the Xcode project — that capability also requires a paid Apple Developer team, not a personal one.

Until those are in place, `WifiNetworkInfo.currentSsid()` returns `null` and `ServerConfigResolver` always falls back to the public URL — the private-URL feature degrades to a no-op rather than breaking anything.

## Auth contract

Trek issues a single JWT per session — `POST /api/auth/login` returns `{ token, user }`, and the JWT's own `exp` claim is the session lifetime. There is no refresh-token exchange for password logins: an expired or invalidated token means the user has to log in again.

If the account has TOTP enabled, `login()` returns `{ mfa_required: true, mfa_token }` instead of a session; `POST /api/auth/mfa/verify-login` exchanges the `mfa_token` plus a 6-digit code for a session.

Error responses are `{ error: string, code?: string }`. Validation failures (400/422) are a flat message, not a per-field map. Endpoints live under `/api/auth/*` (`login`, `mfa/verify-login`, `logout`).

## Composition

`ApiClient` and `AuthService` have no circular dependency: `AuthService` holds an unauthenticated `ApiClient` for the auth endpoints (`authApiClientProvider`). A separate, authenticated `ApiClient` (`apiClientProvider`) for the rest of the app uses `authService.currentAccessToken` as `getAccessToken`, `authService.handleUnauthorized` as `onUnauthorized`, and `serverConfigResolver.resolveBaseUrl` as `getBaseUrl` — so every request targets whichever of the public/private server URLs matches the current Wi-Fi network, with a bearer token attached automatically.

## Authenticated requests & sync resilience

A 401 from an authenticated request does **not** clear the session or sign the user out. This app's offline-first principle (see [offline-first.md](offline-first.md)) treats a rejected token the same way it treats being offline: a "can't sync right now" condition, not a reason to lock someone out of an app they were just using. Concretely:

- `AuthService.needsReconnect` (a `ValueNotifier<bool>`, separate from `isAuthenticated`) is set by `handleUnauthorized()` — the stored token and `isAuthenticated` are left untouched.
- [`SyncStatusShell`](../lib/app/sync_status_shell.dart) wraps the authenticated routes (`/trips` and `/trips/:tripId`, via a `ShellRoute`) with a persistent, non-blocking banner shown while `needsReconnect` is set. It never intercepts navigation or hides its child.
- The banner's "Reconnect" action pushes `/reconnect` ([`ReconnectScreen`](../lib/features/auth/reconnect_screen.dart)), which re-runs `login`/`verifyMfaLogin` in place. Success clears `needsReconnect` (and `login`/`verifyMfaLogin` clear it on *any* successful call, not just from this screen, in case something else re-authenticates first).
- `ReconnectScreen` handles its MFA step **inline** on the same screen rather than pushing `/login/mfa` — that route is gated behind "not authenticated," and a user reconnecting is, by design, still authenticated the whole time. Pushing it would just bounce straight back via the router's redirect.
- `TripListScreen` reflects this same principle for its own errors: a `NetworkException` shows an explicit offline state with retry (see [offline-first.md](offline-first.md)); a 401 falls back to its plain empty state rather than showing a second, duplicate error — the banner above it already said what's wrong.

`needsReconnect` is cleared by `logout()` too, since it's meaningless once there's no session at all.
