# Trips

Covers the read (`TripListScreen`) and create (`CreateTripScreen`) slices of [issue #3](https://github.com/ryanmac8/trek-native-app/issues/3), plus the local cache that backs both — a minimal, trips-scoped stand-in for the full local-persistence mechanism [#21](https://github.com/ryanmac8/trek-native-app/issues/21) will decide on for the rest of the data model. Edit, archive, delete, cover image, and the trip dashboard summary are not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/trips/trip.dart](../lib/trips/trip.dart) | `Trip` — the trip model. `id` is `null` exactly when the trip was created locally and hasn't been confirmed by the server yet (`isPending`); `localId` is a client-generated key that survives that transition. `fromJson`/`toCacheJson`/`fromCacheJson` are the API and local-cache (de)serializers, respectively. |
| [lib/trips/trips_api.dart](../lib/trips/trips_api.dart) | `TripsApi` — thin wrapper around `GET /api/trips` and `POST /api/trips`. |
| [lib/trips/trips_local_store.dart](../lib/trips/trips_local_store.dart) | `TripsLocalStore`/`PreferencesTripsLocalStore` — persists the cached trip list as JSON in `shared_preferences` (plain storage; nothing here is a secret). |
| [lib/trips/trips_repository.dart](../lib/trips/trips_repository.dart) | `TripsRepository` — the offline-first front door screens use instead of `TripsApi` directly. See below. |
| [lib/features/trips/trip_list_screen.dart](../lib/features/trips/trip_list_screen.dart) | `TripListScreen` — the `/trips` route. Reads from the cache first, then refreshes from the network in the background. |
| [lib/features/trips/create_trip_screen.dart](../lib/features/trips/create_trip_screen.dart) | `CreateTripScreen` — the `/trips/new` route. A form for title (required), description, start/end date, and currency. |

## API contract

`GET /api/trips` returns `{ trips: [...] }` (never a bare array). `POST /api/trips` takes `{ title, description?, start_date?, end_date?, currency?, reminder_days?, day_count? }` and returns `{ trip }`. Only `title` is required — the server infers a missing end date as 6 days after the start date (and vice versa), and auto-generates the trip's `Day` records from the resulting date range, so the client doesn't replicate either of those. Trip currency defaults to `EUR` server-side when omitted. Dates are `YYYY-MM-DD` strings.

Each trip in a list/create response also carries `day_count` and `place_count` (aggregate counts, not the records themselves — those are issues [#4](https://github.com/ryanmac8/trek-native-app/issues/4)/[#5](https://github.com/ryanmac8/trek-native-app/issues/5)).

## Offline-first read/write (`TripsRepository`)

Per [offline-first.md](offline-first.md), `TripListScreen` and `CreateTripScreen` never talk to `TripsApi` directly — they go through `TripsRepository`, which keeps the local cache as the source of truth for what's shown:

- **`cachedTrips()`** reads the local store only. `TripListScreen` calls this on load for an instant first paint before the network is involved at all.
- **`refreshTrips()`** retries any pending (offline-created) trips, then fetches the real list. On `NetworkException` it falls back to returning the cache instead of failing — only when the cache is empty does the exception propagate, so the caller can show an explicit offline state.
- **`createTrip()`** writes an optimistic `Trip` to the cache immediately (`id: null`, so `isPending` is `true`) before attempting the network call. If the create can't reach the server, the pending trip stays queued in the cache rather than being lost, and the next `refreshTrips()` call (screen load, pull-to-refresh) retries it. A genuine rejection (validation, permissions, a 5xx) instead rolls back the optimistic write and rethrows, so the form can show the error inline.

`TripListScreen` renders a still-pending trip with a "Syncing…" subtitle and a static sync icon instead of the usual chevron; tapping it is a no-op, since there's no server id yet to navigate to.

## What's still open

- Edit, archive/unarchive, delete, cover image upload, and the trip dashboard summary (remaining `TripsApi`/`TripsRepository` methods and screens for issue #3).
- A shared local-persistence/sync mechanism for the rest of the data model (issue #21) — this cache is deliberately scoped to trips only, not a general pattern yet.
- Conflict resolution for a trip edited on two devices while offline — not applicable yet since there's no edit path, but will need a strategy once one exists.
