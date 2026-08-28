# Reservations

Covers the read-only first slice of [issue #11](https://github.com/ryanmac8/trek-native-app/issues/11): the Bookings tab of the trip dashboard, backed by a trip-scoped local cache. Reservation create/edit/delete, the day/place picker, multi-leg transport detail, travelers, and itinerary-day context are not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/reservations/reservation.dart](../lib/reservations/reservation.dart) | `Reservation` — the model, trimmed to what the Bookings row renders: `title`, `type`, `status`, the `reservation_time` / `reservation_end_time` strings, `location`, `confirmation_number`, `notes`, `url`, the `day_id` link, and the joined `day_number` / `place_name`. `type` and `status` are never null — they mirror the server column defaults (`other` / `pending`). `fromJson`/`toCacheJson`/`fromCacheJson` are the API and local-cache (de)serializers — the wire and cache shapes are the same snake-cased keys. |
| [lib/reservations/reservations_api.dart](../lib/reservations/reservations_api.dart) | `ReservationsApi` — thin wrapper around `GET /api/trips/:tripId/reservations`. |
| [lib/reservations/reservations_local_store.dart](../lib/reservations/reservations_local_store.dart) | `ReservationsLocalStore`/`PreferencesReservationsLocalStore` — persists each trip's cached reservation list as JSON in `shared_preferences`, keyed per trip id (`trek.reservations.cache.<tripId>`) so multiple trips' bookings cache independently. |
| [lib/reservations/reservations_repository.dart](../lib/reservations/reservations_repository.dart) | `ReservationsRepository` — the offline-first front door the Bookings tab uses instead of `ReservationsApi` directly. See below. |
| [lib/features/trips/trip_dashboard_screen.dart](../lib/features/trips/trip_dashboard_screen.dart) | `_BookingsTab` — the Bookings section of the trip dashboard's bottom-tab shell. Reads from the cache first, then refreshes from the network in the background. Each row shows a per-`type` icon, the title, a detail line (start time, falling back to location, then the linked place, then the itinerary day), and a confirmation-number icon when the booking has one. A `cancelled` booking is prefixed `Cancelled ·` in its detail line. |

## API contract

`GET /api/trips/:tripId/reservations` returns `{ reservations: [...] }` (never a bare array), confirmed against Trek's actual `ReservationsController.list` and `ReservationsService.list`, ordered by `reservation_time` ascending then `created_at` ascending. A trip the caller can't access is `404 { error: 'Trip not found' }` (the shared `TripAccessGuard`).

Each row is the `reservations` table (`id`, `trip_id`, `day_id`, `end_day_id`, `place_id`, `assignment_id`, `title`, `accommodation_id`, `reservation_time`, `reservation_end_time`, `location`, `confirmation_number`, `notes`, `status`, `type`, `created_at`, plus `url` and the AirTrail `external_*` / `sync_enabled` columns) with `day_number` and `place_name` joined in, and the computed `day_positions`, `endpoints`, `travelers`, and linked-accommodation (`accommodation_name`, `accommodation_place_id`, `accommodation_start_day_id`, `accommodation_end_day_id`) fields. Only `title`, `type`, `status`, the two time strings, `location`, `confirmation_number`, `notes`, `url`, `day_id`, `day_number`, and `place_name` are modeled client-side so far.

`type` is free-form (`flight`, `train`, `bus`, `car`, `ferry`, `taxi`, `hotel`, `restaurant`, `activity`, `parking`, `other`, …) — the server never constrains it to an enum, so the row's icon mapping treats unrecognized values as "other". `status` is one of `pending` / `confirmed` / `cancelled` (the values Trek's own clients write), also unconstrained server-side.

`reservation_time` / `reservation_end_time` are TEXT columns holding whatever string the writer stored (usually `YYYY-MM-DD HH:mm` or an ISO string), not a normalized timestamp — the row shows them verbatim. `day_id` is a day *id*, not a date; resolving it needs the trip's day list, which isn't modeled client-side yet ([#4](https://github.com/ryanmac8/trek-native-app/issues/4)), so the row falls back to the joined `day_number`.

The endpoint requires a bearer token — this is the app's first authenticated `ApiClient` (`apiClientProvider` in `lib/app/providers.dart`), attaching `AuthService.currentAccessToken` to every request and clearing the local session on a 401.

`POST /api/trips/:tripId/reservations` (needs `title`), `PUT .../:id`, `PUT .../positions`, `PUT .../:id/travelers`, and `DELETE .../:id` all exist server-side but aren't implemented in this client yet — the create/edit forms depend on the place pool ([#5](https://github.com/ryanmac8/trek-native-app/issues/5)) and day model ([#4](https://github.com/ryanmac8/trek-native-app/issues/4)) being available client-side to pick those references, and the server-side create/update path carries budget and accommodation side effects that a client mutation layer will need to account for.

## Offline-first read (`ReservationsRepository`)

Per [offline-first.md](offline-first.md), the Bookings tab never talks to `ReservationsApi` directly — it goes through `ReservationsRepository`, which keeps the local cache as the source of truth for what's shown:

- **`cachedReservations(tripId)`** reads the local store only. The Bookings tab calls this on load for an instant first paint before the network is involved at all.
- **`refreshReservations(tripId)`** fetches the real list and writes it to the cache. On `NetworkException` it falls back to returning the cache instead of failing — only when the cache is empty does the exception propagate, so the caller can show an explicit offline state.

There's no pending-write queue here — this slice is read-only, so there's nothing to reconcile after a mutation.

## What's still open

- Reservation create, edit, and delete (the rest of `ReservationsApi`/`ReservationsRepository` for issue #11), including the type/status pickers and the server-side budget + accommodation side effects a client write triggers.
- Linking a reservation to a day or a place / assignment (needs [#4](https://github.com/ryanmac8/trek-native-app/issues/4) and [#5](https://github.com/ryanmac8/trek-native-app/issues/5)).
- Multi-leg transport bookings — the `endpoints` / `metadata.legs` geometry and per-segment times — and the dedicated transport UI ([#12](https://github.com/ryanmac8/trek-native-app/issues/12)).
- Travelers assigned to a booking, and the linked-accommodation columns.
- Resolving `day_id` to a calendar date, and showing bookings inline on the itinerary.
- A local write queue for reservation mutations, once they exist — see docs/offline-first.md's note on conflicts and the durable outbox tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21).
