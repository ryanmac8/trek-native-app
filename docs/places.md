# Places

Covers the place pool from [issue #5](https://github.com/ryanmac8/trek-native-app/issues/5): the Places tab of the trip dashboard, backed by a trip-scoped local cache and an outbox of local changes. Places can be listed, created, edited, and deleted. The category picker, tags, coordinates, bulk actions, search/filter, the place detail view, and importers are not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/places/place.dart](../lib/places/place.dart) | `Place` — the place model: name, description, address, category, price/currency, notes, Trek's `updated_at`, and a local-only `PlaceSyncStatus` (`synced`/`pending`/`conflict`). A negative `id` is a temporary id for a place whose create hasn't synced. `applyFields` lays a request body over a place. `PlaceCategoryRef` — the category embedded on a place (id/name/color/icon), distinct from the design system's `PlaceCategory` enum ([place_category_colors.dart](../lib/design/place_category_colors.dart)), which models fixed default-category tokens. `PlaceInput` — the form's fields, turned into a `POST` body (`toCreateJson`: non-empty fields only) or a `PUT` body (`changesFrom`: only fields that differ, cleared ones as `null`). |
| [lib/places/pending_place_op.dart](../lib/places/pending_place_op.dart) | `PendingPlaceOp` — one queued create/update/delete: target place id, request body, the `updated_at` it was based on, and (after a 409) the server's current version. |
| [lib/places/places_api.dart](../lib/places/places_api.dart) | `PlacesApi` — `listPlaces`, `createPlace`, `updatePlace` (optionally with `X-Base-Updated-At`), `deletePlace`. |
| [lib/places/places_local_store.dart](../lib/places/places_local_store.dart) | `PlacesLocalStore`/`PreferencesPlacesLocalStore` — per trip, the cached place list (`trek.places.cache.<tripId>`) and the outbox (`trek.places.pending.<tripId>`), as JSON in `shared_preferences`. |
| [lib/places/places_repository.dart](../lib/places/places_repository.dart) | `PlacesRepository` — the offline-first front door the Places tab uses instead of `PlacesApi` directly. See below. |
| [lib/features/places/place_form_screen.dart](../lib/features/places/place_form_screen.dart) | `PlaceFormScreen` — create/edit form (name, description, address, price, 3-letter currency, notes) with a delete action when editing. Pops a `PlaceFormResult`; persisting is the caller's job. |
| [lib/features/trips/trip_dashboard_screen.dart](../lib/features/trips/trip_dashboard_screen.dart) | `_PlacesTab` — the Places section of the trip dashboard. Paints from the cache, refreshes in the background, adds places via its floating button, and opens the form on a row tap (or the conflict dialog for a conflicted row). Rows show a pending icon or a conflict warning when not synced, and a `_CategoryBadge` colored from the place's real category. |

## API contract

All under `/api/trips/:tripId/places` (Trek's `PlacesController`), bearer-authenticated.

| Call | Request | Response |
| --- | --- | --- |
| `GET /` | — | `{ places: [...] }` (never a bare array) |
| `POST /` | Place fields; `name` required (non-empty) | 201 `{ place }` |
| `PUT /:id` | Any subset of place fields; optional `X-Base-Updated-At` header | `{ place }`, or 409 `{ error: 'conflict', server: {...} }` |
| `DELETE /:id` | — | `{ success: true }` |

- A place row is wide (lat/lng, website, phone, image, reservation fields, tags, ratings, provider-derived import columns — see Trek's `placeSchema`). The client models `name`, `description`, `address`, the embedded `category` projection (`id`/`name`/`color`/`icon`, `null` when unset), `price`, `currency`, `notes`, and `updated_at`.
- `PUT` is a partial update: a key absent from the body keeps its value; an explicit `null` clears `description`, `address`, `price`, and `notes`. `name` and `currency` can't be cleared — the server keeps the old value for an empty or `null` one.
- `X-Base-Updated-At` is optimistic concurrency: when present and different from the row's current `updated_at`, the server refuses the write with 409 and returns the current row under `server`. Without the header the update is unconditional.
- String limits (400 `{ error }` when exceeded): name 200, description 2000, address 500, notes 2000. No edit permission (`place_edit`) is 403 `{ error: 'No permission' }`; an unknown trip or place is 404.
- Category colors are hex strings (e.g. `#3b82f6`), matching the default categories' seed colors in Trek's backend (`server/src/db/seeds.ts`).

## Offline-first reads and writes (`PlacesRepository`)

Per [offline-first.md](offline-first.md), the cache is what the Places tab shows, and nothing the user does waits on the network.

**Reads**

- `cachedPlaces(tripId)` reads the local store only — the tab's instant first paint.
- `refreshPlaces(tripId)` replays the outbox, fetches the list, lays any still-queued changes over it, and writes the result to the cache. On `NetworkException` it returns the cache instead, unless the cache is empty, in which case the exception propagates so the tab can show an explicit offline state.

**Writes** — `createPlace`, `updatePlace`, and `deletePlace` change the cache and append to the trip's outbox; none of them touch the network.

- A created place gets a negative temporary id and `pending` status.
- An edit queues only the fields that changed, along with the place's cached `updated_at` as its base version. Further edits to a place that already has a queued create or update merge into it, so the outbox holds at most one waiting change per place.
- Deleting a place drops its queued changes; a place whose create never synced just disappears with nothing sent.

**Replay** — `syncPending(tripId)` sends the outbox oldest-first and returns a `PlaceSyncResult` (`offline`, plus user-facing `rejections`). The Places tab runs it after every change and on refresh.

| Outcome | Effect |
| --- | --- |
| Success | Op removed; the server's place replaces the local one. A create's temporary id is rewritten to the real id in the cache and in every later op. |
| `NetworkException` | Pass stops (`offline: true`); everything stays queued. |
| 401, 5xx | Pass stops; everything stays queued for the next pass. |
| 409 on an update | Op kept with the server's version attached; the place shows as `conflict`. Later ops for that place wait until it's resolved. |
| 404 | A delete counts as done. A create or update drops the place locally — it no longer exists on the server. |
| 400 / 403 | The change is dropped and reported; a refused create removes its local place, and a refused edit or delete is rolled back by re-fetching the list. |

Concurrency inside the repository:

- All reads and writes of a trip's cache and outbox are serialized, so a user edit and a sync step never overwrite each other.
- An op whose request is in flight isn't merged into. An edit made meanwhile queues behind it, and its base version is advanced to the `updated_at` the in-flight request returns, so it doesn't conflict with the app's own write.
- Overlapping `syncPending` calls share one pass, and a call during a pass makes it run once more.

**Conflicts** — `resolveConflict(tripId, placeId, keepMine:)`. Keep mine re-queues the local edit with the server's `updated_at` as its new base, so it overwrites the server's version on the next pass. Use theirs discards the local edit and shows the server's version. The Places tab offers both in a dialog when a conflicted row is tapped.

## What's still open

- The category picker and custom-category CRUD (`GET`/`POST`/`PUT`/`DELETE /api/categories`), and tags on places.
- Coordinates/map, website/phone/hours/duration/transport mode, and the place detail view (photo, Google Place link).
- Bulk update/delete (`POST .../bulk-update`, `.../bulk-delete`), search/filter, ratings, image upload, and the GPX/map/Google/Naver importers.
- The "place pool" filter — the tab shows every place in the trip, not just places not yet assigned to a day, since a day's assignments don't expose place ids client-side yet (depends on [#4](https://github.com/ryanmac8/trek-native-app/issues/4)).
- Moving the places outbox onto a shared, feature-agnostic sync mechanism once [#21](https://github.com/ryanmac8/trek-native-app/issues/21) settles on one, and clearing it on logout.
