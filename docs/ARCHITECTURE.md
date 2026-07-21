# Architecture

## Decided

- **Framework:** Flutter (single codebase for iOS + Android).
- **Platforms:** iOS and Android only. The `linux/`, `macos/`, `windows/`, and `web/` folders `flutter create` generates by default were removed and should stay out.
- **Package:** `com.trek.trek` (org `com.trek`, project name `trek`).
- **Backend:** Trek's existing backend/API (the same one the web PWA and its MCP server talk to). This app is a new client, not a new backend.

## Open / not yet built

Tracked in [ROADMAP.md](ROADMAP.md), Phase 1 foundation issues:

- **Networking & auth** ([#1](https://github.com/ryanmac8/trek-native-app/issues/1)) — HTTP client, token storage, session handling. Not started.
- **State management, navigation, design system** ([#2](https://github.com/ryanmac8/trek-native-app/issues/2)) — not chosen yet. `lib/main.dart` is currently a single placeholder screen with no routing or state layer.
- **Offline-first sync** ([#21](https://github.com/ryanmac8/trek-native-app/issues/21)) — local persistence strategy is undecided; this is the main technical reason to build native instead of continuing to use the PWA, so it should be scoped early even though it's sequenced in Phase 3.

Decisions here should get filled in as those issues are worked, rather than guessed at ahead of time.
