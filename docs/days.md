# Days

Covers the read-only first slice of [issue #4](https://github.com/ryanmac8/trek-native-app/issues/4): the Days tab of the trip dashboard, backed by a trip-scoped local cache. Day create/reorder/edit, and place assignments, are not built yet — those depend on the places data model ([#5](https://github.com/ryanmac8/trek-native-app/issues/5)).

## Pieces

| File | Purpose |
| --- | --- |
| [lib/days/day.dart](../lib/days/day.dart) | `Day` — the day model. `fromJson`/`toCacheJson`/`fromCacheJson` are the API and local-cache (de)serializers, respectively. `assignmentCount` is derived from the response's nested `assignments` array length, since a place model to render those assignments doesn't exist yet. |
| [lib/days/days_api.dart](../lib/days/days_api.dart) | `DaysApi` — thin wrapper around `GET /api/trips/:tripId/days`. |
| [lib/days/days_local_store.dart](../lib/days/days_local_store.dart) | `DaysLocalStore`/`PreferencesDaysLocalStore` — persists each trip's cached day list as JSON in `shared_preferences`, keyed per trip id so multiple trips' itineraries cache independently. |
| [lib/days/days_repository.dart](../lib/days/days_repository.dart) | `DaysRepository` — the offline-first front door the Days tab uses instead of `DaysApi` directly. See below. |
| [lib/features/trips/trip_dashboard_screen.dart](../lib/features/trips/trip_dashboard_screen.dart) | `_DaysTab` — the Days section of the trip dashboard's bottom-tab shell. Reads from the cache first, then refreshes from the network in the background. |

## API contract

`GET /api/trips/:tripId/days` returns `{ days: [...] }` (never a bare array), confirmed against Trek's actual `DaysController`/`dayService.listDays`. Each day carries `id`, `trip_id`, `day_number`, `date` (`YYYY-MM-DD` or `null` for an undated trip), `notes`, `title`, plus nested `assignments` and `notes_items` arrays. Days are auto-generated server-side from a trip's date range when the trip is created (see [trips.md](trips.md)) — there's no client-side create for the initial set.

Only `day_number`, `date`, `notes`, `title`, and the assignment count are modeled client-side so far; the full assignment/place shape, `notes_items`, create (`POST`), reorder (`PUT .../reorder`), update (`PUT .../:id`), and delete (`DELETE .../:id`) endpoints exist server-side but aren't implemented in this client yet.

## Offline-first read (`DaysRepository`)

Per [offline-first.md](offline-first.md), the Days tab never talks to `DaysApi` directly — it goes through `DaysRepository`, which keeps the local cache as the source of truth for what's shown:

- **`cachedDays(tripId)`** reads the local store only. The Days tab calls this on load for an instant first paint before the network is involved at all.
- **`refreshDays(tripId)`** fetches the real list and writes it to the cache. On `NetworkException` it falls back to returning the cache instead of failing — only when the cache is empty does the exception propagate, so the caller can show an explicit offline state.

Unlike `TripsRepository`, there's no pending-write queue here yet — this slice is read-only, so there's nothing to reconcile after a mutation. A day create/reorder/edit path will need one once those are built.

## What's still open

- Day create, reorder, update (notes/title), and delete (the rest of `DaysApi`/`DaysRepository` for issue #4).
- Place assignments — rendering the actual places assigned to a day, not just a count (depends on [#5](https://github.com/ryanmac8/trek-native-app/issues/5)).
- Day notes (`notes_items`) — a separate list from a day's own `notes` field, not yet modeled.
- A local write queue for day mutations, once they exist — see docs/offline-first.md's note on conflicts and the durable outbox tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21).
