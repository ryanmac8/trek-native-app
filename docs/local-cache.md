# Local Read Cache

The shared read path behind the [offline-first](offline-first.md) principle. Screens render cached server data straight away, and the cache revalidates it against the server in the background (stale-while-revalidate). The layer is feature-agnostic: a feature describes each read as a `CacheResource` and gets back `CacheSnapshot`s. Tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21) and the "local caching strategy" item of [#2](https://github.com/ryanmac8/trek-native-app/issues/2).

## Pieces (`lib/cache/`)

| Piece | Role |
| --- | --- |
| `CacheEntry` | One cached response: the JSON-safe `data`, `fetchedAt`, the response `etag`, the `schemaVersion` it was written under, and an `invalidated` flag. |
| `CacheStore` / `PreferencesCacheStore` | Durable key → entry storage. `PreferencesCacheStore` writes each entry as one JSON string in `shared_preferences` under `trek.cache.<key>`. A corrupt entry reads as a miss. |
| `CachePolicy` | Per-resource `maxAge` (default 5 minutes) and `schemaVersion` (default 1). |
| `CacheResource<T>` | One cacheable read: its `key`, a `fetch(etag)` function, and `decode`/`encode` between JSON and the feature's model. `CacheResource.get(client, path, …)` builds the usual conditional `GET`. |
| `CacheSnapshot<T>` | What a screen renders: `data`, `fetchedAt`, `source`, `isStale`, `isRefreshing`, `refreshError`, plus `hasData` and `isOffline`. |
| `ReadCache` | The service: `read`, `refresh`, `watch`, `put`/`update`, `invalidate`/`invalidatePrefix`, `evict`/`evictPrefix`, `clearAll`. |
| `accountCacheScope` / `jwtAccountId` (`cache_scope.dart`) | Builds the scope string that separates accounts and servers. |

## Keys and scope

A resource key is path-like and unique per resource, for example `trips`, `trips/20`, or `trips/20/days`. Prefix operations rely on this, so `invalidatePrefix('trips/20/')` reaches everything under trip 20.

Entries are stored under `<scope>|<key>`. The scope is `<server public URL>#<account id>`. The account id is the `id` claim of the stored session JWT, which Trek signs as `{ id, pv, remember? }`. The scope is built from local storage only, so it doesn't depend on connectivity. An expired session still produces a scope, which keeps cached data readable until the user logs in again.

With no server configured or no stored session, the scope is empty. Entries are then held in memory for the session and never persisted.

Each account on each server only ever sees its own entries. Prefix invalidation and eviction only touch the current scope. `clearAll` removes every scope.

## Reading

| Call | Network | Result |
| --- | --- | --- |
| `read(resource)` | Never | The cached snapshot, or one with `hasData == false`. |
| `refresh(resource)` | Always | Revalidates, then returns the resulting snapshot. Concurrent calls for the same resource share one request. |
| `watch(resource)` | When needed | Emits the cached snapshot first. Revalidates on listen when nothing usable is cached or the entry is stale. Emits again whenever the entry changes (from any caller) or a revalidation starts or finishes. |

`CacheSnapshot.source` is `none` (nothing cached), `cache` (read from storage, not yet confirmed this session), or `server` (fetched or revalidated during this session).

`ReadCache` keeps a write-through in-memory copy of every entry it touches, so a failed storage write never hides fresh data from the current session. None of its methods throw. Storage failures read as misses, and fetch failures go into `refreshError`.

## Revalidation

Trek's server runs on Express, which attaches a weak `ETag` to every JSON response (e.g. `W/"38-aVDNTEL9…"`) and answers `If-None-Match` with `304 Not Modified`. `ApiClient.getIfChanged(path, {query, etag})` returns `Modified(body, etag)` or `NotModified()`, and maps errors exactly as `get` does.

`refresh` sends the stored ETag and handles the outcome:

| Outcome | Effect on the entry | `refreshError` |
| --- | --- | --- |
| 200 | Replaced by the new body and ETag; `fetchedAt` = now; no longer invalidated. The body must decode first, so a malformed body never replaces good data. | `null` |
| 304 | Data kept; `fetchedAt` = now; no longer invalidated. | `null` |
| 403 (`ForbiddenException`) or 404 | Evicted. Access was revoked or the resource is gone. | the exception |
| No response (`NetworkException`) | Kept | `NetworkException` (`isOffline`) |
| 401, 5xx, other errors, an undecodable body | Kept | the error |

## Invalidation rules

| Rule | Trigger | Effect |
| --- | --- | --- |
| Age | `now - fetchedAt >= maxAge` | Stale: still shown, revalidated by the next `watch`. |
| Explicit | `invalidate(key)` / `invalidatePrefix(prefix)`, e.g. after a write to the same data has synced | Stale, regardless of age. Data kept. |
| Schema | Entry's `schemaVersion` ≠ the policy's | Discarded on read. A feature bumps `schemaVersion` when its cached JSON shape or decoder changes incompatibly. |
| Undecodable | `decode` throws on cached data | Read as a miss; overwritten by the next successful refresh. |
| Gone | Refresh returns 403 or 404 | Evicted. |
| Removal | `evict(key)` / `evictPrefix(prefix)`, `clearAll()` | Removed. |

Age never hides data. Offline, a stale entry is all there is, so it stays visible with `isStale` set.

## Local edits

`put(resource, value)` replaces the cached data with a local edit, and `update(resource, change)` applies a function to the current value. Every watcher sees the change. The entry keeps its `fetchedAt` but drops its ETag. Without an ETag, the next revalidation downloads the server's version instead of getting a 304 for the pre-edit one. When nothing was cached before, the new entry starts out invalidated.

A revalidation replaces the entry with whatever the server returns. A feature whose writes are still queued for sync re-applies them on top after a refresh, or holds off revalidating until they have synced.

## Riverpod wiring (`lib/app/providers.dart`)

| Provider | Provides |
| --- | --- |
| `cacheStoreProvider` | `PreferencesCacheStore` |
| `readCacheProvider` | The app's single `ReadCache`, scoped by `accountCacheScope` over `serverConfigStorageProvider` and `tokenStorageProvider`. Disposed with the container. |

## What is and isn't cached

- Cached: server reads for trip data and other per-account data that a screen shows.
- Not cached: the session token (secure storage, see [networking-auth.md](networking-auth.md)), server configuration (its own storage), and anything secret.
- `shared_preferences` suits small and medium payloads. `CacheStore` is the seam for moving to a database if entry sizes require it.
