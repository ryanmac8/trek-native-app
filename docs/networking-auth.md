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
| [lib/auth/session_token.dart](../lib/auth/session_token.dart) | `SessionToken` — Trek's single session JWT, decoding its `exp` claim client-side. |
| [lib/auth/token_storage.dart](../lib/auth/token_storage.dart) | `TokenStorage` interface + `SecureTokenStorage`, which persists the token in the iOS Keychain / Android Keystore via `flutter_secure_storage`. |
| [lib/auth/auth_service.dart](../lib/auth/auth_service.dart) | `login`, `verifyMfaLogin`, `logout`, `currentAccessToken` (expiry-aware, local-only check), `handleUnauthorized`, and an `isAuthenticated` listenable. |

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
