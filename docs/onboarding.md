# Onboarding

First-run experience for a fresh install ([issue #28](https://github.com/ryanmac8/trek-native-app/issues/28)). Logging in with an existing Trek account is the existing server-setup → login flow (see [networking-auth.md](networking-auth.md) and [app-shell.md](app-shell.md)); this page covers what runs before it.

## Welcome screens

`WelcomeScreen` ([lib/features/onboarding/welcome_screen.dart](../lib/features/onboarding/welcome_screen.dart)), at `/welcome`, is a swipeable `PageView` over `welcomePages`:

| # | Title | Covers |
| --- | --- | --- |
| 1 | Your trips. Your plan. | What Trek is (shows the app icon) — the title is Trek's web login tagline |
| 2 | Plan day by day | Places pool → day-by-day itinerary, with accommodations, reservations, notes |
| 3 | Plan together | Collaborators, shared budget, packing lists, todos |
| 4 | Your server, your data | Trek is self-hosted; the next step is connecting to a server and logging in |

A page indicator tracks the current page. **Next** advances; on the last page it becomes **Get started**. **Skip** (top right, hidden on the last page) is available on every other page. Both **Get started** and **Skip** call `OnboardingStorage.markWelcomeSeen()` and go to `/server-setup`.

## When it's shown

The router ([lib/app/router.dart](../lib/app/router.dart)) consults `OnboardingStorage.hasSeenWelcome()` only while no server is configured:

| Server configured? | Welcome seen? | Redirect |
| --- | --- | --- |
| No | No | `/welcome` |
| No | Yes | `/server-setup` |
| Yes | — | Normal auth gating (`/login` or the requested route); `/welcome` itself redirects to `/trips` when signed in |

Because a configured server short-circuits the check, an install that already had a server before this screen existed never sees it, and neither does a user who logs out.

## Persistence

`OnboardingStorage` ([lib/onboarding/onboarding_storage.dart](../lib/onboarding/onboarding_storage.dart)) is exposed as `onboardingStorageProvider`. `PreferencesOnboardingStorage` stores a single bool, `trek.onboarding.welcome_seen`, in `shared_preferences`. It is device-local and never sent to the Trek server.

The interface never throws, because the welcome screens are optional:

- A failed read is reported as "seen", so the user goes straight to server setup.
- `markWelcomeSeen()` sets an in-memory flag before it attempts the write, so a failed write cannot send the user back to `/welcome` later in the same session.

The whole flow is local and makes no network requests, so it behaves the same online and offline.
