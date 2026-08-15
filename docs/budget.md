# Budget

Covers the list + create first slice of [issue #7](https://github.com/ryanmac8/trek-native-app/issues/7): the Budget tab of the trip dashboard, backed by a trip-scoped local cache. Per-person splits, payers, settlements, item edit/delete/reorder, and category management are not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/budget/budget_item.dart](../lib/budget/budget_item.dart) | `BudgetItem` — the budget line item model, trimmed to what the list row renders (name, category, total price/currency, note). `id` is `null` exactly when the item was created locally and hasn't been confirmed by the server yet (`isPending`); `localId` is a client-generated key that survives that transition. `fromJson`/`toCacheJson`/`fromCacheJson` are the API and local-cache (de)serializers, respectively. |
| [lib/budget/budget_api.dart](../lib/budget/budget_api.dart) | `BudgetApi` — thin wrapper around `GET /api/trips/:tripId/budget` and `POST /api/trips/:tripId/budget`. |
| [lib/budget/budget_local_store.dart](../lib/budget/budget_local_store.dart) | `BudgetLocalStore`/`PreferencesBudgetLocalStore` — persists each trip's cached budget item list as JSON in `shared_preferences`, keyed per trip id so multiple trips' budgets cache independently, the same shape as `PlacesLocalStore`. |
| [lib/budget/budget_repository.dart](../lib/budget/budget_repository.dart) | `BudgetRepository` — the offline-first front door the Budget tab uses instead of `BudgetApi` directly. See below. |
| [lib/features/trips/trip_dashboard_screen.dart](../lib/features/trips/trip_dashboard_screen.dart) | `_BudgetTab` — the Budget section of the trip dashboard's bottom-tab shell. Reads from the cache first, then refreshes from the network in the background. A FAB opens a dialog for the item's name, category, and total price, and creates it optimistically. |

## API contract

`GET /api/trips/:tripId/budget` returns `{ items: [...] }` (never a bare array), confirmed against Trek's actual `BudgetController`/`budgetService.listBudgetItems` (`server/src/nest/budget/`, `server/src/services/budgetService.ts`). Each server row also carries `members`/`payers` (per-person splits and who paid what), `paid_by_user_id`, `reservation_id`, and `exchange_rate` — only `name`, `category`, `total_price`, `currency`, `persons`, `days`, `note`, and `expense_date` are modeled client-side so far.

`POST /api/trips/:tripId/budget` takes `{ name, category?, total_price?, persons?, days?, note?, expense_date? }` and returns `{ item }` (201). Only `name` is required — the server falls back to `'other'` for `category` and `0` for `total_price` when omitted, so those defaults aren't replicated client-side. A missing `name` is rejected with `400 { error: 'Name is required' }`. `payers`/`members` (splits) and `reservation_id` are accepted server-side too, but this first slice doesn't send them.

Update (`PUT .../:id`), delete (`DELETE .../:id`), member/payer management (`PUT .../:id/members`, `.../:id/payers`, `.../:id/members/:userId/paid`), settlements (`GET`/`POST`/`PUT`/`DELETE .../settlements`), the per-person summary (`GET .../summary/per-person`), and item/category reordering all exist server-side but aren't implemented in this client yet.

## Offline-first read/write (`BudgetRepository`)

Per [offline-first.md](offline-first.md), the Budget tab never talks to `BudgetApi` directly — it goes through `BudgetRepository`, which keeps the local cache as the source of truth for what's shown. Trip-scoped like `PlacesRepository`, with the same pending-write shape as `TagsRepository`:

- **`cachedItems(tripId)`** reads the local store only. The Budget tab calls this on load for an instant first paint before the network is involved at all.
- **`refreshItems(tripId)`** retries any pending (offline-created) items, then fetches the real list. On `NetworkException` it falls back to returning the cache instead of failing — only when the cache is empty does the exception propagate, so the caller can show an explicit offline state.
- **`createItem(tripId, ...)`** writes an optimistic `BudgetItem` to the cache immediately (`id: null`, so `isPending` is `true`) before attempting the network call. If the create can't reach the server, the pending item stays queued in the cache rather than being lost, and the next `refreshItems()` call (screen load, pull-to-refresh) retries it. A genuine rejection (validation, permissions, a 5xx) instead rolls back the optimistic write and rethrows.

The Budget tab renders a still-pending item with a "Syncing…" subtitle and a sync icon instead of its usual price trailing widget.

## What's still open

- Item edit, delete, and reorder (the rest of `BudgetApi`/`BudgetRepository` for issue #7).
- Per-person splits and payers (`members`/`payers` on create, plus their dedicated endpoints), settlements, and the per-person summary — the bulk of issue #7's expense-splitting scope.
- Category management (`reorder/categories`) and a category picker in the create dialog (free text for now).
- Linking a budget item to a reservation (`reservation_id`), once reservations ([#11](https://github.com/ryanmac8/trek-native-app/issues/11)) exist.
- A local write queue for the rest of the mutations, once they exist — see docs/offline-first.md's note on conflicts and the durable outbox tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21).
