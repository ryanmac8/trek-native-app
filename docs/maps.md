# Maps & Geocoding

First slice of [issue #17](https://github.com/ryanmac8/trek-native-app/issues/17): resolving a shared Google Maps link and reverse-geocoding a manually entered coordinate, each into a name/address. The `/maps` screen (reached from the trip list's app-bar map icon) is a standalone lookup tool — it does not add anything to a trip yet, since that needs place creation ([#5](https://github.com/ryanmac8/trek-native-app/issues/5)), which the app doesn't have.

Not covered by this slice: place text search, autocomplete, place details/photos, importing multiple places from one shared list, and an actual map view of a trip's places. Those endpoints return open, provider-shaped records (Google Places vs. OpenStreetMap fields differ) rather than the two fixed shapes below, which is a larger follow-up.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/maps/maps_models.dart](../lib/maps/maps_models.dart) | `LatLng`, `ReverseGeocodeResult`, `ResolvedPlace` — the wire shapes for the two endpoints below. |
| [lib/maps/maps_api.dart](../lib/maps/maps_api.dart) | `MapsApi` — thin wrapper over the authenticated `ApiClient` for `/api/maps/reverse` and `/api/maps/resolve-url`. No caching. |
| [lib/maps/maps_local_store.dart](../lib/maps/maps_local_store.dart) | `MapsLocalStore`/`PreferencesMapsLocalStore` — a `shared_preferences`-backed cache for both lookup kinds, keyed by rounded coordinate or by URL. |
| [lib/maps/maps_repository.dart](../lib/maps/maps_repository.dart) | `MapsRepository` — the offline-first front door screens use. |
| [lib/features/maps/maps_lookup_screen.dart](../lib/features/maps/maps_lookup_screen.dart) | `MapsLookupScreen` (`/maps`) — a "paste a link" section and a "look up a coordinate" section. |

## API contract

Confirmed against Trek's backend (`server/src/nest/maps/maps.controller.ts`, `maps.service.ts`, and the Zod contract in `@trek/shared/maps/maps.schema.ts`). Both endpoints are JWT-guarded.

- `GET /api/maps/reverse?lat=&lng=&lang=` — `lat`/`lng` are sent as strings (the server's query schema declares them as strings, not numbers). A missing `lat`/`lng` 400s. A geocoder miss is **not** an error: it comes back `200 { name: null, address: null }`, matched here by `ReverseGeocodeResult.isEmpty`.
- `POST /api/maps/resolve-url { url }` — resolves a shared Google Maps link (`https://maps.app.goo.gl/...`, a full `google.com/maps/...` URL, etc.) into `{ lat, lng, name, address, google_ftid }`. A URL that doesn't resolve to anywhere 400s as a `ValidationException`, not a null result.

## Offline behavior

Both lookups are read-only and effectively static — a place's address doesn't change between one lookup and the next — so `MapsLocalStore` caches each answer for a week rather than treating it like a live value. `MapsRepository`:

- Returns a fresh cache hit without touching the network.
- On a cache miss or expired entry, fetches, caches the result, and returns it.
- On a `NetworkException` (or, for reverse geocoding, an all-null "nothing found" answer standing in for one), falls back to a stale cached entry if one exists, flagging the result so the screen can show an offline notice.
- Only when nothing is cached does the exception propagate, so the screen can show an explicit offline state instead of hanging.
- A `ValidationException` (a URL that doesn't resolve, or coordinates the server rejects) always propagates — that's a real input error, not an offline condition.

Reverse-geocode cache keys round the coordinate to 5 decimal places (~1.1m) so two lookups for effectively the same pin share an entry; resolve-url cache keys are the trimmed URL itself.
