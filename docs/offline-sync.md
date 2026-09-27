# Offline Sync (Outbox & Sync Engine)

The shared write path behind the [offline-first](offline-first.md) principle. A feature applies a change to its own local cache first, then queues it in the **outbox**. The **sync engine** pushes queued writes to the server in the background, in order, and retries until each one lands or the server refuses it. Tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21).

The layer is feature-agnostic. It doesn't know about todos, packing items, or any other entity. Each feature registers **sync handlers** that know how to push its own writes.

## Pieces (`lib/sync/`)

| Piece | Role |
| --- | --- |
| `PendingWrite` | One queued mutation: `id`, `kind` (which handler pushes it, e.g. `todo.update`), a JSON-safe `payload`, optional `coalesceKey`, `createdAt`, `attempts`, and `lastError`. |
| `Outbox` | FIFO queue of `PendingWrite`s. Every change is serialized and persisted before its future completes. `changes` emits the pending count after each change. |
| `OutboxStore` / `PreferencesOutboxStore` | Durable storage for the queue: one JSON list in `shared_preferences` under `trek.sync.outbox`, so queued writes survive the app being killed. A corrupt value reads as an empty queue. |
| `SyncHandler` | Implemented per feature. `push(write)` sends the write through `ApiClient` and reconciles the feature's cache with the response. `onRejected(write, error)` rolls back the optimistic local change when the server refuses the write. |
| `SyncPolicy` | Classifies push failures and computes retry backoff. |
| `SyncEngine` | Drains the outbox through the registered handlers and publishes `SyncStatus` and `SyncRejection`s. |
| `SyncStatus` | `phase`, `pendingCount`, `lastSyncedAt`, and `nextRetryAt`. |

## Queueing writes

`Outbox.enqueue(kind, payload, {coalesceKey, replace})` appends a write.

When `coalesceKey` matches a queued write of the same `kind`, the two collapse into the earlier write's slot instead:
- By default, the new payload's fields are merged over the queued one, so the latest value wins per field.
- With `replace: true`, the new payload replaces the queued one outright. This fits whole-value operations such as a list reorder.

Trek's update endpoints apply partial bodies (unset fields keep their stored value, e.g. `COALESCE(?, name)` in the todo service), so a merged per-field payload is a valid request body.

A write that is currently being pushed is never merged into, because its payload is already on the wire. A change made during the push is queued as a separate write behind it.

`Outbox.removeWhere` drops queued writes. A repository uses it, for example, when an item created offline is deleted before its create ever synced, so there is nothing left to tell the server.

## Draining

`SyncEngine.drain()` pushes writes oldest-first. It stops at the first write that fails for any reason other than a rejection, so a later write never overtakes an earlier write to the same entity. Concurrent `drain()` calls share one run, and the run makes one more pass if new writes arrived during it.

Drains are triggered by:
- `start()`, run once from `TrekApp` after session restore. It never blocks startup.
- A new write being enqueued, unless a retry is already scheduled or the engine is waiting for a login.
- The app returning to the foreground (`AppLifecycleListener.onResume` in `TrekApp`).
- A successful login (`syncEngineProvider` listens to `AuthService.isAuthenticated`).
- The scheduled backoff retry.
- Tapping the `SyncStatusIndicator`.

## Failure handling

| Failure | Classified as | Effect |
| --- | --- | --- |
| No HTTP response (`NetworkException`) | `offline` | Write kept. Drain stops. Retry scheduled with backoff. Doesn't count as an attempt. |
| 401 (`UnauthorizedException`) | `unauthorized` | Write kept. Drain stops. No timer: the queue waits for the next login, resume, or manual retry. |
| 408, 429, 5xx, or a non-API error thrown by a handler | `transient` | Write kept with `attempts + 1` and `lastError`. Drain stops. Retry scheduled with backoff. On reaching `maxAttempts` (default 8), the write is treated as rejected. |
| Any other 4xx (400/422 validation, 403, 404, 409) | `rejected` | Write dropped. The handler's `onRejected` runs. `SyncEngine.rejections` emits. The drain continues with the next write. |

A write whose `kind` has no registered handler is rejected with a `StateError`, so it can't block the queue.

Backoff starts at 2 seconds and doubles with each consecutive failed drain, up to 5 minutes. A successful drain resets it.

`TrekApp` listens to `rejections` and shows each one with `AppMessenger.showError`.

## Conflicts

Trek's trip-data endpoints carry no revision or version field. The server applies whatever arrives last. The client-side rules are:
- **Per-field last-write-wins** within the device, through coalesced partial payloads.
- **FIFO ordering**, so a device's own writes reach the server in the order they were made.
- **Server refusal wins over local state.** A rejected write is rolled back by its feature's `onRejected` rather than retried.

Handling 404 on a delete is left to each handler. Treating "already gone" as success means catching that `ServerException` inside `push`.

## Riverpod wiring (`lib/app/providers.dart`)

| Provider | Provides |
| --- | --- |
| `outboxStoreProvider` | `PreferencesOutboxStore` |
| `outboxProvider` | The app's single `Outbox` |
| `syncHandlersProvider` | `Map<String, SyncHandler>` keyed by `PendingWrite.kind`. Empty until a feature registers handlers. |
| `syncEngineProvider` | The `SyncEngine`. It also drains on login. |
| `syncStatusProvider` | `StreamProvider<SyncStatus>`: the current status, then every change |

## Status indicator

`SyncStatusIndicator` (`lib/features/sync/`) is an app-bar action on the trip list. It is hidden when the queue is empty and idle. Otherwise it shows an icon for the phase (sync, `cloud_off`, `cloud_sync`, `sync_problem`, or `cloud_upload` for pending but not yet attempted), with a badge showing the pending count. Its tooltip comes from `describeSyncStatus`. Tapping it triggers a drain and shows that description as a snackbar.

## Not covered by this layer

- The outbox is one app-wide queue, not scoped per server or account. Queued writes stay queued across logout and are pushed with whichever session is active next.
- Offline is detected from failed requests, not from an OS connectivity listener. Reconnection is noticed at the next backoff retry, app resume, or manual tap.
- Local-id → server-id remapping is up to each feature's handler: it reads the current id mapping from its local store at push time.
- Realtime updates from other collaborators (Trek's websocket `realtime` module) aren't consumed. Remote changes arrive through each feature's normal refresh.
