# App Shell

Covers [issue #2](https://github.com/ryanmac8/trek-native-app/issues/2): state management, navigation, and the design system, plus wiring [issue #1](https://github.com/ryanmac8/trek-native-app/issues/1)'s `AuthService`/`ServerConfigStorage` into real screens. `TripListScreen` is the first (read-only) slice of trip data — full trip detail is still [#3](https://github.com/ryanmac8/trek-native-app/issues/3) onward.

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
| `apiClientProvider` | `ApiClient` | authenticated client for the rest of the API — see [networking-auth.md](networking-auth.md#authenticated-requests--sync-resilience) |
| `biometricAuthServiceProvider` | `BiometricAuthService` | see [biometric-lock.md](biometric-lock.md) |
| `appLockStateProvider` | `AppLockState` | ditto |
| `tripsApiProvider` | `TripsApi` | read-only `GET /api/trips` wrapper — see "Screens" below |
| `appRouterProvider` | `GoRouter` | see below |

## Navigation

[go_router](https://pub.dev/packages/go_router) (`go_router`), built by [lib/app/router.dart](../lib/app/router.dart)'s `buildAppRouter`. Routes:

| Path | Screen |
| --- | --- |
| `/server-setup` | `ServerSetupScreen` |
| `/login` | `LoginScreen` |
| `/login/mfa` | `MfaScreen` (reached with the `mfaToken` as `extra`) |
| `/lock` | `BiometricLockScreen` — see [biometric-lock.md](biometric-lock.md) |
| `/reconnect` | `ReconnectScreen` — see [networking-auth.md](networking-auth.md#authenticated-requests--sync-resilience) |
| `/settings` | `SettingsScreen` — a hub listing sub-pages (currently just Networking), matching the pattern self-hosted apps like Immich use. Reached from `TripListScreen`'s AppBar; owns the logout action |
| `/settings/networking` | `NetworkingSettingsScreen` — edits the full `ServerConfig` (public URL, plus a list of private/LAN endpoints each tied to one Wi-Fi network) |
| `/trips` | `TripListScreen` (wrapped in a `ShellRoute` with `SyncStatusShell`, along with `/trips/new` and `/trips/:tripId`) |
| `/trips/new` | `CreateTripScreen` |
| `/trips/:tripId` | `TripDashboardScreen` |

`redirect` gates navigation on local (never network) reads, evaluated on every navigation, in order:

1. `ServerConfigStorage.read()` — no server configured → `/server-setup`.
2. `AuthService.isAuthenticated.value` — no session → `/login`.
3. `AppLockState.biometricsAvailable && !AppLockState.isUnlocked.value` — biometrics available but not unlocked this run → `/lock`.

`refreshListenable` is `Listenable.merge([authService.isAuthenticated, appLockState.isUnlocked])`, so the router re-evaluates on its own the moment either changes (login/logout/token-expiry/unlock) — screens that change this state never call `context.go()` themselves. `/reconnect` is a normal freely-visitable destination once authenticated+unlocked (reached by tapping the sync-status banner), not another gate — see [networking-auth.md](networking-auth.md#authenticated-requests--sync-resilience) for why it has to handle its own MFA step inline instead of pushing `/login/mfa`.

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
| `widgets/skeleton_box.dart` | `SkeletonBox` (pulsing placeholder rect) and `SkeletonListTile` (its list-row-shaped composition) for content whose shape is known before it loads |
| `widgets/app_card.dart` | `AppCard` — bordered, rounded content container, optionally tappable |
| `widgets/app_list_row.dart` | `AppListRow` — standard leading/title/subtitle/trailing row; `SkeletonListTile` mirrors its layout |

`PlaceCategory`'s colors/icons are copied from Trek's actual default category seed data (`server/src/db/seeds.ts` in the [backend repo](https://github.com/liketrek/TREK)), not from issue #2's checklist text — that list has a copy-paste error (`🍽️ Cafe` with no color; the real category is `Bar/Cafe`, `#f97316`, `☕`).

**`PlaceCategory` represents the fresh-install defaults only — Trek's categories are per-user, editable data, not fixed constants.** Confirmed live against a real server: a user can rename a default category, recolor it, or change its icon (including to a non-emoji icon name — `GET /api/categories` on a real instance returned `{"name":"Cafe","icon":"Coffee",...}` for what started as `Bar/Cafe`/`☕`), and add entirely custom categories on top. `PlaceCategory` is a reasonable design-system default for previewing the palette (see the trip dashboard's Places tab) but is not what [#5](https://github.com/ryanmac8/trek-native-app/issues/5) (Places & categories) should build feature logic against — that needs a real `Category` model fetched from `/api/categories`, not this hardcoded enum.

`SkeletonBox`/`AppCard`/`AppListRow` don't have a call site yet — no screen has real list data to load. They're built ahead of [#3](https://github.com/ryanmac8/trek-native-app/issues/3) onward the same way the color/spacing tokens were: so the first feature screen composes them instead of inventing its own. Form fields, date/time pickers, and currency input are still genuinely deferred — no screen shape to design them against yet.

## App icon, splash image, and startup animation

`assets/icon/` holds three renders of Trek's actual T-mark (the geometric logo from the [web client](https://github.com/liketrek/TREK)'s `client/public/icons/icon.svg`, not a placeholder):

| File | Used by |
| --- | --- |
| `icon.png` | `flutter_launcher_icons` (see `pubspec.yaml`) — full-bleed mark + gradient background, generates the iOS/Android app icon |
| `splash.png` | `flutter_native_splash` — mark only, transparent background, composited onto a solid `#0F172A` (the icon gradient's dark end) set via `flutter_native_splash`'s `color` config — generates the native static launch image shown before Flutter starts |
| `mark.png` | [lib/app/splash_screen.dart](../lib/app/splash_screen.dart) — the same asset, animated in-app |

The source SVG uses small rounded corners (cubic bezier segments); the PNGs were rendered by parsing the path's vertices directly and filling straight-edged polygons (rounding is imperceptible at icon/splash sizes) rather than pulling in a native SVG-rasterization toolchain for one-time asset generation. Regenerate with `dart run flutter_launcher_icons` / `dart run flutter_native_splash:create` after changing the source PNGs or their config in `pubspec.yaml`.

A native launch image can only ever be static (an OS-level constraint on both iOS and Android, not a Flutter limitation) — `SplashScreen` is the animated handoff to it: a dark gradient background styled after Trek's web login screen, a `CustomPainter` star field that both twinkles and continuously drifts (bigger/nearer stars drift faster than smaller/farther ones, a simple parallax depth cue, all on a shared diagonal heading so it reads as flying through rather than scattering), and the T-mark fading and scaling in. The drift is driven by a single long-duration (`_flightDurationSeconds`), non-reversing, repeating `AnimationController` whose value maps linearly to elapsed seconds — the loop-back seam it eventually has is never actually seen, since the splash is only on screen for a couple of seconds. `TrekApp` shows it for at least 1400ms (`_minSplashDuration` in [lib/app/trek_app.dart](../lib/app/trek_app.dart)) even though `AuthService.restoreSession()` alone resolves almost instantly, so the reveal animation always gets to finish.

## Global messaging

[lib/app/app_messenger.dart](../lib/app/app_messenger.dart)'s `AppMessenger` shows snackbar-based error/success/info messages from anywhere — screens and services alike — via a single `scaffoldMessengerKey` wired into `MaterialApp.router`. Use it for messages with no natural spot in the UI (a background sync failure, a completed action); form-validation errors that sit next to their field (see `LoginScreen`, `ServerSetupScreen`) should stay inline rather than move to a toast. `showError` also fires two quick `HapticFeedback.vibrate()` pulses — a single buzz reads as a routine acknowledgment, two distinctly reads as "something's wrong" — so any caller of `showError` gets this for free rather than each screen wiring up its own haptic.

## Screens

- **`ServerSetupScreen`** — first-run only, collects just the public server URL via `ServerConfig.validateUrl`, to get onboarding to login as fast as possible. Writes to `ServerConfigStorage` and lets the redirect carry the user to `/login`.
- **`SettingsScreen`** — a hub, not a flat form: a list of sub-pages (only `NetworkingSettingsScreen` so far), reached from `TripListScreen`'s AppBar. Owns the logout action in its own AppBar — an account-level action, not a trip-list one, so `TripListScreen` no longer has it.
- **`NetworkingSettingsScreen`** — the full `ServerConfig` editor: the public URL, plus a list of private (LAN) endpoints, pre-filled from the current config. Each endpoint pairs a URL with the one Wi-Fi network it should be used on (an "Add endpoint" dialog collects both, with a "use current Wi-Fi network" shortcut, and pings the URL's `/api/health` before saving — reachability is advisory, offering "Save anyway" rather than blocking, per [offline-first.md](offline-first.md)). Private endpoints are a power-user setting, intentionally not asked for during first-run onboarding.
- **`LoginScreen`** / **`MfaScreen`** — call `AuthService.login` / `verifyMfaLogin` directly; an `ApiException` is caught and shown inline (including `NetworkException` when offline — see [offline-first.md](offline-first.md)). Neither screen navigates on success; the router's `refreshListenable` does that. Both also mark the app unlocked (`AppLockState.isUnlocked`) on success, since typing a password/MFA code already proves identity — see [biometric-lock.md](biometric-lock.md).
- **`BiometricLockScreen`** / **`ReconnectScreen`** — see [biometric-lock.md](biometric-lock.md) and [networking-auth.md](networking-auth.md#authenticated-requests--sync-resilience) respectively.
- **`TripListScreen`** — reads from `TripsRepository`'s local cache first (instant, works offline — see [trips.md](trips.md)), then refreshes from `GET /api/trips` in the background. A bottom `NavigationBar` splits trips into "Upcoming Trips" (default) and "Past Trips", by comparing `Trip.endDate` to today; an undated trip (still being planned, or not yet synced) counts as upcoming. Degrades explicitly per [offline-first.md](offline-first.md): a `NetworkException` with nothing cached shows an offline state with a retry action rather than hanging, and a 401 falls back to the plain empty state (the `SyncStatusShell` banner above it already surfaces that, so the screen doesn't duplicate the message).
- **`TripDashboardScreen`** — a customizable bottom nav across nine sections (Days/Places/Budget/Packing/Todos/Book/Lists/Files/Collab); only Days (see [days.md](days.md)) reads real data, the rest are placeholders. The Places tab also previews every `PlaceCategory` swatch as a visual check of the design tokens. Only 4 tabs fit in the collapsed bar at once — a trailing hamburger button expands an overflow panel (an `AnimatedSwitcher`/`SizeTransition` sliding it up above the bar) listing the rest. Any tab can be dragged (`Draggable`/`DragTarget`) between a bar slot and the panel to customize which 4 show by default; tapping a panel tab (rather than dragging it) selects it without changing the layout. The chosen layout persists via `TripDashboardNavLayoutStore`, a plain `shared_preferences` read/write — this is a device-local UI preference, not trip data, so it's outside the offline-first trip-data story in [offline-first.md](offline-first.md) and isn't scoped per-trip.

## Deferred

Left for later slices of issue #2, noted here rather than guessed at:

- Local caching/offline writes for trips (and everything else in the data model) — belongs with [#21](https://github.com/ryanmac8/trek-native-app/issues/21)'s offline-sync mechanism. `TripListScreen`'s reads are network-only for now.
- Form fields, date/time pickers, currency input — no screen shape to design them against yet.
- Android adaptive icon foreground/background layers — the launcher icon currently uses the simpler legacy (non-adaptive) path.
