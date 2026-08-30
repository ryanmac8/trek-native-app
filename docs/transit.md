# Transit & airport search

The first slice of [issue #12](https://github.com/ryanmac8/trek-native-app/issues/12): searching public-transit stops, planning a public-transit route between two of them, and looking up airports. Transport entries on the itinerary, creating a journey from a search result, and a transit-mode / departure-time UI are not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/transit/transit_models.dart](../lib/transit/transit_models.dart) | `TransitPlace` (a stop / station / place, with a `"lat,lng"` `coordinate` getter), `TransitItinerary` → `TransitLeg` → `TransitLegStop` (a planned journey and its segments), `Airport`, and `TransitPlanQuery` (the `/api/transit/plan` parameters, with a stable `cacheKey`). The wire shape and the local-cache shape are the same JSON, so `fromJson` / `toJson` round-trip through the local store. |
| [lib/transit/transit_api.dart](../lib/transit/transit_api.dart) | `TransitApi` — wraps `GET /api/transit/geocode`, `GET /api/transit/plan`, `GET /api/airports/search`, and `GET /api/airports/:iata`. A thin transport layer: no caching, no offline handling. |
| [lib/transit/transit_local_store.dart](../lib/transit/transit_local_store.dart) | `TransitLocalStore` / `PreferencesTransitLocalStore` — a bounded (30-entry, oldest-evicted) `shared_preferences` cache of the last results per query, one map each for stop search, route plans, and airport search. A `null` read means "never fetched" (distinct from an empty list). |
| [lib/transit/transit_repository.dart](../lib/transit/transit_repository.dart) | `TransitRepository` — the offline-first front door the screen uses instead of `TransitApi`. See below. |
| [lib/transit/transit_format.dart](../lib/transit/transit_format.dart) | Presentation helpers — `formatDuration`, `formatClock`, `formatMode`, `itinerarySummary`, `transferLabel`. |
| [lib/features/transit/transit_search_screen.dart](../lib/features/transit/transit_search_screen.dart) | `TransitSearchScreen` — the `/transit` screen, reachable from the trip list's app-bar transit icon. A `SegmentedButton` toggles between **Routes** (from/to stop pickers → itinerary cards) and **Airports** (a search list). |

## API contract

All endpoints are JWT-guarded (`TransitController` and `AirportsController`, `server/src/nest/transit/` and `server/src/nest/airports/`), so this is the app's first authenticated `ApiClient` (`apiClientProvider` in `lib/app/providers.dart`), attaching `AuthService.currentAccessToken` to every request and clearing the local session on a 401.

Trek proxies transit routing through [Transitous](https://transitous.org) (a community MOTIS instance over public GTFS feeds) or a self-hosted MOTIS at `TRANSIT_API_URL`. Because Trek is self-hosted, whether transit search works at all depends on the instance's configuration — a plain `502`/`error` response is the expected "provider not available" signal.

- **`GET /api/transit/geocode?q=&lang=&near=`** → `{ results: [{ name, lat, lng, type, area }] }`. `q` shorter than 2 characters returns `[]` (not a 400). `near` is a `"lat,lng"` string that biases results. At most 8 results. Rate-limited server-side (300 / 15 min per IP).
- **`GET /api/transit/plan?from=&to=&time=&arriveBy=&modes=&maxTransfers=`** → `{ itineraries: [{ startTime, endTime, duration, transfers, walkSeconds, legs: [{ mode, from, to, duration, distance, headsign, line, lineColor, lineTextColor, agency, intermediateStops }] }] }`. `from` / `to` are required `"lat,lng"` strings; a non-coordinate value is a `400`. `time` is an ISO date-time (default: now); `arriveBy=true` treats it as an arrival deadline. `modes` is a comma list from a server-side whitelist (`BUS`, `TRAM`, `SUBWAY`, `RAIL`, `FERRY`, `HIGHSPEED_RAIL`, …); `maxTransfers` is `0`–`10`. Up to 8 itineraries, walk-only connections excluded. `duration` is wall-clock seconds (start → end, so waits count). Rate-limited more tightly (60 / 15 min per IP). This slice sends only `from` / `to`.
- **`GET /api/airports/search?q=`** → `[{ iata, icao, name, city, country, lat, lng, tz }]`. A missing / empty `q` returns `[]`. Backed by a bundled dataset (IATA / ICAO / city / name prefix and substring matching), up to 12 results.
- **`GET /api/airports/:iata`** → one `Airport`, or `404 { error: 'Airport not found' }`. `TransitApi.lookupAirport` maps the 404 to `null`.

Coordinates arrive as numbers; `TransitLegStop` coordinates can be `0` when the feed omits them. GTFS line colours arrive `#`-prefixed or `null`.

## Offline-first (`TransitRepository`)

Per [offline-first.md](offline-first.md), the screen never calls `TransitApi` directly. Search and route planning genuinely need the network — there is no bundled transit graph — but the local cache stays the source of truth for *what is shown*:

- **`cachedStops` / `cachedRoute` / `cachedAirports`** read the local store only. The screen calls these first so the last results for a repeated query paint instantly.
- **`searchStops` / `planRoute` / `searchAirports`** fetch, write the cache, and return. On a `NetworkException` they fall back to the cached results for that *exact* query (normalised key: trimmed, lower-cased, whitespace-collapsed, with an optional `near` suffix). Only when nothing is cached does the exception propagate, so the screen can show an explicit offline state with a retry. Queries the server would reject as too short are answered with an empty list without a request.

There are no local writes. Turning a search result into an itinerary/transport entry is a mutation that depends on the Days feature ([#4](https://github.com/ryanmac8/trek-native-app/issues/4)); it is deferred with it, and the durable outbox that mutation will need is [#21](https://github.com/ryanmac8/trek-native-app/issues/21)'s job. The `shared_preferences` result cache here is a minimal, feature-scoped stand-in for the local-persistence mechanism #21 will decide on.

## What's still open

- Transport entries (mode, duration) shown on the itinerary, and creating a transit journey from a search result into the itinerary — both need the Days feature ([#4](https://github.com/ryanmac8/trek-native-app/issues/4)).
- A departure/arrival-time picker and transit-mode / max-transfers filters (the API layer and `TransitPlanQuery` already carry the parameters; the UI sends only `from` / `to`).
- Airport single-lookup by code is wired in `TransitApi` but not surfaced in the UI.
- A map view of an itinerary's geometry (the server returns encoded polylines; the model drops them for now).
- Route-leg realtime/track detail beyond the summary line, and pagination past the first result page.
- Localised mode labels and times — the app has no locale system yet.
