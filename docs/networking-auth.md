# Networking & Auth Foundation

Status of [issue #1](https://github.com/ryanmac8/trek-native-app/issues/1). This covers the first slice: the HTTP client, error handling, server config, token storage, and the login/MFA/logout flow. It does not yet include a login/server-setup screen (that depends on the navigation/design-system work in [issue #2](https://github.com/ryanmac8/trek-native-app/issues/2)) or the full set of Trek data models — those are follow-up PRs against the same issue.

The auth contract here was checked against Trek's actual backend ([liketrek/TREK](https://github.com/liketrek/TREK), `server/src/nest/auth/`), not guessed — see "What Trek's API actually looks like" below.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/config/server_config.dart](../lib/config/server_config.dart) | `ServerConfig` — the user-entered, persisted base URL of the user's own Trek instance (Trek is self-hosted, so there's no fixed dev/staging/prod). `ServerConfigStorage`/`PreferencesServerConfigStorage` persist it in plain local storage (`shared_preferences`) since it isn't a secret. |
| [lib/network/api_exception.dart](../lib/network/api_exception.dart) | Typed exceptions: `NetworkException`, `UnauthorizedException`, `ForbiddenException`, `ValidationException`, `ServerException` (with status code) — each optionally carrying Trek's machine-readable `code` (e.g. `AUTH_REQUIRED`). |
| [lib/network/api_client.dart](../lib/network/api_client.dart) | Wraps `package:http`. Resolves paths against a base URL, JSON-encodes/decodes bodies, attaches a bearer token via an injected `getAccessToken` callback, and maps non-2xx responses (Trek's `{ error, code? }` shape) to the exceptions above. |
| [lib/auth/session_token.dart](../lib/auth/session_token.dart) | `SessionToken` — Trek's single session JWT, decoding its `exp` claim client-side to know when it goes stale. |
| [lib/auth/token_storage.dart](../lib/auth/token_storage.dart) | `TokenStorage` interface + `SecureTokenStorage`, which persists the token in the iOS Keychain / Android Keystore via `flutter_secure_storage`. |
| [lib/auth/auth_service.dart](../lib/auth/auth_service.dart) | `login`, `verifyMfaLogin`, `logout`, `currentAccessToken` (clears an expired session rather than refreshing it), `handleUnauthorized`, and an `isAuthenticated` listenable for UI to react to session changes. |

## What Trek's API actually looks like

Reading `server/src/nest/auth/` in the real backend corrected several assumptions from the first draft of this PR:

- **One JWT, not an access/refresh pair.** `POST /api/auth/login` returns `{ token, user }`. The JWT's own `exp` claim (backed by `SESSION_DURATION` / `SESSION_DURATION_REMEMBER` server-side) is the whole session lifetime.
- **No refresh endpoint for password logins.** There's a `refresh_token` concept in the codebase, but it's scoped to the OAuth/MCP plugin subsystem, not the user-facing login flow. Once the JWT expires (or its `password_version` claim is invalidated by a password change elsewhere), the user has to log in again — there's nothing to silently exchange it for. `AuthService.currentAccessToken` and `AuthService.handleUnauthorized` both just clear the session rather than pretending to refresh it.
- **Login can require MFA.** If the account has TOTP enabled, `login()` returns `{ mfa_required: true, mfa_token }` instead of a session — the caller must collect a 6-digit code and call `AuthService.verifyMfaLogin`. Modeled as a `LoginResult` sealed type (`LoggedIn` | `MfaRequired`) so callers can't forget to handle it.
- **Error responses are `{ error: string, code?: string }`**, not `{ message: string }`. `ApiClient` reads `error` first (falling back to `message` for forward compatibility) and surfaces `code` on the exception when present.
- **Endpoints live under `/api/auth/*`** (`login`, `mfa/verify-login`, `logout`), not a bare `/auth/*`.
- **Validation failures are a flat message**, not a per-field map — `ValidationException` reflects that; there's no `errors: { field: [...] }` shape to parse.

## Why there's no dev/staging/prod environment config

An earlier draft of this PR modeled "Environment/config management" (per issue #1's checklist) as a fixed `Environment` enum (dev/staging/prod) with hardcoded base URLs, the way a vendor-run SaaS API would work. That's wrong for Trek: the real project is **self-hosted** ("Your trips. Your plan. Your server." — Docker image, Unraid template, etc.), like Nextcloud or Immich. There is no `api.trek.app` — every user runs their own instance at their own URL. `ServerConfig` reflects that instead: a single user-entered address (e.g. `https://trek.example.com` or `http://192.168.1.50:3000` for a LAN instance), validated and normalized by `ServerConfig.parse`, persisted via `PreferencesServerConfigStorage`, and read by `ApiClient`'s `baseUrl`.

There's still no UI to enter it — that's a server-setup step that belongs in onboarding (issue [#28](https://github.com/ryanmac8/trek-native-app/issues/28)) once #2's navigation exists. Until then, `ServerConfig`/`ApiClient` can be exercised directly (as the tests do) with a URL supplied in code.

## How the pieces fit together

`ApiClient` doesn't know about `AuthService`, and `AuthService` only uses `ApiClient` to call the auth endpoints — there's no circular dependency. The intended wiring, once issue #2 sets up app-wide composition:

1. Create one unauthenticated `ApiClient` and pass it to `AuthService`.
2. Create a second, authenticated `ApiClient` for the rest of the app, passing `authService.currentAccessToken` as `getAccessToken` and `authService.handleUnauthorized` as `onUnauthorized`, so a 401 anywhere in the app clears the session and the UI (listening to `isAuthenticated`) can redirect to login.

## How to test

```bash
flutter pub get
flutter test test/config/server_config_test.dart
flutter test test/network/api_client_test.dart
flutter test test/auth/session_token_test.dart
flutter test test/auth/token_storage_test.dart
flutter test test/auth/auth_service_test.dart

# or the whole suite
flutter test
flutter analyze
```

All tests run against fakes (`package:http/testing.dart`'s `MockClient` for HTTP, mocked platform channels for secure storage and shared_preferences, hand-built unsigned JWTs for expiry logic) — no real network calls or device/simulator needed.
