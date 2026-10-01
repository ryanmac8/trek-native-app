# Calendar sync

The device calendar is kept in sync with Trek through **subscribed ICS feeds**. Trek serves each feed as a live `.ics` document, and the device calendar re-fetches it on its own schedule. A one-time `.ics` import would go stale. The app never writes events into EventKit or CalendarContract directly. It turns a feed on or off, and hands the feed's URL to the calendar app as a subscription.

Tracked in [#24](https://github.com/ryanmac8/trek-native-app/issues/24).

## Trek's feed contract

Trek has two feeds (`server/src/nest/feeds/`):

| Feed | Token-management endpoint | Public feed URL | Contents |
| --- | --- | --- | --- |
| All trips (per user) | `/api/feed/user/token` | `/api/feed/user/<token>.ics` | Every non-archived trip the user owns or is a member of, except trips that ended more than 90 days ago |
| Single trip | `/api/trips/:tripId/feed/token` | `/api/feed/trip/<token>.ics` | That trip's itinerary |

Each token-management endpoint is JWT-guarded and supports four methods. Every one of them responds with `{ "feed_url": string | null }`:

- `GET` returns the current URL, or `null` when the feed is off.
- `POST` enables the feed. It is idempotent and returns the existing URL if there already is one.
- `PUT` rotates the token. This creates a new URL, and the old URL stops resolving.
- `DELETE` disables the feed and always returns `null`.

The returned `feed_url` is absolute. The server builds it from its `APP_URL` setting, or from the request's host when `APP_URL` is unset. The public `.ics` routes need no session: the token in the URL is the only credential. They also send refresh hints (`REFRESH-INTERVAL`/`X-PUBLISHED-TTL` of one hour).

The trip endpoints also need the `share_manage` permission, which belongs to the trip owner by default. A member without that permission gets `403 { "error": "No permission" }`, and an unknown trip gets `404 { "error": "Trip not found" }`.

## Pieces

All under `lib/calendar_feed/`:

- **`CalendarFeedScope`** (`calendar_feed.dart`): `AllTripsFeedScope` or `TripFeedScope(tripId)`. Each one maps to its token endpoint and a cache key.
- **`CalendarFeedSnapshot`**: the cached state of one feed. It holds the last `feedUrl` the server returned, at most one pending `CalendarFeedAction` (`enable`/`rotate`/`disable`), and `syncedAt`.
  - `isEnabled` gives a pending action priority over the last server state.
  - `subscribableUrl` is `null` while any action is pending. During an enable there is no URL yet, and during a rotate the cached URL is about to stop working.
- **`CalendarFeedApi`**: maps a scope plus an action onto the endpoints above.
- **`CalendarFeedStore`** / **`SecureCalendarFeedStore`**: stores snapshots in `flutter_secure_storage`, because a feed URL is a credential. Entries are keyed by account (public server URL plus user id, from `calendarFeedAccountProvider`) and by scope.
- **`CalendarFeedRepository`**: the offline-first layer that screens use (see below). A single app-wide instance (`calendarFeedRepositoryProvider`) handles every call one at a time, so a pending action is never sent twice concurrently.
- **`CalendarSubscriber`** / **`UrlLauncherCalendarSubscriber`** (`calendar_subscriber.dart`): opens the feed in the calendar app, using `url_launcher`.

`CalendarFeedScreen` (`lib/features/calendar_feed/`) is the UI. It has two routes:

- `/calendar` for the all-trips feed, opened from the trip list's app bar.
- `/trips/:tripId/calendar` for a single trip, opened from the trip dashboard's app bar.

The screen has an on/off switch, the feed link, and three buttons: **Add to calendar**, **Copy link** and **Reset link** (which rotates the token). Turning the feed off and resetting the link both ask for confirmation first, because each one breaks every existing subscription to that feed, on any device and for anyone.

## Offline behavior

- **Reads.** `readCached` never touches the network. The screen shows the cached snapshot immediately, then calls `refresh` in the background. If there is no cache and the server can't be reached, the screen shows an explicit offline state with a Retry button.
- **Writes.** `request(scope, action)` saves the action as `pending` in the store *before* it calls the server, so the action survives the app being killed while offline.
  - Disabling takes effect locally straight away: the cached URL is cleared at once.
  - Enabling and rotating need the server to mint a token. Until they sync, the feed shows as on but with no link.
  - A newer action replaces an older pending one, because each action fully determines the end state.
- **Retry.** `refresh` sends any pending action first, and plain-fetches only when nothing is pending. It runs when the screen opens, on pull-to-refresh, and from the offline banner's Retry button.
- **Failures.**
  - These failures are retryable: `NetworkException`, a 5xx response, and a 401. In each case the cached snapshot and the pending action are kept, and the screen shows an offline banner.
  - These failures are permanent: a 403, a 404, and any other 4xx response. The pending action is dropped and the cached URL is cleared. A 403 shows a "can't manage sharing" state, and any other permanent failure shows an error snackbar.

## Subscribing on each platform

`UrlLauncherCalendarSubscriber` first opens the feed as `webcal://…`, which is the same URL with the scheme changed. iOS Calendar handles `webcal://` natively and asks the user to confirm the subscription.

On Android there is often no `webcal://` handler. In that case the app falls back to Google Calendar's add-by-URL link, `https://calendar.google.com/calendar/render?cid=webcal://…`. Google fetches the feed from its own servers, so this fallback only works when the Trek server is publicly reachable.

If neither link opens, the app copies the feed link to the clipboard so the user can add it by hand. `AndroidManifest.xml` declares `<queries>` for `VIEW` intents on `webcal` and `https`, which makes those handlers visible to the app on Android 11+.
