# Accommodations

Covers the read-only first slice of [issue #10](https://github.com/ryanmac8/trek-native-app/issues/10): the Stays tab of the trip dashboard, backed by a trip-scoped local cache. Accommodation create/edit/delete, linking an existing place as an accommodation, the check-in/check-out day-range picker, and itinerary-day context are not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/accommodations/accommodation.dart](../lib/accommodations/accommodation.dart) | `Accommodation` — the model, trimmed to what the Stays row renders: the linked place's name and address, the `start_day_id` / `end_day_id` bounds, the `check_in` / `check_in_end` / `check_out` date strings, `confirmation`, `notes`, and the linked `reservation_title`. `place_id` is `null` when the linked place has been deleted. `fromJson`/`toCacheJson`/`fromCacheJson` are the API and local-cache (de)serializers — the wire and cache shapes are the same snake-cased keys. |
| [lib/accommodations/accommodations_api.dart](../lib/accommodations/accommodations_api.dart) | `AccommodationsApi` — thin wrapper around `GET /api/trips/:tripId/accommodations`. |
| [lib/accommodations/accommodations_local_store.dart](../lib/accommodations/accommodations_local_store.dart) | `AccommodationsLocalStore`/`PreferencesAccommodationsLocalStore` — persists each trip's cached accommodation list as JSON in `shared_preferences`, keyed per trip id so multiple trips' stays cache independently. |
| [lib/accommodations/accommodations_repository.dart](../lib/accommodations/accommodations_repository.dart) | `AccommodationsRepository` — the offline-first front door the Stays tab uses instead of `AccommodationsApi` directly. See below. |
| [lib/features/trips/trip_dashboard_screen.dart](../lib/features/trips/trip_dashboard_screen.dart) | `_StaysTab` — the Stays section of the trip dashboard's bottom-tab shell. Reads from the cache first, then refreshes from the network in the background. Each row shows the place name, a "check-in → check-out" line (falling back to the place address, then the linked reservation title), and a confirmation-number icon when the booking has one. |

## API contract

`GET /api/trips/:tripId/accommodations` returns `{ accommodations: [...] }` (never a bare array), confirmed against Trek's actual `AccommodationsController` and `dayService.listAccommodations`, ordered by `created_at` ascending. A trip the caller can't access is `404 { error: 'Trip not found' }`. Each row is the `day_accommodations` table (`id`, `trip_id`, `place_id`, `start_day_id`, `end_day_id`, `check_in`, `check_in_end`, `check_out`, `confirmation`, `notes`, `created_at`) plus the place columns joined in (`place_name`, `place_address`, `place_image`, `place_lat`, `place_lng`) and `reservation_title` from the auto-linked reservation. Only `place_name`, `place_address`, the day-id bounds, the check-in/out date strings, `confirmation`, `notes`, and `reservation_title` are modeled client-side so far.

`start_day_id` / `end_day_id` are day *ids*, not dates — resolving them to calendar dates needs the trip's day list, which isn't modeled client-side yet ([#4](https://github.com/ryanmac8/trek-native-app/issues/4)), so the row leans on `check_in` / `check_out` for its date line.

The endpoint requires a bearer token — this is the app's first authenticated `ApiClient` (`apiClientProvider` in `lib/app/providers.dart`), attaching `AuthService.currentAccessToken` to every request and clearing the local session on a 401.

`POST /api/trips/:tripId/accommodations` (needs `place_id`, `start_day_id`, `end_day_id`), `PUT .../:id`, and `DELETE .../:id` all exist server-side but aren't implemented in this client yet — they depend on the place pool ([#5](https://github.com/ryanmac8/trek-native-app/issues/5)) and day model ([#4](https://github.com/ryanmac8/trek-native-app/issues/4)) being available client-side to pick those references.

## Offline-first read (`AccommodationsRepository`)

Per [offline-first.md](offline-first.md), the Stays tab never talks to `AccommodationsApi` directly — it goes through `AccommodationsRepository`, which keeps the local cache as the source of truth for what's shown:

- **`cachedAccommodations(tripId)`** reads the local store only. The Stays tab calls this on load for an instant first paint before the network is involved at all.
- **`refreshAccommodations(tripId)`** fetches the real list and writes it to the cache. On `NetworkException` it falls back to returning the cache instead of failing — only when the cache is empty does the exception propagate, so the caller can show an explicit offline state.

There's no pending-write queue here — this slice is read-only, so there's nothing to reconcile after a mutation.

## What's still open

- Accommodation create, edit, and delete (the rest of `AccommodationsApi`/`AccommodationsRepository` for issue #10), including linking an existing Hotel-category place as an accommodation and a new-place flow.
- The check-in / check-out day-range picker (needs the trip's day list — [#4](https://github.com/ryanmac8/trek-native-app/issues/4)).
- Showing accommodation context on the relevant days in the itinerary view.
- Resolving `start_day_id` / `end_day_id` to calendar dates for accommodations that have no `check_in` / `check_out` set.
- The place image, coordinates, and a map preview.
- A local write queue for accommodation mutations, once they exist — see docs/offline-first.md's note on conflicts and the durable outbox tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21).
