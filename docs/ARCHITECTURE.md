# Architecture

## Decided

- **Framework:** Flutter (single codebase for iOS + Android).
- **Platforms:** iOS and Android only. The `linux/`, `macos/`, `windows/`, and `web/` folders `flutter create` generates by default were removed and should stay out.
- **Package:** `com.trek.trek` (org `com.trek`, project name `trek`).
- **Backend:** Trek's existing backend/API (the same one the web PWA and its MCP server talk to). This app is a new client, not a new backend.
- **Server config:** Trek is self-hosted, not a vendor-run API — there's no fixed `api.trek.app` to build against. The app points at a user-entered server URL (`ServerConfig`, see [networking-auth.md](networking-auth.md)), the same way Nextcloud/Immich clients work, rather than fixed dev/staging/prod environments.
- **Offline-first is a cross-cutting design principle, not deferred Phase 3 work.** Every feature that reads or writes trip data must be designed assuming the network may be unavailable at any point — local storage as the source of truth, local-first writes, graceful degradation. See [offline-first.md](offline-first.md) for what this means in practice. The concrete sync mechanism (local database choice, conflict resolution, retry/outbox strategy) is still undecided — that's [#21](https://github.com/ryanmac8/trek-native-app/issues/21) — but the *principle* applies now, to every feature built before #21 lands too.

## Open / not yet built

Tracked in [ROADMAP.md](ROADMAP.md), Phase 1 foundation issues:

- **Networking & auth** ([#1](https://github.com/ryanmac8/trek-native-app/issues/1)) — HTTP client, error handling, self-hosted server config, secure token storage, and the login/MFA/logout flow (verified against Trek's actual backend, which issues one JWT with no refresh — see [networking-auth.md](networking-auth.md)) are implemented. Auth already follows the offline-first principle: checking whether a session is active never requires network (see offline-first.md). Still open: server-setup/login UI (blocked on #2), full request/response models for the rest of the data model, and wiring the auth flow into the app shell.
- **State management, navigation, design system** ([#2](https://github.com/ryanmac8/trek-native-app/issues/2)) — not chosen yet. `lib/main.dart` is currently a single placeholder screen with no routing or state layer.
- **Offline-first sync mechanism** ([#21](https://github.com/ryanmac8/trek-native-app/issues/21)) — local database choice, conflict resolution strategy, and the write-retry/outbox mechanism are all undecided. Sequenced in Phase 3 on the roadmap, but per the principle above, should be pulled forward and scoped as soon as real trip data starts getting fetched/stored, rather than left until then.

Decisions here should get filled in as those issues are worked, rather than guessed at ahead of time.
