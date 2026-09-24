# Atlas

Atlas is Trek's cross-trip travel record ([#18](https://github.com/ryanmac8/trek-native-app/issues/18)): visited countries and regions, a bucket list, and aggregate travel stats. The app currently implements the **stats dashboard** — totals, the next-trip countdown and last trip, most-visited country, travel streak, and continents breakdown. Visited-country/region marking, the bucket list, and the map view are not built yet.

## Pieces

| File | What it is |
| --- | --- |
| [lib/atlas/atlas_models.dart](../lib/atlas/atlas_models.dart) | `AtlasStats` (the stats response), `AtlasCountry`, `AtlasLastTrip`, `AtlasNextTrip`, `VisitStatus`, and `CachedAtlasStats` (a snapshot plus its `fetchedAt`). Also date helpers (`parseTrekDate`, `calendarDaysBetween`) and `countryFlag`. |
| [lib/atlas/atlas_api.dart](../lib/atlas/atlas_api.dart) | `AtlasApi.fetchStats()` — transport only, no caching. |
| [lib/atlas/atlas_local_store.dart](../lib/atlas/atlas_local_store.dart) | `AtlasLocalStore` interface + `PreferencesAtlasLocalStore`, one JSON snapshot per account scope in `shared_preferences`. |
| [lib/atlas/atlas_repository.dart](../lib/atlas/atlas_repository.dart) | `AtlasRepository` — the offline-first front door: `cachedStats()` (local only) and `refreshStats()` (fetch, write through, return). |
| [lib/features/atlas/atlas_screen.dart](../lib/features/atlas/atlas_screen.dart) | `AtlasScreen` at `/atlas`, opened from the trip list's globe action. |

Providers (`atlasApiProvider`, `atlasLocalStoreProvider`, `atlasCacheScopeProvider`, `atlasRepositoryProvider`) live in [lib/app/providers.dart](../lib/app/providers.dart); `AtlasApi` uses the authenticated `apiClientProvider`.

## API contract

`GET /api/addons/atlas/stats` (`AtlasController` in Trek's `server/src/nest/atlas/`) — JWT-guarded, with no addon gate, so it answers even when the Atlas addon is disabled.

```jsonc
{
  "countries": [
    { "code": "NZ", "placeCount": 12, "tripCount": 2,
      "firstVisit": "2024-02-01", "lastVisit": "2025-03-10",
      "status": "visited" }          // visited | planned | idea
  ],
  "stats": {
    "totalTrips": 5, "totalPlaces": 17,
    "totalCountries": 1,             // visited only
    "totalCountriesPlanned": 1, "totalCountriesIdea": 1,
    "totalDays": 23, "totalCities": 6
  },
  "mostVisited": { /* a countries[] entry, or null */ },
  "continents": { "Oceania": 1 },          // visited countries per continent
  "continentsPlanned": { "Asia": 1 },
  "lastTrip": { "id": 20, "title": "New Zealand", "start_date": "2025-03-01",
                "end_date": "2025-03-10", "countryCode": "NZ" },  // or null
  "nextTrip": { "id": 21, "title": "Japan", "start_date": "2026-10-04",
                "daysUntil": 10 },                                // or null
  "streak": 3,          // consecutive years with a trip, counting back from now
  "firstYear": 2024,    // or null
  "tripsThisYear": 2
}
```

- `status` semantics: **visited** — at least one source is a trip that has started, or a manual mark; **planned** — every source is a trip starting in the future; **idea** — every source is an undated trip. The totals, `mostVisited`, and `continents` count visited countries only.
- Continent names are `Africa`, `Antarctica`, `Asia`, `Europe`, `North America`, `Oceania`, `South America`, or `Other`.
- A user with **no trips** gets a reduced shape: `countries` (manually marked countries only, without `status`), `trips: []`, and `stats` with only `totalTrips`/`totalPlaces`/`totalCountries`/`totalDays`. `AtlasStats.fromJson` accepts both shapes — missing counters read as 0, missing objects as `null`, and a missing `status` as `visited`.

## Offline behavior

- `AtlasScreen` paints the cached snapshot first, then refreshes. If the refresh fails and a snapshot exists, it stays on screen with an "Offline — showing stats from …" banner and a retry. With no snapshot, a `NetworkException` shows an explicit offline state with a retry; any other error shows a generic error state.
- The next-trip countdown and last-trip "ended N days ago" are computed on the device from the trip dates (`AtlasNextTrip.daysUntil`, `AtlasLastTrip.daysSinceEnd`), not from the server's `daysUntil` snapshot, so they stay correct as the cache ages. A cached next trip whose start date has passed is hidden. `streak` and `tripsThisYear` are server-computed for the year at fetch time.
- Snapshots are keyed by **account scope** — the configured public server URL plus the session's user id (the JWT `id` claim, via `AuthService.currentUserId`) — so a different account or server on the same device never sees another account's stats. Without a live session the repository neither reads nor writes the cache. A corrupt entry reads as a cache miss.
- This slice is read-only, so there is no outbox. Marking countries/regions and editing the bucket list are mutations that depend on the write-queue mechanism tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21) — see [offline-first.md](offline-first.md).
