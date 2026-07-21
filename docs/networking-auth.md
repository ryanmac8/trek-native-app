# Networking & Auth Foundation

Status of [issue #1](https://github.com/ryanmac8/trek-native-app/issues/1). This covers the first slice: the HTTP client, error handling, environment config, token storage, and the login/logout/refresh flow. It does not yet include a login screen (that depends on the navigation/design-system work in [issue #2](https://github.com/ryanmac8/trek-native-app/issues/2)) or the full set of Trek data models — those are follow-up PRs against the same issue.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/config/environment.dart](../lib/config/environment.dart) | `Environment` enum (dev/staging/prod) and the base URL for each. Selected via `--dart-define=TREK_ENV=dev\|staging\|prod` at build/run time; defaults to prod. |
| [lib/network/api_exception.dart](../lib/network/api_exception.dart) | Typed exceptions: `NetworkException`, `UnauthorizedException`, `ForbiddenException`, `ValidationException` (with field errors), `ServerException` (with status code). |
| [lib/network/api_client.dart](../lib/network/api_client.dart) | Wraps `package:http`. Resolves paths against a base URL, JSON-encodes/decodes bodies, attaches a bearer token via an injected `getAccessToken` callback, and maps non-2xx responses to the exceptions above. |
| [lib/auth/auth_tokens.dart](../lib/auth/auth_tokens.dart) | `AuthTokens` model (access token, refresh token, computed expiry). |
| [lib/auth/token_storage.dart](../lib/auth/token_storage.dart) | `TokenStorage` interface + `SecureTokenStorage`, which persists tokens in the iOS Keychain / Android Keystore via `flutter_secure_storage`. |
| [lib/auth/auth_service.dart](../lib/auth/auth_service.dart) | `login`, `logout`, `refreshTokens`, `currentAccessToken` (auto-refreshes if expired), and an `isAuthenticated` listenable for UI to react to session changes. |

## How the pieces fit together

`ApiClient` doesn't know about `AuthService`, and `AuthService` only uses `ApiClient` to call the auth endpoints — there's no circular dependency. The intended wiring, once issue #2 sets up app-wide composition:

1. Create one unauthenticated `ApiClient` and pass it to `AuthService`.
2. Create a second, authenticated `ApiClient` for the rest of the app, passing `authService.currentAccessToken` as `getAccessToken` and `authService.refreshTokens` (wrapped to return `bool`) as `onUnauthorized`, so a 401 anywhere in the app triggers a silent refresh-and-retry.

This split keeps the auth client from ever needing its own output as an input.

## Error handling

`ApiClient` throws one of the sealed `ApiException` subtypes for every failure mode — callers can `catch (e) when (e is ApiException)` for a generic message, or switch on the concrete type to special-case, e.g., redirecting to login on `UnauthorizedException`. A future PR will wire these into the global snackbar/toast system tracked in issue #2.

## Assumptions to verify against the real backend

The auth endpoints (`POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`) and their JSON shapes (`accessToken` / `refreshToken` / `expiresIn`) are placeholders based on common conventions — they haven't been checked against Trek's actual API yet. Update `AuthTokens.fromJson` and the paths in `AuthService` once the real contract is confirmed.

## How to test

```bash
flutter pub get
flutter test test/config/environment_test.dart
flutter test test/network/api_client_test.dart
flutter test test/auth/token_storage_test.dart
flutter test test/auth/auth_service_test.dart

# or the whole suite
flutter test
flutter analyze
```

All tests run against fakes (`package:http/testing.dart`'s `MockClient` for HTTP, a mocked platform channel for secure storage) — no real network calls or device/simulator needed.
