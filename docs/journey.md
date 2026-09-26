# Journey

Journey is Trek's cross-trip travel narrative ([#20](https://github.com/ryanmac8/trek-native-app/issues/20)): a dated series of written entries, check-ins, and photos that can span several linked trips, with contributors who can view or edit it. It is an addon that a Trek admin can switch off per server. The app currently implements a **read-only view**:

- the list of journeys the user owns or contributes to
- one journey: status, the viewer's role, entry/photo/place counts, linked trips, contributors, and its entries grouped by date

These are not built yet: creating, editing, and deleting journeys and entries; reordering entries; photos (entry photos and the gallery are counted but not shown); linking and unlinking trips; contributor management; share links; suggestions; per-journey preferences; the map, stats, and photo-book views.

## Pieces

| File | What it is |
| --- | --- |
| [lib/journey/journey_models.dart](../lib/journey/journey_models.dart) | `JourneyList` / `JourneySummary` (list rows), `JourneyDetail` (with `JourneyEntry`s, `JourneyTrip`s, `JourneyContributor`s), the `JourneyStatus`, `JourneyRole`, and `JourneyEntryType` enums, and `CachedJourney<T>` (a snapshot plus its `fetchedAt`). |
| [lib/journey/journey_api.dart](../lib/journey/journey_api.dart) | `JourneyApi.fetchJourneys()` and `fetchJourney(id)`. Transport only, no caching. |
| [lib/journey/journey_local_store.dart](../lib/journey/journey_local_store.dart) | `JourneyLocalStore` interface + `PreferencesJourneyLocalStore`. Stores one JSON snapshot for the list and one per opened journey, per account scope, in `shared_preferences`. |
| [lib/journey/journey_repository.dart](../lib/journey/journey_repository.dart) | `JourneyRepository`, the offline-first front door. `cachedList()` and `cachedJourney(id)` read only the local cache. `refreshList()` and `refreshJourney(id)` fetch, write the result to the cache, and return it. |
| [lib/features/journey/journey_list_screen.dart](../lib/features/journey/journey_list_screen.dart) | `JourneyListScreen` at `/journeys`, opened from the trip list's book action. |
| [lib/features/journey/journey_detail_screen.dart](../lib/features/journey/journey_detail_screen.dart) | `JourneyDetailScreen` at `/journeys/:journeyId`. |
| [lib/features/journey/journey_widgets.dart](../lib/features/journey/journey_widgets.dart) | Shared pieces: the load-error states, the offline banner, and date formatting. |

The providers are `journeyApiProvider`, `journeyLocalStoreProvider`, `journeyCacheScopeProvider`, and `journeyRepositoryProvider`, all in [lib/app/providers.dart](../lib/app/providers.dart). `JourneyApi` uses the authenticated `apiClientProvider`.

## API contract

These endpoints live in `JourneyController` in Trek's `server/src/nest/journey/`, under `/api/journeys`. The data comes from `JourneyDomainService.listJourneys` and `getJourneyFull`.

- **Addon gate.** The Journey addon guard runs before auth. While the addon is off, every route answers `404 { "error": "Journey addon is not enabled" }`.
- **Access.** Routes are JWT-guarded. A journey is visible to its creator (`user_id`) and to anyone in `journey_contributors`. A journey the caller can't see answers `404 { "error": "Journey not found" }`.
- **Timestamps.** `created_at` / `updated_at` are epoch milliseconds. Dates (`entry_date`, trip dates) are `YYYY-MM-DD`.

`GET /api/journeys` → `{ "journeys": [...] }`, most recently updated first:

```jsonc
{ "id": 7, "user_id": 1, "title": "South Island loop", "subtitle": "…",
  "cover_gradient": null, "cover_image": "covers/nz.jpg",
  "status": "active",               // draft | active | completed | archived
  "created_at": 1767225600000, "updated_at": 1770000000000,
  "entry_count": 3,                 // skeletons excluded
  "photo_count": 1,
  "place_count": 2,                 // distinct non-empty entry location names
  "trip_date_min": "2026-02-01",    // across linked trips; null without any
  "trip_date_max": "2026-02-14" }
```

`GET /api/journeys/:id` → the journey row plus:

```jsonc
{
  "entries": [
    { "id": 101, "journey_id": 7, "author_id": 1,
      "type": "entry",              // entry | checkin | skeleton
      "title": "…", "story": "…",
      "entry_date": "2026-02-01", "entry_time": "14:30",
      "location_name": "Christchurch", "location_lat": -43.53, "location_lng": 172.63,
      "mood": "happy", "weather": "sunny",
      "tags": ["roadtrip"],                               // decoded array
      "pros_cons": { "pros": ["…"], "cons": ["…"] },      // or null
      "visibility": "private", "sort_order": 0,
      "source_trip_id": 20, "source_trip_name": "New Zealand",
      "photos": [ { "id": 1, "photo_id": 5, "file_path": "journey/a.jpg", … } ] }
  ],
  "gallery": [ … ],
  "trips": [ { "trip_id": 20, "title": "New Zealand", "start_date": "…", "end_date": "…",
               "cover_image": null, "currency": "NZD", "place_count": 12, "added_at": … } ],
  "contributors": [ { "user_id": 2, "username": "sam", "role": "editor",   // owner | editor | viewer
                      "avatar_url": "/uploads/avatars/a.png", … } ],
  "stats": { "entries": 1, "photos": 1, "places": 3 },
  "hide_skeletons": false,          // the viewer's own preference
  "dismissed_count": 0,
  "my_role": "owner"                // owner | editor | viewer
}
```

- **Entry order.** Entries come sorted by `entry_date`, then `sort_order`, then `id`. Dismissed suggestions are left out server-side.
- **Skeletons.** A `skeleton` entry is a placeholder the server derives from a linked trip's itinerary, for the user to write up. The app shows skeletons as muted "Suggested" rows unless `hide_skeletons` is set.
- **Stats.** `stats.entries` counts only `type: "entry"` rows; `stats.photos` counts the gallery.

## Offline behavior

- **Cache first.** Both screens paint their cached snapshot before refreshing.
  - If a refresh fails with a `NetworkException` and a snapshot exists, the snapshot stays on screen with an "Offline — showing … from …" banner and a retry.
  - With nothing cached, a `NetworkException` shows an explicit offline state with a retry. Any other error shows a generic error state.
- **Server-side removal.** The addon gate's 404 replaces the list (even a cached one) with an "addon isn't enabled" state. On the detail screen, any 404 (the journey was deleted or unshared, or the addon is off) replaces the cached copy with an explanation. The cached snapshot itself is left in place.
- **Per-account cache.** Snapshots are keyed by account scope: the configured public server URL plus the session's user id (the JWT `id` claim, via `AuthService.currentUserId`). A different account or server on the same device never sees another account's journeys.
  - Without a live session the repository neither reads nor writes the cache.
  - A corrupt entry reads as a cache miss.
  - Photo records, gallery items, and contributor avatars are not cached; each entry keeps only its photo count.
- **No outbox yet.** This slice is read-only. Every Journey write depends on the write-queue mechanism tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21). See [offline-first.md](offline-first.md).
