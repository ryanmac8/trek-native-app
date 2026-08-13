# Tags

Covers the list + create slice of [issue #6](https://github.com/ryanmac8/trek-native-app/issues/6): the `/tags` screen, backed by a local cache of the user's tags. Tag edit/delete, applying/removing a tag on a place, and filtering the place pool by tag are not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/tags/tag.dart](../lib/tags/tag.dart) | `Tag` — the tag model. `id` is `null` exactly when the tag was created locally and hasn't been confirmed by the server yet (`isPending`); `localId` is a client-generated key that survives that transition. `fromJson`/`toCacheJson`/`fromCacheJson` are the API and local-cache (de)serializers, respectively. |
| [lib/tags/tags_api.dart](../lib/tags/tags_api.dart) | `TagsApi` — thin wrapper around `GET /api/tags` and `POST /api/tags`. |
| [lib/tags/tags_local_store.dart](../lib/tags/tags_local_store.dart) | `TagsLocalStore`/`PreferencesTagsLocalStore` — persists the cached tag list as JSON in `shared_preferences`. Not keyed per trip, unlike `PlacesLocalStore` — tags belong to the user, not a trip. |
| [lib/tags/tags_repository.dart](../lib/tags/tags_repository.dart) | `TagsRepository` — the offline-first front door the tags screen uses instead of `TagsApi` directly. See below. |
| [lib/features/tags/tags_list_screen.dart](../lib/features/tags/tags_list_screen.dart) | `TagsListScreen` — the `/tags` route. Reads from the cache first, then refreshes from the network in the background. A FAB opens a dialog for the tag's name and a preset color swatch. |

## API contract

`GET /api/tags` returns `{ tags: [...] }` (never a bare array), confirmed against Trek's actual `TagsController`/`tagSchema` (`server/src/nest/tags/`). Unlike places, tags aren't trip-scoped — every endpoint is scoped to the authenticated user's own tags.

`POST /api/tags` takes `{ name, color? }` and returns `{ tag }` (201). Only `name` is required; the server falls back to `#10b981` for `color` when omitted, so that default isn't replicated client-side. A missing `name` is rejected with `400 { error: 'Tag name is required' }`.

Update (`PUT /api/tags/:id`), delete (`DELETE /api/tags/:id`), and applying/removing a tag on a place all exist server-side but aren't implemented in this client yet.

## Offline-first read/write (`TagsRepository`)

Per [offline-first.md](offline-first.md), `TagsListScreen` never talks to `TagsApi` directly — it goes through `TagsRepository`, which keeps the local cache as the source of truth for what's shown. Mirrors `TripsRepository`'s shape:

- **`cachedTags()`** reads the local store only. `TagsListScreen` calls this on load for an instant first paint before the network is involved at all.
- **`refreshTags()`** retries any pending (offline-created) tags, then fetches the real list. On `NetworkException` it falls back to returning the cache instead of failing — only when the cache is empty does the exception propagate, so the caller can show an explicit offline state.
- **`createTag()`** writes an optimistic `Tag` to the cache immediately (`id: null`, so `isPending` is `true`) before attempting the network call. If the create can't reach the server, the pending tag stays queued in the cache rather than being lost, and the next `refreshTags()` call (screen load, pull-to-refresh) retries it. A genuine rejection (validation, permissions, a 5xx) instead rolls back the optimistic write and rethrows.

`TagsListScreen` renders a still-pending tag with a "Syncing…" subtitle and a sync icon instead of a normal row.

## What's still open

- Tag edit and delete (the rest of `TagsApi`/`TagsRepository` for issue #6).
- Applying/removing a tag on a place, and filtering the place pool by one or more tags — both depend on the place pool ([#5](https://github.com/ryanmac8/trek-native-app/issues/5)) existing to filter against.
- A shared local-persistence/sync mechanism for the rest of the data model (issue #21) — this cache is deliberately scoped to tags only, not a general pattern yet.
