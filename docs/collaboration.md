# Collaboration

Covers the notes list + create slice of [issue #13](https://github.com/ryanmac8/trek-native-app/issues/13): the Notes tab of the trip dashboard, backed by a trip-scoped local cache. Editing, pinning, file attachments, member list/add/remove, polls, and chat are not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/collab/collab_note.dart](../lib/collab/collab_note.dart) | `CollabNote` — the note model, trimmed to what the list row renders (title, content, category, color, pinned, author username). `id` is `null` exactly when the note was created locally and hasn't been confirmed by the server yet (`isPending`); `localId` is a client-generated key that survives that transition, the same shape as `TodoItem`. `fromJson`/`toCacheJson`/`fromCacheJson` are the API and local-cache (de)serializers, respectively. |
| [lib/collab/collab_api.dart](../lib/collab/collab_api.dart) | `CollabApi` — thin wrapper around `GET`/`POST /api/trips/:tripId/collab/notes`. |
| [lib/collab/collab_local_store.dart](../lib/collab/collab_local_store.dart) | `CollabLocalStore`/`PreferencesCollabLocalStore` — persists each trip's cached note list as JSON in `shared_preferences`, keyed per trip id so multiple trips' notes cache independently, the same shape as `TodoLocalStore`. |
| [lib/collab/collab_repository.dart](../lib/collab/collab_repository.dart) | `CollabRepository` — the offline-first front door the Notes tab uses instead of `CollabApi` directly. See below. |
| [lib/features/trips/trip_dashboard_screen.dart](../lib/features/trips/trip_dashboard_screen.dart) | `_NotesTab` — the Notes section of the trip dashboard's bottom-tab shell. Reads from the cache first, then refreshes from the network in the background. A FAB opens a dialog for the note's title, content, and category, and creates it optimistically. A pinned note shows a pin icon; a still-pending (offline-created) note shows a "Syncing…" subtitle instead. |

## API contract

`GET /api/trips/:tripId/collab/notes` returns `{ notes: [...] }` (never a bare array), confirmed against Trek's actual `CollabController`/`collabService.listNotes` (`server/src/nest/collab/`, `server/src/services/collabService.ts`), sorted pinned-first then by most recently updated. Each server row also carries `website`, `attachments` (uploaded files), `avatar_url`, `user_id`, `created_at`, and `updated_at` — only `title`, `content`, `category`, `color`, `pinned`, and the author's `username` are modeled client-side so far.

`POST /api/trips/:tripId/collab/notes` takes `{ title, content?, category?, color?, website?, pinned? }` and returns `{ note }` (201). Only `title` is required — a missing `title` is rejected with `400 { error: 'Title is required' }`. `website` and `pinned` are accepted server-side but this slice doesn't send them; `category` defaults server-side to `'General'` and `color` to `'#6366f1'` when omitted.

`PUT /api/trips/:tripId/collab/notes/:id`, `DELETE /api/trips/:tripId/collab/notes/:id`, and the note-file endpoints (`POST`/`DELETE .../notes/:id/files*`) exist server-side but aren't implemented in this client yet. Neither are the polls (`.../polls*`) or chat (`.../messages*`) sub-resources, or trip member list/add/remove.

## Offline-first read/write (`CollabRepository`)

Per [offline-first.md](offline-first.md), the Notes tab never talks to `CollabApi` directly — it goes through `CollabRepository`, which keeps the local cache as the source of truth for what's shown. Trip-scoped like `TodoRepository`, with the same pending-write shape, trimmed to this slice's list + create:

- **`cachedNotes(tripId)`** reads the local store only. The Notes tab calls this on load for an instant first paint before the network is involved at all.
- **`refreshNotes(tripId)`** retries any not-yet-synced (offline-created) notes, then fetches the real list. A note this call just retried into existence (or one still pending, offline) is kept even if the freshly-fetched server list doesn't (yet) include it, since the retry can race the list call. On `NetworkException` (from the retries or the list call) it falls back to returning the cache instead of failing — only when the cache is empty does the exception propagate, so the caller can show an explicit offline state.
- **`createNote(tripId, ...)`** writes an optimistic `CollabNote` to the cache immediately (`id: null`, so `isPending` is `true`) before attempting the network call. If the create can't reach the server, the pending note stays queued in the cache rather than being lost, and the next `refreshNotes()` call (screen load, pull-to-refresh) retries it. A genuine rejection (validation, permissions, a 5xx) instead rolls back the optimistic write and rethrows.

## What's still open

- Editing and deleting a note.
- Pinning/unpinning from the client (the `pinned` flag is read and displayed, but only ever set server-side today).
- File attachments on a note.
- Trip member list, add/remove.
- Polls: create, vote, view results, close, delete.
- Chat: send message, react, delete own message, unread indicators.
- A category/color picker in the create dialog (free text for now).
- A local write queue for the rest of the mutations, once they exist — see docs/offline-first.md's note on conflicts and the durable outbox tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21).
