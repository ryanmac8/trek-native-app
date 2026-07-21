# Architecture

## Decided

- **Framework:** Flutter (single codebase for iOS + Android).
- **Platforms:** iOS and Android only. The `linux/`, `macos/`, `windows/`, and `web/` folders `flutter create` generates by default were removed and should stay out.
- **Package:** `com.trek.trek` (org `com.trek`, project name `trek`).
- **Backend:** Trek's existing backend/API (the same one the web PWA and its MCP server talk to). This app is a new client, not a new backend.
- **Server config:** Trek is self-hosted, not a vendor-run API. The app points at user-entered public/private server URLs (switching to the private one on trusted Wi-Fi networks) rather than fixed dev/staging/prod environments. See [networking-auth.md](networking-auth.md).
- **Offline-first:** a cross-cutting design principle, not Phase 3-only work — every feature that reads or writes trip data is designed assuming the network may be unavailable. See [offline-first.md](offline-first.md).

## Open / not yet built

Tracked in [ROADMAP.md](ROADMAP.md), Phase 1 foundation issues:

- **Networking & auth** ([#1](https://github.com/ryanmac8/trek-native-app/issues/1)) — HTTP client, error handling, server config, secure token storage, the login/MFA/logout flow, and an authenticated `ApiClient` (with sync-resilient 401 handling, not a forced logout) are implemented; see [networking-auth.md](networking-auth.md). The server-setup/login UI and app-shell wiring landed as part of #2. Open: request/response models for the rest of the data model beyond the minimal `TripsApi` read.
- **State management, navigation, design system** ([#2](https://github.com/ryanmac8/trek-native-app/issues/2)) — Riverpod for state/DI, go_router for navigation (auth/server/biometric-gated redirects), a Material 3 design system (colors, typography, spacing, Trek's place category colors), a global snackbar messenger, the real Trek app icon/splash image, and an animated startup screen. See [app-shell.md](app-shell.md). Open: local caching strategy (belongs with #21) and the rest of the reusable UI kit (form fields, date/time pickers, currency input).
- **Biometric app lock** ([#26](https://github.com/ryanmac8/trek-native-app/issues/26)) — Face ID/Touch ID/Android biometric unlock, gating re-entry to an already-authenticated session once per cold start. See [biometric-lock.md](biometric-lock.md). Open: re-lock on backgrounding/resume (only cold start is handled), and a settings toggle to opt out (needs #27).
- **Trips** ([#3](https://github.com/ryanmac8/trek-native-app/issues/3)) — list and create are built, both offline-first against a trips-scoped local cache (`TripsRepository`). See [trips.md](trips.md). Open: edit, archive/unarchive, delete, cover image, trip dashboard summary, and everything else in the data model (days, places, budget, packing, todos).
- **Offline-first sync mechanism** ([#21](https://github.com/ryanmac8/trek-native-app/issues/21)) — a general local database choice, conflict resolution strategy, and write-retry/outbox mechanism for the whole data model are still undecided. See [offline-first.md](offline-first.md). Trips has a minimal, `shared_preferences`-backed version of this scoped to just the trip list (see [trips.md](trips.md)) as a first cut; it doesn't generalize to other resources yet.

Decisions here should get filled in as those issues are worked, rather than guessed at ahead of time.
