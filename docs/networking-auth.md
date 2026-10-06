# Networking & Auth

First slice of [issue #1](https://github.com/ryanmac8/trek-native-app/issues/1): the HTTP client, error handling, server config, token storage, and the login/MFA/logout flow. No login/server-setup UI yet (depends on [issue #2](https://github.com/ryanmac8/trek-native-app/issues/2)'s navigation), and no request/response models for the rest of the data model yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/config/server_config.dart](../lib/config/server_config.dart) | `ServerConfig` — the user's public and (optional) private server URLs, plus the Wi-Fi SSIDs that should use the private one. `ServerConfigStorage`/`PreferencesServerConfigStorage` persist it via `shared_preferences` (plain storage; not a secret). |
| [lib/config/wifi_network_info.dart](../lib/config/wifi_network_info.dart) | `WifiNetworkInfo` — the current Wi-Fi SSID, or `null` if unavailable. `DeviceWifiNetworkInfo` is the real implementation, backed by `network_info_plus`. |
| [lib/config/server_config_resolver.dart](../lib/config/server_config_resolver.dart) | `ServerConfigResolver.resolveBaseUrl()` — combines `ServerConfigStorage` and `WifiNetworkInfo` into the single base URL to use for the current network. |
| [lib/network/api_exception.dart](../lib/network/api_exception.dart) | Typed exceptions: `NetworkException`, `UnauthorizedException`, `ForbiddenException`, `ValidationException`, `ServerException` (with status code) — each optionally carries Trek's `code` field (e.g. `AUTH_REQUIRED`). |
| [lib/network/api_client.dart](../lib/network/api_client.dart) | Wraps `package:http`. Resolves paths against a base URL (fixed via `baseUrl`, or resolved per-request via `getBaseUrl`), JSON-encodes/decodes bodies, attaches a bearer token via an injected `getAccessToken` callback, and maps non-2xx responses to the exceptions above. |
| [lib/auth/session_token.dart](../lib/auth/session_token.dart) | `SessionToken` — Trek's single session JWT, decoding its `exp` and `id` (user id) claims client-side. |
| [lib/auth/token_storage.dart](../lib/auth/token_storage.dart) | `TokenStorage` interface + `SecureTokenStorage`, which persists the token in the iOS Keychain / Android Keystore via `flutter_secure_storage`. |
| [lib/auth/auth_service.dart](../lib/auth/auth_service.dart) | `login`, `verifyMfaLogin`, `logout`, `currentAccessToken` (expiry-aware, local-only check), `handleUnauthorized`, and an `isAuthenticated` listenable. |
| [lib/auth/local_data.dart](../lib/auth/local_data.dart) | `AccountScopedData` (a clearable account-owned store), `LocalDataRegistry` (all such stores on the device), and `LocalDataOwner`/`LocalDataOwnerStorage` (which account the local data belongs to). |
| [lib/features/auth/logout_action.dart](../lib/features/auth/logout_action.dart) | `confirmAndLogout` — the logout entry point for UI; confirms first when unsynced changes would be discarded. |

## Server configuration

Trek is self-hosted — there is no fixed vendor-run API URL. `ServerConfig` holds a `publicUrl` (always reachable — a domain behind a reverse proxy, dynamic DNS, etc.) and an optional `privateUrl` (a local-network address, e.g. `http://192.168.1.50:3000`), plus a set of Wi-Fi SSIDs on which the private URL should be used. `ServerConfig.validateUrl` validates and normalizes a user-entered address for either field. `ServerConfig.resolveBaseUrl(currentSsid)` returns the private URL when connected to a trusted SSID and a private URL is configured, otherwise the public URL.

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

`ApiClient` and `AuthService` have no circular dependency: `AuthService` holds an unauthenticated `ApiClient` for the auth endpoints. A separate, authenticated `ApiClient` for the rest of the app uses `authService.currentAccessToken` as `getAccessToken`, `authService.handleUnauthorized` as `onUnauthorized`, and `serverConfigResolver.resolveBaseUrl` as `getBaseUrl` — so a 401 clears the session and `isAuthenticated` reflects it, and every request targets whichever of the public/private server URLs matches the current Wi-Fi network.

## Logout and account-scoped local data

Local data belongs to one account, identified by a `LocalDataOwner`: the configured server's public URL plus the user id from the session JWT's `id` claim (Trek signs `{ id, pv, remember? }`). The owner of the data currently on the device is persisted by `PreferencesLocalDataOwnerStorage` under the `shared_preferences` key `trek.local_data.owner`.

Feature stores implement `AccountScopedData` (`name`, `clear()`, and optionally `unsyncedChangeCount()`) and register with the `LocalDataRegistry` that `AuthService` is constructed with (`localDataRegistryProvider`). `LocalDataRegistry.clearAll()` clears every store, continues past a store that throws, and returns the failures rather than throwing.

| Event | Session token | Account-scoped local data | Recorded owner |
| --- | --- | --- | --- |
| `logout()` | Cleared | Cleared | Cleared |
| `login()` / `verifyMfaLogin()` as the recorded owner | Written | Kept | Kept |
| `login()` / `verifyMfaLogin()` as anyone else, or with no recorded owner | Written | Cleared before the token is written | Replaced |
| Token expiry, `handleUnauthorized()` (401) | Cleared | Kept | Kept |

Logout's `POST /api/auth/logout` only clears the web client's cookie (it is `@Public` and returns `{ success: true }`), so it is best-effort: local clearing happens whether or not it succeeds, including offline. Keeping local data across an expired or rejected session means the same account signing back in still has its offline cache; the login-time owner check is what stops a different account (or the same user id on a different server) from seeing it. If the owner can't be determined — no `id` claim, no server URL, or owner storage failing — the data is treated as belonging to someone else and cleared.

Clearing discards writes that haven't reached the server. `confirmAndLogout` sums `unsyncedChangeCount()` across the registry and, if it is non-zero, asks the user to confirm before logging out.
