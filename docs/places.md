# Places

Covers the read-only first slice of [issue #5](https://github.com/ryanmac8/trek-native-app/issues/5): the Places tab of the trip dashboard, backed by a trip-scoped local cache. Place create/edit/delete, the category picker, bulk actions, search/filter, and importers are not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/places/place.dart](../lib/places/place.dart) | `Place` — the place model, trimmed to what the pool row renders (name, category, price/currency, notes). `PlaceCategoryRef` — the category embedded on a place (id/name/color/icon), distinct from the design system's `PlaceCategory` enum ([place_category_colors.dart](../lib/design/place_category_colors.dart)), which models fixed default-category tokens rather than a place's actual assigned category. `fromJson`/`toCacheJson`/`fromCacheJson` are the API and local-cache (de)serializers, respectively. |
| [lib/places/places_api.dart](../lib/places/places_api.dart) | `PlacesApi` — thin wrapper around `GET /api/trips/:tripId/places`. |
| [lib/places/places_local_store.dart](../lib/places/places_local_store.dart) | `PlacesLocalStore`/`PreferencesPlacesLocalStore` — persists each trip's cached place list as JSON in `shared_preferences`, keyed per trip id so multiple trips' place pools cache independently. |
| [lib/places/places_repository.dart](../lib/places/places_repository.dart) | `PlacesRepository` — the offline-first front door the Places tab uses instead of `PlacesApi` directly. See below. |
| [lib/features/trips/trip_dashboard_screen.dart](../lib/features/trips/trip_dashboard_screen.dart) | `_PlacesTab` — the Places section of the trip dashboard's bottom-tab shell. Reads from the cache first, then refreshes from the network in the background. Each row shows the place's name, a price/notes subtitle, and a `_CategoryBadge` colored from the place's real (server-assigned) category. |

## API contract

`GET /api/trips/:tripId/places` returns `{ places: [...] }` (never a bare array), confirmed against Trek's actual `PlacesController`/`placeService.list`. The full place row is wide (description, address, lat/lng, website, phone, image, reservation fields, tags, provider-derived import columns — see Trek's `placeSchema`); only `name`, the embedded `category` projection (`id`/`name`/`color`/`icon`, `null` when unset), `price`, `currency`, and `notes` are modeled client-side so far. Category colors are hex strings (e.g. `#3b82f6`), matching the default categories' seed colors in Trek's backend (`server/src/db/seeds.ts`).

Endpoint requires a bearer token — this PR adds the app's first authenticated `ApiClient` (`apiClientProvider` in `lib/app/providers.dart`), attaching `AuthService.currentAccessToken` to every request.

Create (`POST`), update (`PUT .../:id`), delete (`DELETE .../:id`), bulk update/delete, image search, and the GPX/map/Google/Naver list importers all exist server-side but aren't implemented in this client yet. Neither is `GET /api/categories` (the category picker's palette, including a user's custom categories) — this slice only reads the category Trek's server has already assigned to each place.

## Offline-first read (`PlacesRepository`)

Per [offline-first.md](offline-first.md), the Places tab never talks to `PlacesApi` directly — it goes through `PlacesRepository`, which keeps the local cache as the source of truth for what's shown:

- **`cachedPlaces(tripId)`** reads the local store only. The Places tab calls this on load for an instant first paint before the network is involved at all.
- **`refreshPlaces(tripId)`** fetches the real list and writes it to the cache. On `NetworkException` it falls back to returning the cache instead of failing — only when the cache is empty does the exception propagate, so the caller can show an explicit offline state.

Unlike `TripsRepository` (once it exists), there's no pending-write queue here yet — this slice is read-only, so there's nothing to reconcile after a mutation.

## What's still open

- Place create, edit, delete, and bulk update/delete (the rest of `PlacesApi`/`PlacesRepository` for issue #5).
- The "place pool" filter — this slice shows every place in the trip, not narrowed to places not yet assigned to a day, since a day's assignments don't expose place ids client-side yet (depends on [#4](https://github.com/ryanmac8/trek-native-app/issues/4)).
- The category picker and custom-category CRUD (`GET`/`POST`/`PUT`/`DELETE /api/categories`) — needed once place create/edit exists.
- Place detail view (description, address, website, phone, photo), search/filter, and the GPX/map/Google/Naver list importers.
- A local write queue for place mutations, once they exist — see docs/offline-first.md's note on conflicts and the durable outbox tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21).
