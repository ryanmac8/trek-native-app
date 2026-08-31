# Settings & account management

The first slice of [issue #27](https://github.com/ryanmac8/trek-native-app/issues/27): a `/settings` screen showing the signed-in account, the configured server, and sign out. Editing the profile, changing the password, managing MFA, and deleting the account are not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/account/account_models.dart](../lib/account/account_models.dart) | `TrekAccount` — the signed-in user (`id`, `username`, `email`, `role`, `avatarUrl`, `oidcIssuer`, `createdAt`, `mfaEnabled`, `mustChangePassword`), with an `isSsoAccount` getter. The wire shape and the local-cache shape are the same JSON, so `fromJson` / `toJson` round-trip through the local store. |
| [lib/account/account_api.dart](../lib/account/account_api.dart) | `AccountApi` — wraps `GET /api/auth/me`. A thin transport layer: no caching, no offline handling. |
| [lib/account/account_local_store.dart](../lib/account/account_local_store.dart) | `AccountLocalStore` / `PreferencesAccountLocalStore` — a single-slot `shared_preferences` cache of the last-known account. A `null` read means "nothing cached" (never fetched, or cleared on sign-out). |
| [lib/account/account_repository.dart](../lib/account/account_repository.dart) | `AccountRepository` — the offline-first front door the screen uses instead of `AccountApi`. See below. |
| [lib/features/settings/settings_screen.dart](../lib/features/settings/settings_screen.dart) | `SettingsScreen` — the `/settings` screen, reachable from the trip list's app-bar settings icon. An account card, a server card (public / private URL and trusted Wi-Fi, with **Change server**), and **Sign out**. |

## API contract

`GET /api/auth/me` is JWT-guarded (`AuthController`, `server/src/nest/auth/`), so this uses the app's authenticated `ApiClient` (`apiClientProvider` in `lib/app/providers.dart`) — the first client on `main` to attach `AuthService.currentAccessToken` and clear the local session on a 401. See [networking-auth.md](networking-auth.md#composition).

- **`GET /api/auth/me`** → `{ user: { id, username, email, role, avatar_url, oidc_issuer, created_at, mfa_enabled, must_change_password } }`. Secrets (password hash, stored API keys, MFA secret and backup codes) are stripped server-side by `stripUserForClient` and never sent. `created_at` is ISO-8601, `Z`-suffixed. `role` is `user` or `admin`. `oidc_issuer` is set only for SSO accounts. A dead session responds `401 { error }`.

The endpoint is `@MfaExempt` server-side — the client can load the account even mid-MFA-setup.

## Offline-first (`AccountRepository`)

Per [offline-first.md](offline-first.md), the screen never calls `AccountApi` directly. The account is read-only in this slice, and the local cache is the source of truth for what the screen shows:

- **`cachedAccount`** reads the local store only. The screen calls it first so the last-known profile paints instantly.
- **`refreshAccount`** fetches the current account, writes it to the cache, and returns it. A `NetworkException` propagates unchanged: the screen keeps showing the cached profile (with an offline notice) when it has one, and shows an explicit offline state with a retry when it does not. An `UnauthorizedException` also propagates — the shared client has already cleared the session and the router redirects to login.
- **`clearCachedAccount`** drops the cached profile. The screen calls it on an explicit **Sign out** or **Change server** so the next account can't briefly see the previous one. A 401-driven logout does not clear the cache; the next sign-in's `refreshAccount` overwrites it.

There are no local writes. Editing the profile is a mutation that needs the durable outbox [#21](https://github.com/ryanmac8/trek-native-app/issues/21) will decide on; the `shared_preferences` cache here is a minimal, feature-scoped stand-in for the local-persistence mechanism #21 will settle.

## Server management

The server card reads the stored `ServerConfig` (`ServerConfigStorage`, a purely local read — see [networking-auth.md](networking-auth.md#server-configuration)) and shows the public URL, the private URL, and the trusted Wi-Fi SSIDs. **Change server** clears the stored config and the cached account and signs out; the router then redirects to server setup because no server is configured.

## What's still open

- Editing username / email (`PUT /api/auth/me/settings`), changing the password (`PUT /api/auth/me/password`), and deleting the account (`DELETE /api/auth/me`). A password change re-issues the session server-side; on a bearer client the current token is invalidated, so this needs its own re-authentication flow rather than a plain form.
- Managing MFA (`POST /api/auth/mfa/setup` / `enable` / `disable`) and avatar upload (`POST /api/auth/avatar`).
- Editing the server URLs in place, rather than clearing and re-running server setup.
- The runtime Wi-Fi / location permission prompt the private-URL switching needs (noted in [networking-auth.md](networking-auth.md#server-configuration)).
- App version / build number and links to Trek's licenses.
