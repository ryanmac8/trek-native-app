# Todos

Covers the list + create + check/uncheck slice of [issue #9](https://github.com/ryanmac8/trek-native-app/issues/9): the Todos tab of the trip dashboard, backed by a trip-scoped local cache. Delete/reorder, due dates, description, assignment, priority, and category assignees are not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/todos/todo_item.dart](../lib/todos/todo_item.dart) | `TodoItem` — the todo item model, trimmed to what the list row renders (name, category, checked state). `id` is `null` exactly when the item was created locally and hasn't been confirmed by the server yet (`isPending`); `localId` is a client-generated key that survives that transition. `pendingChecked` is the equivalent bookkeeping for a checked/unchecked toggle that hasn't been confirmed yet. `fromJson`/`toCacheJson`/`fromCacheJson` are the API and local-cache (de)serializers, respectively; `copyWithChecked` produces the toggled copy `TodoRepository.toggleChecked` writes to the cache. |
| [lib/todos/todo_api.dart](../lib/todos/todo_api.dart) | `TodoApi` — thin wrapper around `GET /api/trips/:tripId/todo`, `POST /api/trips/:tripId/todo`, and the `checked` slice of `PUT /api/trips/:tripId/todo/:id`. |
| [lib/todos/todo_local_store.dart](../lib/todos/todo_local_store.dart) | `TodoLocalStore`/`PreferencesTodoLocalStore` — persists each trip's cached todo item list as JSON in `shared_preferences`, keyed per trip id so multiple trips' todo lists cache independently, the same shape as `PackingLocalStore`. |
| [lib/todos/todo_repository.dart](../lib/todos/todo_repository.dart) | `TodoRepository` — the offline-first front door the Todos tab uses instead of `TodoApi` directly. See below. |
| [lib/features/trips/trip_dashboard_screen.dart](../lib/features/trips/trip_dashboard_screen.dart) | `_TodosTab` — the Todos section of the trip dashboard's bottom-tab shell. Reads from the cache first, then refreshes from the network in the background. A FAB opens a dialog for the item's name and category, and creates it optimistically. Tapping a synced row toggles its checked state the same way; a still-pending row isn't tappable. |

## API contract

`GET /api/trips/:tripId/todo` returns `{ items: [...] }` (never a bare array), confirmed against Trek's actual `TodoController`/`todoService.listItems` (`server/src/nest/todo/`, `server/src/services/todoService.ts`). Note the route is singular `todo`, not `todos`. Each server row also carries `due_date`, `description`, `assigned_user_id`, `priority`, and `sort_order` — only `name`, `category`, and `checked` are modeled client-side so far.

`POST /api/trips/:tripId/todo` takes `{ name, category?, due_date?, description?, assigned_user_id?, priority? }` and returns `{ item }` (201). Only `name` is required — a missing `name` is rejected with `400 { error: 'Item name is required' }`. `due_date`, `description`, `assigned_user_id`, and `priority` are accepted server-side but this slice doesn't send them.

`PUT /api/trips/:tripId/todo/:id` takes any subset of `{ name, checked, category, due_date, description, assigned_user_id, priority }` and returns `{ item }` (200); a missing item is `404 { error: 'Item not found' }`. This client only ever sends `{ checked }`.

Delete and reorder (`DELETE .../:id`, `PUT .../reorder`) and category assignees (`GET`/`PUT .../category-assignees*`) all exist server-side but aren't implemented in this client yet.

## Offline-first read/write (`TodoRepository`)

Per [offline-first.md](offline-first.md), the Todos tab never talks to `TodoApi` directly — it goes through `TodoRepository`, which keeps the local cache as the source of truth for what's shown. Trip-scoped like `PackingRepository`, with the same pending-write shape:

- **`cachedItems(tripId)`** reads the local store only. The Todos tab calls this on load for an instant first paint before the network is involved at all.
- **`refreshItems(tripId)`** retries any not-yet-synced items — offline creates and offline toggles alike — then fetches the real list. A toggle still queued after its retry (still offline) overrides the corresponding item in the freshly-fetched server list, since that list would otherwise carry the stale pre-toggle value. On `NetworkException` (from the retries or the list call) it falls back to returning the cache instead of failing — only when the cache is empty does the exception propagate, so the caller can show an explicit offline state.
- **`createItem(tripId, ...)`** writes an optimistic `TodoItem` to the cache immediately (`id: null`, so `isPending` is `true`) before attempting the network call. If the create can't reach the server, the pending item stays queued in the cache rather than being lost, and the next `refreshItems()` call (screen load, pull-to-refresh) retries it. A genuine rejection (validation, permissions, a 5xx) instead rolls back the optimistic write and rethrows.
- **`toggleChecked(tripId, item)`** flips `item.checked` in the cache immediately (`pendingChecked: true`) before attempting the network call, the same optimistic-then-reconcile shape as `createItem`. If the update can't reach the server, the flipped value stays queued in the cache and the next `refreshItems()` call retries it. A genuine rejection instead rolls the cache back to the pre-toggle item and rethrows. Only a synced item (`!isPending`) can be toggled — a still-pending create has no server id yet to send the update to.

The Todos tab renders a still-pending (unsynced create) item with a "Syncing…" subtitle and a sync icon instead of its usual checked/unchecked icon, and doesn't respond to taps on it.

## What's still open

- Item delete/reorder (the rest of `TodoApi`/`TodoRepository` for issue #9).
- Due dates, description, and priority — surfaced server-side but not modeled client-side yet.
- Assignment (`assigned_user_id`) and category assignees — the collaborative-todo scope of issue #9.
- A category picker in the create dialog (free text for now).
- A local write queue for the rest of the mutations, once they exist — see docs/offline-first.md's note on conflicts and the durable outbox tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21).
