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

- **Networking & auth** ([#1](https://github.com/ryanmac8/trek-native-app/issues/1)) — HTTP client, error handling, server config, secure token storage, the login/MFA/logout flow, and an authenticated `ApiClient` (bearer-token injection + 401 handling via `AuthService.handleUnauthorized`) are implemented; see [networking-auth.md](networking-auth.md). The server-setup/login UI and app-shell wiring landed as part of #2 (see below). Open: request/response models for the rest of the data model, and a non-blocking "reconnect" UX for a 401 (today it just clears the session).
- **State management, navigation, design system** ([#2](https://github.com/ryanmac8/trek-native-app/issues/2)) — Riverpod for state/DI, go_router for navigation (auth/server-gated redirects), a Material 3 design system (colors, typography, spacing, Trek's place category colors), a global snackbar messenger, the real Trek app icon/splash image, and an animated startup screen. See [app-shell.md](app-shell.md). Open: local caching strategy (belongs with #21, though places now has a first, scoped-to-places cut — see below) and the rest of the reusable UI kit (form fields, date/time pickers, currency input).
- **Trips** ([#3](https://github.com/ryanmac8/trek-native-app/issues/3)) — not built on `main` yet. `TripListScreen`/`TripDashboardScreen` exist as placeholders from #2; there's no `Trip` model, API client, or local cache, so the dashboard (and the places pool below) aren't reachable from real trip data yet — only by navigating directly to a `/trips/:tripId` route.
- **Places — place pool** ([#5](https://github.com/ryanmac8/trek-native-app/issues/5)) — the trip dashboard's Places tab reads a trip's place list offline-first against a places-scoped local cache (`PlacesRepository`). See [places.md](places.md). Open: place create/edit/delete, the category picker/custom categories, filtering to just the unassigned pool (depends on #4), and everything else in the data model.
- **Offline-first sync mechanism** ([#21](https://github.com/ryanmac8/trek-native-app/issues/21)) — local database choice, conflict resolution strategy, and write-retry/outbox mechanism are undecided. See [offline-first.md](offline-first.md). Places has a minimal, `shared_preferences`-backed version of this scoped to its own resource (see [places.md](places.md)) as a first cut; it doesn't generalize to other resources yet.

Decisions here should get filled in as those issues are worked, rather than guessed at ahead of time.
