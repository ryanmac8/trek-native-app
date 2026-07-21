# Trek (native app)

Native iOS and Android client for **Trek**, a collaborative trip-planning app (trips, itineraries, places, packing lists, budgets, and more). This project is a native alternative to the Trek PWA, built with [Flutter](https://flutter.dev) for a single codebase across both platforms.

## Status

🚧 Early scaffolding — no features implemented yet.

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (channel: stable)
- Xcode (for iOS builds/simulator)
- Android Studio + an Android SDK/emulator (for Android builds)

Check your setup:

```bash
flutter doctor
```

### Run the app

```bash
flutter pub get
flutter run
```

### Tests

```bash
flutter test
```

## Project structure

```
lib/            App source code
test/           Widget/unit tests
ios/            iOS platform project
android/        Android platform project
docs/           Documentation (roadmap, architecture)
```

## Documentation & roadmap

See [docs/](docs/) for the roadmap and architecture notes, and the [Trek MVP project board](https://github.com/users/ryanmac8/projects/1) / [issues](https://github.com/ryanmac8/trek-native-app/issues) for day-to-day tracking.

## License

AGPL-3.0 — see [LICENSE](LICENSE).
