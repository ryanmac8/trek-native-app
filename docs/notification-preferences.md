# Notification preferences

Which notifications Trek sends the signed-in user, and over which channels. This is the part of [#22 Push notifications](https://github.com/ryanmac8/trek-native-app/issues/22) ("notification preferences — which categories are enabled") that Trek's backend supports today. Trek's server has no APNs/FCM device-token registration: its delivery channels are in-app, email, webhook, ntfy, and plugin channels. Native OS push is not built.

## Pieces

| File | What it is |
| --- | --- |
| [lib/notification_preferences/notification_preferences_models.dart](../lib/notification_preferences/notification_preferences_models.dart) | `NotificationPreferencesMatrix` (the matrix response: cells, channel columns, event rows, implemented combos), `NotificationChannel` (one column), `CachedNotificationPreferences` (the server matrix, its `fetchedAt`, and unsynced `pending` cells), and `notificationEventLabel`. |
| [lib/notification_preferences/notification_preferences_api.dart](../lib/notification_preferences/notification_preferences_api.dart) | `NotificationPreferencesApi.fetch()` / `update(cells)` — transport only, no caching. |
| [lib/notification_preferences/notification_preferences_local_store.dart](../lib/notification_preferences/notification_preferences_local_store.dart) | `NotificationPreferencesLocalStore` interface + `PreferencesNotificationPreferencesLocalStore`, one JSON snapshot (pending cells included) per account scope in `shared_preferences`. |
| [lib/notification_preferences/notification_preferences_repository.dart](../lib/notification_preferences/notification_preferences_repository.dart) | `NotificationPreferencesRepository` — the offline-first front door: `cached()`, `setPreference()`, `syncPending()`, `refresh()`. |
| [lib/features/notification_preferences/notification_preferences_screen.dart](../lib/features/notification_preferences/notification_preferences_screen.dart) | `NotificationPreferencesScreen` at `/notification-preferences`, opened from the trip list's bell action. |

Providers (`notificationPreferencesApiProvider`, `notificationPreferencesLocalStoreProvider`, `notificationPreferencesCacheScopeProvider`, `notificationPreferencesRepositoryProvider`) live in [lib/app/providers.dart](../lib/app/providers.dart); the API uses the authenticated `apiClientProvider`.

## API contract

Both endpoints are on `NotificationsController` in Trek's `server/src/nest/notifications/`, JWT-guarded.

`GET /api/notifications/preferences` returns the user-scope matrix:

```jsonc
{
  "preferences": {                       // event → channel → enabled
    "trip_invite": { "inapp": true, "email": false, "webhook": true },
    "synology_session_cleared": { "inapp": true }
  },
  "channels": [                          // columns, in display order
    { "id": "inapp", "source": "builtin",
      "labelKey": "settings.notificationPreferences.inapp",
      "active": true, "configured": true },
    { "id": "webhook", "source": "builtin",
      "labelKey": "settings.notificationPreferences.webhook",
      "active": true, "configured": false },
    { "id": "plugin:matrix", "source": "plugin", "label": "Matrix chat",
      "settingsPath": "/settings/plugins/matrix",
      "active": true, "configured": true }
  ],
  "event_types": ["trip_invite", "booking_change", "…"],   // rows, in order
  "implemented_combos": {                // which channels can deliver each event
    "trip_invite": ["inapp", "email", "webhook", "ntfy"],
    "synology_session_cleared": ["inapp"]
  },
  "defaults": { "ntfyServer": null }
}
```

- Event types: `trip_invite`, `booking_change`, `trip_reminder`, `todo_due`, `vacay_invite`, `vacay_share`, `collection_invite`, `photos_shared`, `collab_message`, `packing_tagged`, `synology_session_cleared`, `plugin_notification`. The admin-only events (`version_available`, `replica_failure`) are excluded from `event_types` in the user scope. Unknown event types from a newer server are shown with a label derived from the key.
- Channel ids are `inapp`, `email`, `webhook`, `ntfy`, or `plugin:<id>`. In-app is always active. Built-in channels carry an i18n `labelKey`; plugin channels carry a literal `label`.
- `active` is the admin's per-instance switch; `configured` is whether this user has entered credentials for the channel (e.g. their own webhook URL). A channel is shown only when it is `active` and can deliver at least one event in `event_types` — the same rule as Trek's web client. An unconfigured channel still shows, marked "Not configured yet".
- Every cell defaults to enabled: the server stores only opt-out rows.

`PUT /api/notifications/preferences` takes a partial `event → channel → bool` map (`preferencesUpdateRequestSchema`, `z.record(z.string(), z.record(z.string(), z.boolean()))`). Each cell is applied independently — `true` deletes the opt-out row, `false` upserts it — and the response is the refreshed matrix. The app sends only the changed cells, so cells changed on another device are left alone. A malformed body is a 400 `{ error }`.

## Offline behavior

- The screen paints the cached snapshot first, then refreshes. If the refresh fails and a snapshot exists, it stays on screen with an "Offline — showing preferences from …" banner and a retry. With no snapshot, a `NetworkException` shows an explicit offline state with a retry; any other error shows a generic error state.
- A toggle is written to the local snapshot's `pending` cells first (`setPreference`, never touches the network), shown immediately, then pushed by `syncPending`. Pending cells are coalesced per cell (latest value wins) and persisted, so they survive an app restart. While any are pending the screen shows "N changes saved on this device, waiting to sync with your server."
- `syncPending` sends every pending cell in one `PUT` and removes a cell from `pending` only if its value is still what was sent; a cell toggled again during the request goes out in a follow-up `PUT` in the same run. Concurrent callers share one run. Local-store updates are serialized so a toggle during a sync is never lost.
- Pending cells are retried on the next `refresh()` (opening the screen, pull-to-refresh, or the banner's retry), which syncs before fetching. There is no background retry while the screen is closed.
- A `NetworkException` leaves the cells pending. A 401 also leaves them pending (the session is cleared and the router goes to login; they sync after the same account signs back in). Any other rejection drops the sent cells, so the server's value shows again, and the screen shows an error snackbar.
- Snapshots are keyed by **account scope** — the configured public server URL plus the session's user id (the JWT `id` claim, via `AuthService.currentUserId`) — so a different account or server on the same device never sees or syncs another account's preferences. Without a live session the repository neither reads nor writes the cache. A corrupt entry reads as a cache miss.
- Conflict resolution is last-write-wins per cell, which matches the server's per-cell semantics.
