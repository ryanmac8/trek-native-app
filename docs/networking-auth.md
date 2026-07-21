# Networking & Auth

First slice of [issue #1](https://github.com/ryanmac8/trek-native-app/issues/1): the HTTP client, error handling, server config, token storage, and the login/MFA/logout flow. No login/server-setup UI yet (depends on [issue #2](https://github.com/ryanmac8/trek-native-app/issues/2)'s navigation), and no request/response models for the rest of the data model yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/config/server_config.dart](../lib/config/server_config.dart) | `ServerConfig` — the user-entered, persisted base URL of the user's Trek instance. `ServerConfigStorage`/`PreferencesServerConfigStorage` persist it via `shared_preferences` (plain storage; not a secret). |
| [lib/network/api_exception.dart](../lib/network/api_exception.dart) | Typed exceptions: `NetworkException`, `UnauthorizedException`, `ForbiddenException`, `ValidationException`, `ServerException` (with status code) — each optionally carries Trek's `code` field (e.g. `AUTH_REQUIRED`). |
| [lib/network/api_client.dart](../lib/network/api_client.dart) | Wraps `package:http`. Resolves paths against a base URL, JSON-encodes/decodes bodies, attaches a bearer token via an injected `getAccessToken` callback, and maps non-2xx responses to the exceptions above. |
| [lib/auth/session_token.dart](../lib/auth/session_token.dart) | `SessionToken` — Trek's single session JWT, decoding its `exp` claim client-side. |
| [lib/auth/token_storage.dart](../lib/auth/token_storage.dart) | `TokenStorage` interface + `SecureTokenStorage`, which persists the token in the iOS Keychain / Android Keystore via `flutter_secure_storage`. |
| [lib/auth/auth_service.dart](../lib/auth/auth_service.dart) | `login`, `verifyMfaLogin`, `logout`, `currentAccessToken` (expiry-aware, local-only check), `handleUnauthorized`, and an `isAuthenticated` listenable. |

## Server configuration

Trek is self-hosted — there is no fixed vendor-run API URL. `ServerConfig.parse` validates and normalizes a user-entered address (e.g. `https://trek.example.com` or `http://192.168.1.50:3000` for a LAN instance); `PreferencesServerConfigStorage` persists it; `ApiClient.baseUrl` reads it.

## Auth contract

Trek issues a single JWT per session — `POST /api/auth/login` returns `{ token, user }`, and the JWT's own `exp` claim is the session lifetime. There is no refresh-token exchange for password logins: an expired or invalidated token means the user has to log in again.

If the account has TOTP enabled, `login()` returns `{ mfa_required: true, mfa_token }` instead of a session; `POST /api/auth/mfa/verify-login` exchanges the `mfa_token` plus a 6-digit code for a session.

Error responses are `{ error: string, code?: string }`. Validation failures (400/422) are a flat message, not a per-field map. Endpoints live under `/api/auth/*` (`login`, `mfa/verify-login`, `logout`).

## Composition

`ApiClient` and `AuthService` have no circular dependency: `AuthService` holds an unauthenticated `ApiClient` for the auth endpoints. A separate, authenticated `ApiClient` for the rest of the app uses `authService.currentAccessToken` as `getAccessToken` and `authService.handleUnauthorized` as `onUnauthorized`, so a 401 clears the session and `isAuthenticated` reflects it.
