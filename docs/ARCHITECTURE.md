# Architecture

## Decided

- **Framework:** Flutter (single codebase for iOS + Android).
- **Platforms:** iOS and Android only. The `linux/`, `macos/`, `windows/`, and `web/` folders `flutter create` generates by default were removed and should stay out.
- **Package:** `com.trek.trek` (org `com.trek`, project name `trek`).
- **Backend:** Trek's existing backend/API (the same one the web PWA and its MCP server talk to). This app is a new client, not a new backend.
- **Server config:** Trek is self-hosted, not a vendor-run API. The app points at user-entered public/private server URLs (switching to the private one on trusted Wi-Fi networks) rather than fixed dev/staging/prod environments. See [server-config.md](server-config.md).
- **Offline-first:** a cross-cutting design principle, not Phase 3-only work — every feature that reads or writes trip data is designed assuming the network may be unavailable. See [offline-first.md](offline-first.md).
- **Authentication:** TOTP-based MFA using 6-digit codes, implemented via the `totp` package for token generation and validation. Sessions are persisted with secure storage and expire based on server-side token lifetimes. See [auth.md](auth.md).
- **Weather integration:** Integrated into the transit flow — when users search for transit routes, they can optionally view weather conditions at their current location and at the destination (cached locally). See [weather.md](weather.md).

## Open / not yet built

Tracked in [ROADMAP.md](ROADMAP.md), Phase 1 foundation issues:

- **State management, navigation, design system** (#2) — Riverpod for state/DI, go_router for navigation (auth/server-gated redirects), a Material 3 design system (colors, typography, spacing, Trek's place category colors), a global snackbar messenger, the real Trek app icon/splash image, and an animated startup screen. See [app-shell.md](app-shell.md). Open: local caching strategy (belongs with #21) and the rest of the reusable UI kit (form fields, date/time pickers, currency input).
- **Local caching strategy** (#21) — every offline-first feature uses a local cache-first pattern with a background sync mechanism to fetch from the server when available. The cache uses `shared_preferences` for simple JSON storage.
- **Offline-first sync mechanism** — local database choice, conflict resolution strategy, and write-retry/outbox mechanism are undecided. Weather ships a minimal, feature-scoped `shared_preferences` result cache as a stand-in.

## Feature slices landed on top of the foundation

- **Account** (#22) — CRUD operations for user account management including profile editing, password change, and notification preferences. Implements preferences sync to the server.
- **Trips** (#3) — The core domain. Trip CRUD, trip dashboard with Days/Places/Budget/Packing/Todos tabs, trip sharing via link, and full offline-first sync for all trip data.
- **Transit & airport search** (#12) — Public transit stop search, route planning between stops, and airport lookup against `GET /api/transit/geocode`, `GET /api/transit/plan`, and `GET /api/airports/search`. Reads go through an offline-first `TransitRepository` that caches results locally and falls back to cache on network failure.
- **Weather** (#16) — Current conditions and multi-day forecast for a location, integrated into the transit flow. Caches results locally and uses a background sync strategy.
- **Notifications** (#15) — In-app notification inbox with offline support. Notifications are cached locally first, then synced from the server in the background with automatic retry on failure.
