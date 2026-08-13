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

- **Networking & auth** ([#1](https://github.com/ryanmac8/trek-native-app/issues/1)) — HTTP client, error handling, server config, secure token storage, and the login/MFA/logout flow are implemented; see [networking-auth.md](networking-auth.md). The server-setup/login UI and app-shell wiring landed as part of #2 (see below). Open: request/response models for the rest of the data model, and an authenticated (bearer-token) `ApiClient` — nothing has needed one yet.
- **State management, navigation, design system** ([#2](https://github.com/ryanmac8/trek-native-app/issues/2)) — Riverpod for state/DI, go_router for navigation (auth/server-gated redirects), a Material 3 design system (colors, typography, spacing, Trek's place category colors), a global snackbar messenger, the real Trek app icon/splash image, and an animated startup screen. See [app-shell.md](app-shell.md). Open: local caching strategy (belongs with #21) and the rest of the reusable UI kit (form fields, date/time pickers, currency input).
- **Tags** ([#6](https://github.com/ryanmac8/trek-native-app/issues/6)) — the `/tags` screen lists and creates tags offline-first against a local cache (`TagsRepository`). See [tags.md](tags.md). Open: tag edit/delete, applying/removing a tag on a place, and filtering the place pool by tag.
- **Offline-first sync mechanism** ([#21](https://github.com/ryanmac8/trek-native-app/issues/21)) — local database choice, conflict resolution strategy, and write-retry/outbox mechanism are undecided. See [offline-first.md](offline-first.md). Tags has a minimal, `shared_preferences`-backed version of this scoped to its own resource (see [tags.md](tags.md)) as a first cut; it doesn't generalize to other resources yet.

Decisions here should get filled in as those issues are worked, rather than guessed at ahead of time.
