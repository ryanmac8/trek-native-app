# Home-screen widgets

Tracking issue: [#23](https://github.com/ryanmac8/trek-native-app/issues/23).

One widget exists so far: **Next trip**, on Android. It shows the signed-in account's next trip with a countdown ("In 33 days", "Starts tomorrow"), or the current day of a trip in progress ("Day 3 of 5"). Tapping it opens the app.

## Data contract

The widget is built from `GET /api/trips` (JWT-guarded), which returns `{ trips: [...] }` — the account's non-archived trips, owned or shared, newest first. Each row is a full trip record; the widget reads only `id`, `title`, `start_date`, and `end_date`. Dates are plain `YYYY-MM-DD` strings with no time zone, and any trip may be undated.

## Which trip is shown

`nextTripCandidates` (`lib/home_widgets/widget_trip.dart`) reduces the trip list to the trips still relevant on a given day: every dated trip whose last day (end date, or start date if it has none) is today or later, sorted by start date, then id — at most five.

The native widget shows the first candidate whose last day is not yet in the past, against the device's **local** date. Trips already running always started before the ones still ahead, so this order matches Trek's own "active trip" choice (`TripsService.activeTrip` on the server: the trip running today, else the next to start) on every later day too. That's why the app publishes a short list rather than one trip: when a trip ends while the app hasn't run, the widget moves on to the next one by itself.

The countdown is counted in whole calendar days from the local date:

| Situation | Shown |
| --- | --- |
| No data published (signed out, or the app hasn't run since install) | "Open Trek to sign in" |
| Signed in, no candidate left | "No upcoming trips" |
| Starts tomorrow | "Starts tomorrow" |
| Starts in *n* ≥ 2 days | "In *n* days" |
| Running, with an end date | "Day *x* of *y*" |
| Running, no end date (start date is today) | "Day 1" |

## Pieces

- **`WidgetTripApi`** — `GET /api/trips` over the authenticated `apiClientProvider`.
- **`WidgetTripStore`** / `PreferencesWidgetTripStore` — the last fetched trip list as JSON in `shared_preferences`, keyed by account scope (public server URL + user id, from `homeWidgetCacheScopeProvider`), so a different account on the same device never publishes the previous one's trips.
- **`HomeWidgetPublisher`** / `PluginHomeWidgetPublisher` — writes the candidate list through [`home_widget`](https://pub.dev/packages/home_widget) and asks the OS to redraw the widget. A no-op on platforms without a widget (currently everything but Android).
- **`NextTripWidgetSync`** — the offline-first refresh (below). One app-wide instance (`nextTripWidgetSyncProvider`); overlapping calls share one in-flight refresh.
- **`HomeWidgetRefresher`** — a UI-less widget wrapping the router in `TrekApp`. Refreshes when mounted with a live session, when a session starts, and when the app returns to the foreground; clears the widget when the session ends. Failures are logged, never shown.

## Offline behavior

`NextTripWidgetSync.refresh()`:

1. With no session, clears the widget and doesn't touch the network.
2. Republishes the cached trip list straight away, recomputing the candidates against today's date — so a refresh while offline still moves the countdown along.
3. Fetches `GET /api/trips`. On success, caches and republishes the fresh list.
   - A `NetworkException` or server error keeps the cached publish; with nothing cached, the widget is left as it was.
   - An `UnauthorizedException` means the session is gone (the shared client has already cleared it), so the widget is cleared.

Signing out clears the widget but keeps the cached list, so signing back into the same account republishes it without a connection.

Between app launches the native widget redraws itself hourly (`updatePeriodMillis` in `next_trip_widget_info.xml`), recomputing the countdown from the published list and the local date — no app process or network needed.

## Android implementation

- `android/app/src/main/kotlin/com/trek/trek/NextTripWidgetProvider.kt` — a `HomeWidgetProvider` that reads the published list from `home_widget`'s shared preferences (key `next_trip.candidates`, a JSON array of `{id, title, start_date, end_date}`) and binds `res/layout/next_trip_widget.xml`.
- `NextTripWidgetContent.kt` — the candidate choice and day arithmetic, free of Android UI types, with JVM unit tests in `android/app/src/test/`.
- Registered as a `<receiver>` in `AndroidManifest.xml`; sizing and update period in `res/xml/next_trip_widget_info.xml`; strings in `res/values/strings.xml`.

## Not built yet

- **iOS.** A WidgetKit extension target plus an App Group shared between it and the app (which `home_widget` needs to write to — `HomeWidget.setAppGroupId`). Until then the publisher does nothing on iOS.
- **"Today's itinerary" widget** for an active trip — needs the day/assignment data model (#4).
- **Widget configuration** (picking which trip to show).
- **Opening the shown trip** from a tap, rather than just the app — needs the trip routes from #3.
