# App Shell

First slice of [issue #2](https://github.com/ryanmac8/trek-native-app/issues/2): state management, navigation, and the design system, plus wiring [issue #1](https://github.com/ryanmac8/trek-native-app/issues/1)'s `AuthService`/`ServerConfigStorage` into real screens. No trip data yet — that's [#3](https://github.com/ryanmac8/trek-native-app/issues/3) onward.

## State management

[Riverpod](https://riverpod.dev) (`flutter_riverpod`). [lib/app/providers.dart](../lib/app/providers.dart) wires the networking/auth foundation as providers:

| Provider | Type | Backs |
| --- | --- | --- |
| `serverConfigStorageProvider` | `ServerConfigStorage` | `PreferencesServerConfigStorage` |
| `wifiNetworkInfoProvider` | `WifiNetworkInfo` | `DeviceWifiNetworkInfo` |
| `serverConfigResolverProvider` | `ServerConfigResolver` | combines the two above |
| `authApiClientProvider` | `ApiClient` | unauthenticated client for `/api/auth/*`, using `serverConfigResolverProvider` as `getBaseUrl` |
| `tokenStorageProvider` | `TokenStorage` | `SecureTokenStorage` |
| `authServiceProvider` | `AuthService` | wraps `authApiClientProvider` + `tokenStorageProvider` |
| `appRouterProvider` | `GoRouter` | see below |

An authenticated `ApiClient` (bearer token + 401 handling wired to `AuthService.handleUnauthorized`) isn't provided yet — that belongs to whichever feature first needs to call an authenticated endpoint.

## Navigation

[go_router](https://pub.dev/packages/go_router) (`go_router`), built by [lib/app/router.dart](../lib/app/router.dart)'s `buildAppRouter`. Routes:

| Path | Screen |
| --- | --- |
| `/server-setup` | `ServerSetupScreen` |
| `/login` | `LoginScreen` |
| `/login/mfa` | `MfaScreen` (reached with the `mfaToken` as `extra`) |
| `/trips` | `TripListScreen` |
| `/trips/:tripId` | `TripDashboardScreen` |

`redirect` gates navigation on two local (never network) reads, evaluated on every navigation:

1. `ServerConfigStorage.read()` — no server configured → `/server-setup`.
2. `AuthService.isAuthenticated.value` — no session → `/login`.

`AuthService.isAuthenticated` (a `ValueNotifier<bool>`, so it doubles as a `Listenable`) is passed as `refreshListenable`, so the router re-evaluates on its own the moment a login/logout/token-expiry flips it — screens that change auth state never call `context.go()` themselves.

`TrekApp` ([lib/app/trek_app.dart](../lib/app/trek_app.dart)) calls `AuthService.restoreSession()` once at startup, before building the router, so the first redirect decision reflects a session already on disk rather than the `isAuthenticated` default of `false`.

## Design system

[lib/design/](../lib/design/):

| File | Contents |
| --- | --- |
| `app_colors.dart` | Brand seed color + semantic (success/warning/danger/info) tokens |
| `app_typography.dart` | `TextTheme` type scale |
| `app_spacing.dart` | 4px-based spacing scale (`xs`–`xxl`) |
| `app_theme.dart` | `AppTheme.light` / `AppTheme.dark` — `ColorScheme.fromSeed` + the typography scale, Material 3 |
| `place_category_colors.dart` | `PlaceCategory` enum — label, color, icon for Trek's 10 default place categories |
| `widgets/empty_state.dart` | Centered icon + message for a screen with no data |
| `widgets/loading_indicator.dart` | Centered spinner |

`PlaceCategory`'s colors/icons are copied from Trek's actual default category seed data (`server/src/db/seeds.ts` in the [backend repo](https://github.com/liketrek/TREK)), not from issue #2's checklist text — that list has a copy-paste error (`🍽️ Cafe` with no color; the real category is `Bar/Cafe`, `#f97316`, `☕`).

A broader reusable UI kit (form fields, date/time pickers, currency input, cards, list rows) isn't built yet — screens so far use plain Material widgets styled by `AppTheme`. Build kit pieces as later screens need them, rather than speculatively.

## Screens

- **`ServerSetupScreen`** — collects the public server URL (required) and an optional private/LAN URL + trusted Wi-Fi network names, via `ServerConfig.validateUrl`. Writes to `ServerConfigStorage` and lets the redirect carry the user to `/login`.
- **`LoginScreen`** / **`MfaScreen`** — call `AuthService.login` / `verifyMfaLogin` directly; an `ApiException` is caught and shown inline (including `NetworkException` when offline — see [offline-first.md](offline-first.md)). Neither screen navigates on success; the router's `refreshListenable` does that.
- **`TripListScreen`** — empty state (no trip data model yet) plus a working logout action.
- **`TripDashboardScreen`** — bottom `NavigationBar` with the five sections issue #2 calls for (Days/Places/Budget/Packing/Todos), each a placeholder. The Places tab also previews every `PlaceCategory` swatch as a visual check of the design tokens.

## Deferred

Left for later slices of issue #2, noted here rather than guessed at:

- Local caching strategy (what's cached, invalidation) — belongs with [#21](https://github.com/ryanmac8/trek-native-app/issues/21)'s offline-sync mechanism.
- Global error/toast/snackbar system.
- App icon, splash screen.
- The rest of the reusable UI kit (cards, list rows, date/time pickers, currency input, skeleton loading states).
