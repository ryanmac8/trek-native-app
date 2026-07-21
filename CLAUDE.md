# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Native iOS/Android client for **Trek**, a collaborative trip-planning app, built with Flutter as an alternative to Trek's existing PWA. The project is still in early scaffolding — see [docs/ROADMAP.md](docs/ROADMAP.md) for the full feature plan (tracked as GitHub issues/milestones in this repo) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for decisions made so far.

The app targets **iOS and Android only** — the `linux/`, `macos/`, `windows/`, and `web/` platform folders that `flutter create` normally generates were deliberately removed and should not be re-added.

## Offline-first

Assume the network may be unavailable at any point. This applies to every feature that reads or writes trip data, not just the sync work tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21). Read [docs/offline-first.md](docs/offline-first.md) before implementing any such feature.

## Commands

```bash
flutter pub get              # install dependencies
flutter run                  # run on a connected device/simulator
flutter test                 # run all tests
flutter test test/widget_test.dart   # run a single test file
flutter test --plain-name "renders home page"   # run a single test by name
flutter analyze              # static analysis (must be clean before committing)
flutter build ios            # iOS build
flutter build apk            # Android build
```

## Architecture

`lib/main.dart` is still a single placeholder screen — there is no state management or navigation layer yet ([#2](https://github.com/ryanmac8/trek-native-app/issues/2)). The networking/auth foundation ([#1](https://github.com/ryanmac8/trek-native-app/issues/1)) exists under `lib/config/`, `lib/network/`, and `lib/auth/`; see [docs/networking-auth.md](docs/networking-auth.md). Both are foundational epics that other feature work depends on.

Trek's backend data model (Trip → Day → Assignment → Place, plus Accommodation, Reservation, Budget, Packing, Todo, Tags, Collaboration, Atlas, Vacay, Journey) is documented per-feature in the GitHub issues — see [docs/ROADMAP.md](docs/ROADMAP.md) for the summarized version.

## Backend reference

Trek's actual backend/frontend lives at [github.com/liketrek/TREK](https://github.com/liketrek/TREK) (self-hosted NestJS/Express server under `server/`, web PWA client under `client/`) — this is the source of truth for API contracts and should be checked, not guessed at, before implementing anything that talks to it: endpoint paths, request/response JSON shapes, auth flow, error formats, etc. (e.g. `server/src/nest/auth/` for the login/session/MFA contract). Note that Trek is self-hosted, not a single vendor-run API — there's no fixed production URL to point this app at by default.
