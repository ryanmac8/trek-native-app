# Notifications

Covers the first slice of [issue #15](https://github.com/ryanmac8/trek-native-app/issues/15): the in-app notifications inbox, backed by a local cache and a pending-reads outbox. Boolean (yes/no) notification responses, deleting notifications, channel preferences, acting on a `navigate` notification's target, and pagination are not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/notifications/trek_notification.dart](../lib/notifications/trek_notification.dart) | `TrekNotification` — the model, trimmed to what the inbox renders: `id`, `type` (`simple` / `boolean` / `navigate`), the `title_key` / `title_params` and `text_key` / `text_params` pairs, `navigate_target`, `is_read`, `created_at`, and the joined `sender_username` / `sender_avatar`. `title_params` / `text_params` are parsed from a JSON string (the wire shape) or tolerated as a map; `is_read` accepts the SQLite `0` / `1`. `fromJson` / `toCacheJson` / `fromCacheJson` are the API and local-cache (de)serializers. |
| [lib/notifications/notification_text.dart](../lib/notifications/notification_text.dart) | The bundled English `notif.*` string catalog (copied from Trek's `shared/src/i18n/en/notif.ts`), `renderNotificationText(key, params)` doing `{placeholder}` substitution, and `relativeTimeLabel` for the "3m" / "2h" / "5d" list timestamps. |
| [lib/notifications/notifications_api.dart](../lib/notifications/notifications_api.dart) | `NotificationsApi` — wraps `GET /api/notifications/in-app`, `PUT /api/notifications/in-app/:id/read`, and `PUT /api/notifications/in-app/read-all`. Returns `InAppNotificationsPage` (`notifications`, `total`, `unreadCount`). |
| [lib/notifications/notifications_local_store.dart](../lib/notifications/notifications_local_store.dart) | `NotificationsLocalStore` / `PreferencesNotificationsLocalStore` — persists the cached list (`trek.notifications.cache`) and the pending-reads outbox (`trek.notifications.pending_reads`) in `shared_preferences`. |
| [lib/notifications/notifications_repository.dart](../lib/notifications/notifications_repository.dart) | `NotificationsRepository` — the offline-first front door the inbox uses instead of `NotificationsApi` directly. See below. |
| [lib/features/notifications/notifications_screen.dart](../lib/features/notifications/notifications_screen.dart) | `NotificationsScreen` — the inbox at `/notifications`, reachable from the trip list's app-bar bell. Reads from the cache first, then refreshes in the background. Each row renders the translated title, a detail line (body · relative time), an unread marker, and — when unread — marks itself read on tap. A "Mark all read" action shows while anything is unread. |

## API contract

All three endpoints are JWT-guarded (`NotificationsController`, `server/src/nest/notifications/`), so this is the app's first authenticated `ApiClient` (`apiClientProvider` in `lib/app/providers.dart`), attaching `AuthService.currentAccessToken` to every request and clearing the local session on a 401.

- **`GET /api/notifications/in-app?limit=&offset=&unread_only=`** → `{ notifications: [...], total, unread_count }`. `limit` defaults to 20 and is clamped server-side to 50. Rows are ordered `created_at` descending. This slice fetches only the first page.
- **`PUT /api/notifications/in-app/:id/read`** → `{ success: true }`, or `404 { error: 'Not found' }` when the id isn't one of the caller's notifications.
- **`PUT /api/notifications/in-app/read-all`** → `{ success: true, count }`.

Each row is the `notifications` table (`id`, `type`, `scope`, `target`, `sender_id`, `recipient_id`, `title_key`, `title_params`, `text_key`, `text_params`, the `positive_*` / `negative_*` / `navigate_*` columns, `response`, `is_read`, `created_at`) with the sender's `username` / `avatar` joined in. `title_params` / `text_params` are TEXT columns holding a JSON object string (default `'{}'`); `is_read` is an integer `0` / `1`; `created_at` is returned as a UTC ISO-8601 string.

Notification text is **not translated server-side** — `*_key` is an i18n key and `*_params` are its `{placeholder}` values. The client renders them from its bundled `notif.*` catalog; an unknown key renders as the raw key string rather than failing (matching Trek's web client). Only `simple` / `boolean` / `navigate` types exist (a DB `CHECK`); this slice renders all three the same way and ignores the boolean response actions.

Channel-preference endpoints (`GET|PUT /api/notifications/preferences`), the test-ping endpoints, `PUT /api/notifications/in-app/:id/unread`, `DELETE /api/notifications/in-app/:id`, `DELETE /api/notifications/in-app/all`, and `POST /api/notifications/in-app/:id/respond` all exist server-side but aren't wired into this client yet.

## Offline-first (`NotificationsRepository`)

Per [offline-first.md](offline-first.md), the inbox never talks to `NotificationsApi` directly — it goes through `NotificationsRepository`, which keeps the local cache as the source of truth and applies "mark read" locally before the network is involved.

**Reads:**

- **`cachedNotifications()` / `cachedUnreadCount()`** read the local store only, with the pending-reads outbox layered on top so an optimistic "mark read" stays applied across an app restart. The inbox calls this on load for an instant first paint.
- **`refreshNotifications()`** flushes any queued reads, then fetches the first page and writes it to the cache. On `NetworkException` it falls back to the cache instead of failing — only when the cache is empty does the exception propagate, so the caller can show an explicit offline state.

**Writes** (`markRead`, `markAllRead`):

- The cache is updated first and the affected id(s) are appended to the pending-reads outbox in the local store.
- The matching server call is then attempted. A `NetworkException` is swallowed — the local write already succeeded and the id stays queued.
- `_flushPendingReads()` (run at the start of every `refreshNotifications()`) retries the queue one id at a time, narrowing the persisted set as each succeeds so a mid-flush disconnect leaves the rest queued. A non-network API error (e.g. a `404` for a notification deleted server-side) counts as delivered and drops the id from the queue.

The pending-reads outbox is a minimal, single-purpose stand-in for the durable outbox the wider offline-sync work will introduce ([#21](https://github.com/ryanmac8/trek-native-app/issues/21)); it only needs to carry the one mutation this slice performs.

## What's still open

- Boolean yes/no notification responses (`POST .../:id/respond`) and the `positive_*` / `negative_*` columns.
- Marking a notification unread again, and deleting one / all.
- Acting on a `navigate` notification's `navigate_target` (most of the routes it points at don't exist in the native app yet).
- Pagination / "load more" past the first page, and a live unread badge on the trip list.
- Real-time delivery over Trek's WebSocket path, and channel-preference management.
- Localised notification text — only English `notif.*` strings are bundled, and the app has no locale system yet.
- A shared durable outbox once more mutations exist — see [offline-first.md](offline-first.md) and [#21](https://github.com/ryanmac8/trek-native-app/issues/21).
