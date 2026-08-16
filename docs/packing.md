# Packing

Covers the list + create first slice of [issue #8](https://github.com/ryanmac8/trek-native-app/issues/8): the Packing tab of the trip dashboard, backed by a trip-scoped local cache. Checking items off, bags, sharing, templates, and category assignment are not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/packing/packing_item.dart](../lib/packing/packing_item.dart) | `PackingItem` — the packing item model, trimmed to what the list row renders (name, category, checked state). `id` is `null` exactly when the item was created locally and hasn't been confirmed by the server yet (`isPending`); `localId` is a client-generated key that survives that transition. `fromJson`/`toCacheJson`/`fromCacheJson` are the API and local-cache (de)serializers, respectively. |
| [lib/packing/packing_api.dart](../lib/packing/packing_api.dart) | `PackingApi` — thin wrapper around `GET /api/trips/:tripId/packing` and `POST /api/trips/:tripId/packing`. |
| [lib/packing/packing_local_store.dart](../lib/packing/packing_local_store.dart) | `PackingLocalStore`/`PreferencesPackingLocalStore` — persists each trip's cached packing item list as JSON in `shared_preferences`, keyed per trip id so multiple trips' packing lists cache independently, the same shape as `BudgetLocalStore`. |
| [lib/packing/packing_repository.dart](../lib/packing/packing_repository.dart) | `PackingRepository` — the offline-first front door the Packing tab uses instead of `PackingApi` directly. See below. |
| [lib/features/trips/trip_dashboard_screen.dart](../lib/features/trips/trip_dashboard_screen.dart) | `_PackingTab` — the Packing section of the trip dashboard's bottom-tab shell. Reads from the cache first, then refreshes from the network in the background. A FAB opens a dialog for the item's name and category, and creates it optimistically. |

## API contract

`GET /api/trips/:tripId/packing` returns `{ items: [...] }` (never a bare array), confirmed against Trek's actual `PackingController`/`packingService.listItems` (`server/src/nest/packing/`, `server/src/services/packingService.ts`). Each server row also carries three-tier sharing (`is_private`, `owner_id`, `recipients`), bag assignment (`bag_id`, `weight_grams`), `quantity`, `sort_order`, and co-contributors — only `name`, `category`, and `checked` are modeled client-side so far.

`POST /api/trips/:tripId/packing` takes `{ name, category? }` and returns `{ item }` (201). Only `name` is required — the server falls back to category `'Allgemein'` and `checked: false` when omitted, so those defaults aren't replicated client-side. A missing `name` is rejected with `400 { error: 'Item name is required' }`. Sharing (`is_private`/`visibility`/`recipient_ids`) and `quantity` are accepted server-side too (quantity only via `import`/bulk paths, not this create endpoint), but this first slice doesn't send them.

Toggling checked (`PUT .../:id`), delete (`DELETE .../:id`), reorder (`PUT .../reorder`), bags (`GET`/`POST`/`PUT`/`DELETE .../bags*`), templates (`GET .../templates`, `POST .../apply-template/:id`, `POST .../save-as-template`), sharing (`PUT .../:id/sharing`), contributors (`POST`/`DELETE .../:id/contributors*`), bulk import (`POST .../import`), and category assignees (`GET`/`PUT .../category-assignees*`) all exist server-side but aren't implemented in this client yet.

## Offline-first read/write (`PackingRepository`)

Per [offline-first.md](offline-first.md), the Packing tab never talks to `PackingApi` directly — it goes through `PackingRepository`, which keeps the local cache as the source of truth for what's shown. Trip-scoped like `BudgetRepository`, with the same pending-write shape:

- **`cachedItems(tripId)`** reads the local store only. The Packing tab calls this on load for an instant first paint before the network is involved at all.
- **`refreshItems(tripId)`** retries any pending (offline-created) items, then fetches the real list. On `NetworkException` it falls back to returning the cache instead of failing — only when the cache is empty does the exception propagate, so the caller can show an explicit offline state.
- **`createItem(tripId, ...)`** writes an optimistic `PackingItem` to the cache immediately (`id: null`, so `isPending` is `true`) before attempting the network call. If the create can't reach the server, the pending item stays queued in the cache rather than being lost, and the next `refreshItems()` call (screen load, pull-to-refresh) retries it. A genuine rejection (validation, permissions, a 5xx) instead rolls back the optimistic write and rethrows.

The Packing tab renders a still-pending item with a "Syncing…" subtitle and a sync icon instead of its usual checked/unchecked icon.

## What's still open

- Checking/unchecking an item (the core packing interaction) and item delete/reorder (the rest of `PackingApi`/`PackingRepository` for issue #8).
- Bags (packing containers, weight limits, member assignment) and moving items between them.
- Three-tier sharing (Common/Personal/Shared) and per-item contributors — the bulk of issue #8's collaborative-packing scope.
- Templates (list, apply, save-as) and bulk import.
- Category assignees and a category picker in the create dialog (free text for now).
- A local write queue for the rest of the mutations, once they exist — see docs/offline-first.md's note on conflicts and the durable outbox tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21).
