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
| `widgets/skeleton_box.dart` | `SkeletonBox` (pulsing placeholder rect) and `SkeletonListTile` (its list-row-shaped composition) for content whose shape is known before it loads |
| `widgets/app_card.dart` | `AppCard` — bordered, rounded content container, optionally tappable |
| `widgets/app_list_row.dart` | `AppListRow` — standard leading/title/subtitle/trailing row; `SkeletonListTile` mirrors its layout |
| `widgets/date_time_fields.dart` | `DateField` / `TimeField` — read-only, text-field-styled inputs that open the platform date/time picker; see [Form fields](#form-fields) |
| `widgets/currency_amount_field.dart` | `CurrencyAmountField` (+ its `CurrencyAmountInputFormatter`) — money input for one currency; see [Form fields](#form-fields) |
| `formats/trek_date_time.dart` | `TrekDateTime` — conversions to/from Trek's `YYYY-MM-DD` date and `HH:MM` time strings |
| `formats/currency.dart` | `Currency` — Trek's selectable currency codes, symbols, decimal places, decimal separators, and amount text parsing/formatting |

`PlaceCategory`'s colors/icons are copied from Trek's actual default category seed data (`server/src/db/seeds.ts` in the [backend repo](https://github.com/liketrek/TREK)), not from issue #2's checklist text — that list has a copy-paste error (`🍽️ Cafe` with no color; the real category is `Bar/Cafe`, `#f97316`, `☕`).

**`PlaceCategory` represents the fresh-install defaults only — Trek's categories are per-user, editable data, not fixed constants.** Confirmed live against a real server: a user can rename a default category, recolor it, or change its icon (including to a non-emoji icon name — `GET /api/categories` on a real instance returned `{"name":"Cafe","icon":"Coffee",...}` for what started as `Bar/Cafe`/`☕`), and add entirely custom categories on top. `PlaceCategory` is a reasonable design-system default for previewing the palette (see the trip dashboard's Places tab) but is not what [#5](https://github.com/ryanmac8/trek-native-app/issues/5) (Places & categories) should build feature logic against — that needs a real `Category` model fetched from `/api/categories`, not this hardcoded enum.

`SkeletonBox`/`AppCard`/`AppListRow` and the form fields below don't have a call site yet — no screen has real list data to load or edit. They're built ahead of [#3](https://github.com/ryanmac8/trek-native-app/issues/3) onward the same way the color/spacing tokens were: so the first feature screen composes them instead of inventing its own.

### Form fields

**`DateField` / `TimeField`** are stateless: the parent owns `value` (`DateTime?` / `TimeOfDay?`) and rebuilds with whatever `onChanged` reports. Tapping opens `showDatePicker` / `showTimePicker`; dismissing the picker reports nothing, and an optional clear button (`clearable: true`) reports `null`. Both are styled like a text field (label, leading icon, `errorText`), so they line up with typed fields in the same form.

- `DateField` displays e.g. `Sat, Mar 7, 2026`, reports picks as local midnight, and opens on `value`, else `initialPickerDate`, else today — clamped into `firstDate`..`lastDate` (default: ten years either side of today).
- `TimeField` displays in the device's 12/24-hour preference and opens on `value`, else `initialPickerTime` (default 09:00).

Trek stores dates as `YYYY-MM-DD` strings (day dates, trip start/end, vacay entries, expense dates) and times as `HH:MM` (assignment times, day-note time labels; some reservation time columns hold a local `YYYY-MM-DDTHH:MM`). `TrekDateTime.formatDate`/`parseDate` and `formatTime`/`parseTime` convert between those and `DateTime`/`TimeOfDay`; the parsers return `null` for anything malformed or out of range (`2026-02-30`, `24:00`) rather than throwing.

**`CurrencyAmountField`** is a `TextFormField` for an amount in one ISO 4217 `currency` (e.g. a trip's `currency`). It follows the money rules of Trek's web client (`client/src/utils/formatters.ts`, `client/src/components/Budget/BudgetPanel.constants.ts`), held in `Currency`:

| Rule | Behavior |
| --- | --- |
| Decimal places | 0 for JPY, KRW, VND, CLP, ISK, HUF (by Trek convention), BIF, DJF, GNF, KMF, PYG, RWF, UGX, VUV, XAF, XOF, XPF; 3 for BHD, IQD, JOD, KWD, LYD, OMR, TND; 2 otherwise |
| Decimal separator | The currency's home convention, independent of device locale — `,` for EUR, CZK, PLN, SEK, NOK, DKK, TRY, BRL, IDR, ZAR, MAD, HUF, RON, BGN, HRK, ISK, RUB, UAH, KGS, VND, CLP, COP, ARS; `.` otherwise |
| Typing | Digits plus one separator and at most the currency's decimal places; either `,` or `.` is accepted and rewritten to the currency's separator. No grouping separators or signs |
| Seeding | `initialValue` is cent-rounded and padded to the currency's decimals (`4.9` EUR → `4,90`, `500` JPY → `500`) |
| Output | `onChanged` reports a `double` (or `null` while empty), ready to send as a JSON number such as a budget item's `total_price` |
| Prefix | The currency's symbol (`€`, `$`, `¥`), falling back to its code |

`required: true` fails `Form` validation while empty. Changing `currency` on a mounted field keeps the typed number and swaps its separator; decimals the new currency doesn't allow fail validation instead of being rounded away. `Currency.codes` is Trek's selectable set; `Currency.selectableWith(saved)` appends a saved code outside it so editing an older item doesn't blank its currency. `Currency.cleanAmount` rounds to whole cents to drop float noise from uneven splits, matching the backend's money arithmetic.

These widgets do no I/O, so they behave the same offline; forms built from them write to local state first, per [offline-first.md](offline-first.md).

## App icon, splash image, and startup animation

`assets/icon/` holds three renders of Trek's actual T-mark (the geometric logo from the [web client](https://github.com/liketrek/TREK)'s `client/public/icons/icon.svg`, not a placeholder):

| File | Used by |
| --- | --- |
| `icon.png` | `flutter_launcher_icons` (see `pubspec.yaml`) — full-bleed mark + gradient background, generates the iOS/Android app icon |
| `splash.png` | `flutter_native_splash` — mark only, transparent background, composited onto a solid `#0F172A` (the icon gradient's dark end) set via `flutter_native_splash`'s `color` config — generates the native static launch image shown before Flutter starts |
| `mark.png` | [lib/app/splash_screen.dart](../lib/app/splash_screen.dart) — the same asset, animated in-app |

The source SVG uses small rounded corners (cubic bezier segments); the PNGs were rendered by parsing the path's vertices directly and filling straight-edged polygons (rounding is imperceptible at icon/splash sizes) rather than pulling in a native SVG-rasterization toolchain for one-time asset generation. Regenerate with `dart run flutter_launcher_icons` / `dart run flutter_native_splash:create` after changing the source PNGs or their config in `pubspec.yaml`.

A native launch image can only ever be static (an OS-level constraint on both iOS and Android, not a Flutter limitation) — `SplashScreen` is the animated handoff to it: a dark gradient background styled after Trek's web login screen, a twinkling star field (`CustomPainter`), and the T-mark fading and scaling in. `TrekApp` shows it for at least 1400ms (`_minSplashDuration` in [lib/app/trek_app.dart](../lib/app/trek_app.dart)) even though `AuthService.restoreSession()` alone resolves almost instantly, so the reveal animation always gets to finish.

## Global messaging

[lib/app/app_messenger.dart](../lib/app/app_messenger.dart)'s `AppMessenger` shows snackbar-based error/success/info messages from anywhere — screens and services alike — via a single `scaffoldMessengerKey` wired into `MaterialApp.router`. Use it for messages with no natural spot in the UI (a background sync failure, a completed action); form-validation errors that sit next to their field (see `LoginScreen`, `ServerSetupScreen`) should stay inline rather than move to a toast. `TripListScreen`'s logout action is the first real caller (`AppMessenger.showInfo('Logged out.')`).

## Screens

- **`ServerSetupScreen`** — collects the public server URL (required) and an optional private/LAN URL + trusted Wi-Fi network names, via `ServerConfig.validateUrl`. Writes to `ServerConfigStorage` and lets the redirect carry the user to `/login`.
- **`LoginScreen`** / **`MfaScreen`** — call `AuthService.login` / `verifyMfaLogin` directly; an `ApiException` is caught and shown inline (including `NetworkException` when offline — see [offline-first.md](offline-first.md)). Neither screen navigates on success; the router's `refreshListenable` does that.
- **`TripListScreen`** — empty state (no trip data model yet) plus a working logout action.
- **`TripDashboardScreen`** — bottom `NavigationBar` with the five sections issue #2 calls for (Days/Places/Budget/Packing/Todos), each a placeholder. The Places tab also previews every `PlaceCategory` swatch as a visual check of the design tokens.

## Deferred

Left for later slices of issue #2, noted here rather than guessed at:

- Local caching strategy (what's cached, invalidation) — belongs with [#21](https://github.com/ryanmac8/trek-native-app/issues/21)'s offline-sync mechanism.
- A currency picker over `Currency.codes`, and a combined date-range field — no screen shape to design them against yet.
- Android adaptive icon foreground/background layers — the launcher icon currently uses the simpler legacy (non-adaptive) path.
