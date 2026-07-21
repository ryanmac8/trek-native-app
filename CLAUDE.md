# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Native iOS/Android client for **Trek**, a collaborative trip-planning app, built with Flutter as an alternative to Trek's existing PWA. The project is still in early scaffolding — see [docs/ROADMAP.md](docs/ROADMAP.md) for the full feature plan (tracked as GitHub issues/milestones in this repo) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for decisions made so far.

The app targets **iOS and Android only** — the `linux/`, `macos/`, `windows/`, and `web/` platform folders that `flutter create` normally generates were deliberately removed and should not be re-added.

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

The codebase currently consists of a single entry point, [lib/main.dart](lib/main.dart) — there is no state management, networking, or navigation layer yet. Those are tracked as foundational epics (issues [#1](https://github.com/ryanmac8/trek-native-app/issues/1) and [#2](https://github.com/ryanmac8/trek-native-app/issues/2)) and should be established before feature work builds on top of them, since every other epic depends on them.

Trek's backend data model (Trip → Day → Assignment → Place, plus Accommodation, Reservation, Budget, Packing, Todo, Tags, Collaboration, Atlas, Vacay, Journey) is documented per-feature in the GitHub issues — see [docs/ROADMAP.md](docs/ROADMAP.md) for the summarized version.
