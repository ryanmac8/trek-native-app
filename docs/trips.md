# Trips

Covers the read (`TripListScreen`), create (`CreateTripScreen`), edit (`EditTripScreen`), archive/unarchive, and delete slices of [issue #3](https://github.com/ryanmac8/trek-native-app/issues/3), plus the local cache that backs all of them — a minimal, trips-scoped stand-in for the full local-persistence mechanism [#21](https://github.com/ryanmac8/trek-native-app/issues/21) will decide on for the rest of the data model. Cover image upload, the "include archived" list toggle, and the trip dashboard summary are not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/trips/trip.dart](../lib/trips/trip.dart) | `Trip` — the trip model. `id` is `null` exactly when the trip was created locally and hasn't been confirmed by the server yet (`isPending`); `localId` is a client-generated key that survives that transition. `hasPendingEdit`/`hasPendingArchiveSync` mark a synced trip with a local edit/archive toggle not yet confirmed by the server. `fromJson`/`toCacheJson`/`fromCacheJson` are the API and local-cache (de)serializers, respectively. |
| [lib/trips/trips_api.dart](../lib/trips/trips_api.dart) | `TripsApi` — thin wrapper around `GET /api/trips`, `POST /api/trips`, `PUT /api/trips/:id` (`updateTrip`/`archiveTrip`), and `DELETE /api/trips/:id`. |
| [lib/trips/trips_local_store.dart](../lib/trips/trips_local_store.dart) | `TripsLocalStore`/`PreferencesTripsLocalStore` — persists the cached trip list, plus a set of trip ids with a delete still queued to sync, as JSON in `shared_preferences` (plain storage; nothing here is a secret). |
| [lib/trips/trips_repository.dart](../lib/trips/trips_repository.dart) | `TripsRepository` — the offline-first front door screens use instead of `TripsApi` directly. See below. |
| [lib/features/trips/trip_list_screen.dart](../lib/features/trips/trip_list_screen.dart) | `TripListScreen` — the `/trips` route. Reads from the cache first, then refreshes from the network in the background. |
| [lib/features/trips/create_trip_screen.dart](../lib/features/trips/create_trip_screen.dart) | `CreateTripScreen` — the `/trips/new` route. A form for title (required), description, start/end date, and currency. |
| [lib/features/trips/edit_trip_screen.dart](../lib/features/trips/edit_trip_screen.dart) | `EditTripScreen` — the `/trips/:tripId/edit` route. The same form as create, prefilled, saving via `TripsRepository.editTrip`. |
| [lib/features/trips/trip_dashboard_screen.dart](../lib/features/trips/trip_dashboard_screen.dart) | Its app bar shows the trip's real title (read from the local cache) and, once that trip is loaded, a menu for Edit / Archive‑or‑Unarchive / Delete. |

## API contract

`GET /api/trips` returns `{ trips: [...] }` (never a bare array) and, by default, excludes archived trips — the server's `archived` query param (`0`/`1`) controls that, but the client doesn't send it yet (see "What's still open"). `POST /api/trips` takes `{ title, description?, start_date?, end_date?, currency?, reminder_days?, day_count? }` and returns `{ trip }`. Only `title` is required — the server infers a missing end date as 6 days after the start date (and vice versa), and auto-generates the trip's `Day` records from the resulting date range, so the client doesn't replicate either of those. Trip currency defaults to `EUR` server-side when omitted. Dates are `YYYY-MM-DD` strings.

Each trip in a list/create/update response also carries `day_count` and `place_count` (aggregate counts, not the records themselves — those are issues [#4](https://github.com/ryanmac8/trek-native-app/issues/4)/[#5](https://github.com/ryanmac8/trek-native-app/issues/5)) and `is_archived`, which arrives as a SQLite integer (`0`/`1`), not a JSON boolean.

`PUT /api/trips/:id` is a partial update — only the fields present in the body are considered a write, and the server checks a different permission depending on which: `title`/`description`/`start_date`/`end_date`/`currency`/`reminder_days`/`day_count` require `trip_edit`, `is_archived` requires `trip_archive`, and `cover_image` requires `trip_cover_upload`. Because of that, `TripsApi.updateTrip` (the metadata edit) and `TripsApi.archiveTrip` (the archive toggle) always send disjoint field sets — a collaborator who can archive a trip but not edit its metadata (or vice versa) would otherwise get a spurious 403. `DELETE /api/trips/:id` returns `{ success: true }`.

## Offline-first read/write (`TripsRepository`)

Per [offline-first.md](offline-first.md), the trip screens never talk to `TripsApi` directly — they go through `TripsRepository`, which keeps the local cache as the source of truth for what's shown:

- **`cachedTrips()`** reads the local store only. `TripListScreen` calls this on load for an instant first paint before the network is involved at all.
- **`refreshTrips()`** retries any pending (offline-created) trips, any trip with a queued edit or archive toggle, and any queued delete, then fetches the real list. On `NetworkException` it falls back to returning the cache instead of failing — only when the cache is empty does the exception propagate, so the caller can show an explicit offline state. A cached trip with none of `isPending`/`hasPendingEdit`/`hasPendingArchiveSync` set that's simply absent from the server's list is treated as legitimately archived or deleted, not re-added — the one exception is a trip whose create synced moments earlier in the same `refreshTrips()` call, which is kept for that one refresh in case the list call raced the create.
- **`createTrip()`** writes an optimistic `Trip` to the cache immediately (`id: null`, so `isPending` is `true`) before attempting the network call. If the create can't reach the server, the pending trip stays queued in the cache rather than being lost, and the next `refreshTrips()` call (screen load, pull-to-refresh) retries it. A genuine rejection (validation, permissions, a 5xx) instead rolls back the optimistic write and rethrows, so the form can show the error inline.
- **`editTrip()`**/**`setArchived()`** apply the change to the cached trip immediately, flagging it (`hasPendingEdit`/`hasPendingArchiveSync`) until the server confirms it. A `NetworkException` leaves the change applied locally, flagged for the next `refreshTrips()` to retry; a genuine rejection rolls the trip back to its previous cached state and rethrows.
- **`deleteTrip()`** removes the trip from the cache immediately. If the `DELETE` call can't reach the server, the id is queued in `TripsLocalStore`'s pending-deletes set and retried by the next `refreshTrips()`; a genuine rejection restores the trip to the cache and rethrows.

`TripListScreen` renders a still-pending (offline-created) trip with a "Syncing…" subtitle and a static sync icon instead of the usual chevron; tapping it is a no-op, since there's no server id yet to navigate to.

## Upcoming / Past tabs

A bottom `NavigationBar` on `TripListScreen` splits the (already-loaded) trip list into "Upcoming Trips" and "Past Trips", always defaulting to Upcoming. A trip is "past" only when it has an `endDate` that's before today — a trip with no end date (undated, or a still-`isPending` trip that hasn't synced its dates yet) counts as upcoming, since the absence of an end date reads as "still being planned," not "already over." This is a client-side filter over the same in-memory list, not a separate fetch or cache partition.

Within each tab, trips are sorted: Upcoming by soonest `startDate` first (an undated trip has nothing to compare, so it sorts after every dated one); Past by most recently ended first, oldest last.

## Archiving and the trip list

Since the client's `listTrips()` doesn't request archived trips, archiving one (from the dashboard's menu) removes it from `TripListScreen` as soon as the archive syncs and the list next refreshes — there's no "include archived" toggle yet to see or unarchive it afterward. Unarchiving only works from within a still-open dashboard for that trip in the same session; this is a known, intentionally-deferred gap until the toggle (still unchecked on issue #3) is built.

## What's still open

- Cover image upload, the trip dashboard summary, and an "include archived trips" toggle on `TripListScreen` (which is also the only way to reach an archived trip's dashboard to unarchive it — see above).
- A shared local-persistence/sync mechanism for the rest of the data model (issue #21) — this cache is deliberately scoped to trips only, not a general pattern yet.
- Conflict resolution for a trip edited on two devices while offline — each mutation (edit, archive, delete) is tracked independently, but there's no merge strategy yet for two conflicting edits made offline on different devices.
