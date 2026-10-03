# CI & release builds

How the app is checked on every change and how release builds are produced. Tracked in [#29](https://github.com/ryanmac8/trek-native-app/issues/29).

## Workflows

| Workflow | Trigger | Jobs |
| --- | --- | --- |
| [`ci.yml`](../.github/workflows/ci.yml) | Every pull request, pushes to `main` | **Analyze & test** (format check, `flutter analyze`, `flutter test`), then — only if that passes — **Build Android** (`flutter build apk --debug`) and **Build iOS** (`flutter build ios --debug --no-codesign`, on a macOS runner). |
| [`release.yml`](../.github/workflows/release.yml) | Pushing a `v*` tag, or a manual run (`workflow_dispatch`) | **Resolve version**, then a signed Android app bundle and an unsigned iOS `Runner.app`, both uploaded as workflow artifacts. |

The build jobs in `ci.yml` catch native build breakage (Gradle/Kotlin, CocoaPods, Xcode) that `flutter test` can't see, such as a plugin needing a higher deployment target.

## Versioning

`pubspec.yaml`'s `version` holds the user-facing version name (e.g. `1.0.0`). Release builds override the build number with the workflow's run number (`--build-number=$GITHUB_RUN_NUMBER`), so Android `versionCode` and iOS `CFBundleVersion` increase on every release run without editing `pubspec.yaml`.

A tag-triggered release run fails if the tag doesn't equal `v` + the pubspec version name (tag `v1.2.0` requires `version: 1.2.0+…`). Manual runs skip that check.

## Android signing

[`android/app/build.gradle.kts`](../android/app/build.gradle.kts) signs the `release` build type with the upload keystore when all four credentials are available, from either source:

| `android/key.properties` | Environment variable | Meaning |
| --- | --- | --- |
| `storeFile` | `TREK_ANDROID_KEYSTORE_PATH` | Keystore path; a relative path resolves against `android/app/` |
| `storePassword` | `TREK_ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `keyAlias` | `TREK_ANDROID_KEY_ALIAS` | Key alias |
| `keyPassword` | `TREK_ANDROID_KEY_PASSWORD` | Key password |

`key.properties` values take precedence over environment variables. [`android/key.properties.example`](../android/key.properties.example) is the template; `key.properties`, `*.jks`, and `*.keystore` are gitignored.

If any credential is missing, release builds are signed with the debug key instead, so `flutter run --release` works on any machine. Google Play rejects such a build.

### Release workflow secrets

`release.yml`'s Android job reads these repository secrets and exports them as the `TREK_ANDROID_*` variables above:

| Secret | Contents |
| --- | --- |
| `TREK_ANDROID_KEYSTORE_BASE64` | The upload keystore file, base64-encoded (`base64 -i upload-keystore.jks`) |
| `TREK_ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `TREK_ANDROID_KEY_ALIAS` | Key alias |
| `TREK_ANDROID_KEY_PASSWORD` | Key password |

The job fails rather than falling back to the debug key when any secret is missing, and fails again after the build if the bundle's signer is the Android debug certificate.

## iOS

Release runs build `Runner.app` with `--no-codesign` and upload it zipped. It compiles and links the full release configuration but can't be installed on a device or uploaded to App Store Connect.

## Not yet built

- iOS code signing (certificates, provisioning profiles) and automated TestFlight upload
- Automated Google Play internal-testing upload
- Store listing assets (screenshots, descriptions, privacy label / data safety form)
- Crash reporting and analytics
