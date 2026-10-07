# Feature flags (server add-ons)

Trek's feature flags live on the server, not in the app: each self-hosted instance has **add-ons** that an admin switches on and off in Trek's admin panel. When an add-on is off, its REST routes answer `404 { "error": "<Name> addon is not enabled" }` and the web client hides its UI. The app reads the same flags so it can hide the same UI instead of showing screens that can only fail.

## The contract: `GET /api/addons`

JWT-guarded (authenticated `ApiClient`), no parameters. Served by `AddonsController`/`AddonsService.list()` in Trek's `server/src/nest/addons/`.

```json
{
  "collabFeatures": { "chat": true, "notes": true, "links": true, "polls": true, "whatsnext": true },
  "bagTracking": false,
  "addons": [
    { "id": "packing", "name": "Lists", "type": "trip", "icon": "ListChecks", "enabled": true },
    { "id": "immich", "name": "Immich", "type": "photo_provider", "icon": "Image", "enabled": true,
      "config": { }, "fields": [ ] }
  ]
}
```

- `addons` lists **enabled add-ons only**, ordered by the server's `sort_order`. Anything absent is off.
- `type` is `trip`, `global`, `integration`, or `photo_provider`. Photo providers (Immich, Synology Photos) appear only while the `journey` add-on is on; their `config`/`fields` describe the provider settings form and aren't modeled by the app.
- `collabFeatures` are the Collab add-on's sub-switches. They're opt-out on the server (a never-set switch is on), so a missing key parses as `true`.
- `bagTracking` is opt-in (default off).

### Add-on ids

| Id | Name | Type | What it gates | Fresh-install default |
| --- | --- | --- | --- | --- |
| `packing` | Lists | trip | packing lists **and** todos | on |
| `budget` | Costs | trip | trip budget | on |
| `documents` | Documents | trip | trip files | on |
| `collab` | Collab | trip | notes, polls, chat (each also gated by `collabFeatures`) | on |
| `roadtrip` | Road trip | trip | drive legs, stops, timing | off |
| `vacay` | Vacay | global | vacation-day planner | on |
| `atlas` | Atlas | global | visited countries / bucket list | on |
| `journey` | Journey | global | travel journal (and photo providers) | off |
| `collections` | Collections | global | cross-trip place library | off |
| `mcp` | MCP | integration | AI assistant integration | off |
| `naver_list_import` | Naver List Import | integration | Naver Maps list import | on |
| `airtrail` | AirTrail | integration | flight sync | off |
| `dawarich` | Dawarich | integration | location-history suggestions | off |
| `llm_parsing` | AI Parsing | integration | booking-import LLM fallback | off |

`memories` is not a row: like the web client, `AddonFlags.isEnabled(AddonIds.memories)` is true whenever any `photo_provider` entry is enabled.

## Pieces

| File | Role |
| --- | --- |
| [lib/addons/addon_flags.dart](../lib/addons/addon_flags.dart) | `AddonIds` constants; `ServerAddon`, `CollabFeatures`, `AddonFlags` (parsing, `isEnabled`, `freshInstallDefaults`); `CachedAddonFlags` (flags + `fetchedAt`). |
| [lib/addons/addons_api.dart](../lib/addons/addons_api.dart) | `AddonsApi.fetchFlags()` — the `GET /api/addons` call. A non-object or wrongly typed body is a `FormatException`. |
| [lib/addons/addon_flags_local_store.dart](../lib/addons/addon_flags_local_store.dart) | `AddonFlagsLocalStore` / `PreferencesAddonFlagsLocalStore` — one JSON entry per server in `shared_preferences` (key `trek.addons.flags.<public server URL>`). A corrupt entry reads as a miss. |
| [lib/addons/addon_flags_repository.dart](../lib/addons/addon_flags_repository.dart) | `AddonFlagsRepository` — `cachedFlags()` (local only, never throws) and `refreshFlags()` (fetch, cache best-effort, return; `ApiException`s propagate). |
| [lib/addons/addon_flags_controller.dart](../lib/addons/addon_flags_controller.dart) | `AddonFlagsController` (a Riverpod `Notifier`) and `AddonFlagsState` — what the UI watches. |

Providers (in [lib/app/providers.dart](../lib/app/providers.dart)): `addonsApiProvider`, `addonFlagsLocalStoreProvider`, `addonFlagsCacheScopeProvider`, `addonFlagsRepositoryProvider`, and `addonFlagsProvider`.

## Offline behavior

Flags are instance configuration, not per-user data, so the cache is scoped by server (public URL) only; it's not cleared when switching accounts on the same server. Without a configured server nothing is cached.

`addonFlagsProvider` never waits on the network:

1. It starts at `AddonFlags.freshInstallDefaults` (`source: defaults`) — what `seedAddons` in Trek's `server/src/db/seeds.ts` enables — so a first launch while offline shows the stock feature set rather than hiding everything.
2. It swaps in the cached flags for the current server as soon as they're read (`source: cache`, with their `fetchedAt`).
3. It refreshes in the background; success replaces the flags (`source: server`) and updates the cache.

A refresh that fails — offline (`NetworkException`), 401, 5xx, or a malformed body — keeps whatever flags were showing and sets `refreshFailed: true`; `AddonFlagsController.refresh()` can be called again later and clears it on success. Flags are read-only in the app (toggling them is an admin action), so there's nothing to queue.

## Where the UI gates on them

`ref.watch(addonFlagsProvider).isEnabled(AddonIds.x)`.

- `TripDashboardScreen` shows Budget only while `budget` is on, and Packing and Todos only while `packing` is on. Days and Places are always shown. If the selected tab disappears, the dashboard falls back to the first tab. Otherwise the selection is kept by tab, not by position.
