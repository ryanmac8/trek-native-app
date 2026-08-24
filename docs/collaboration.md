# Collaboration

Covers the notes list + create + edit + delete slice of [issue #13](https://github.com/ryanmac8/trek-native-app/issues/13): the Notes tab of the trip dashboard, backed by a trip-scoped local cache. Pinning, file attachments, member list/add/remove, polls, and chat are not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/collab/collab_note.dart](../lib/collab/collab_note.dart) | `CollabNote` — the note model, trimmed to what the list row renders (title, content, category, color, pinned, author username). `id` is `null` exactly when the note was created locally and hasn't been confirmed by the server yet (`isPending`); `localId` is a client-generated key that survives that transition, the same shape as `TodoItem`. `needsSync` and `pendingDelete` track an already-synced note's own offline edit/delete queue — distinct from `isPending`, which only applies to a note that's never reached the server at all. `fromJson`/`toCacheJson`/`fromCacheJson` are the API and local-cache (de)serializers, respectively. |
| [lib/collab/collab_api.dart](../lib/collab/collab_api.dart) | `CollabApi` — thin wrapper around `GET`/`POST /api/trips/:tripId/collab/notes` and `PUT`/`DELETE /api/trips/:tripId/collab/notes/:id`. |
| [lib/collab/collab_local_store.dart](../lib/collab/collab_local_store.dart) | `CollabLocalStore`/`PreferencesCollabLocalStore` — persists each trip's cached note list as JSON in `shared_preferences`, keyed per trip id so multiple trips' notes cache independently, the same shape as `TodoLocalStore`. |
| [lib/collab/collab_repository.dart](../lib/collab/collab_repository.dart) | `CollabRepository` — the offline-first front door the Notes tab uses instead of `CollabApi` directly. See below. |
| [lib/features/trips/trip_dashboard_screen.dart](../lib/features/trips/trip_dashboard_screen.dart) | `_NotesTab` — the Notes section of the trip dashboard's bottom-tab shell. Reads from the cache first, then refreshes from the network in the background. A FAB opens a dialog for a new note's title, content, and category, and creates it optimistically. Each row's overflow menu opens the same form pre-filled for editing, or deletes the note after a confirmation dialog — both apply optimistically the same way create does. A pinned note shows a pin icon; a note with an unsynced create or edit shows a "Syncing…" subtitle and a sync icon. |

## API contract

`GET /api/trips/:tripId/collab/notes` returns `{ notes: [...] }` (never a bare array), confirmed against Trek's actual `CollabController`/`collabService.listNotes` (`server/src/nest/collab/`, `server/src/services/collabService.ts`), sorted pinned-first then by most recently updated. Each server row also carries `website`, `attachments` (uploaded files), `avatar_url`, `user_id`, `created_at`, and `updated_at` — only `title`, `content`, `category`, `color`, `pinned`, and the author's `username` are modeled client-side so far.

`POST /api/trips/:tripId/collab/notes` takes `{ title, content?, category?, color?, website?, pinned? }` and returns `{ note }` (201). Only `title` is required — a missing `title` is rejected with `400 { error: 'Title is required' }`. `website` and `pinned` are accepted server-side but this slice doesn't send them; `category` defaults server-side to `'General'` and `color` to `'#6366f1'` when omitted.

`PUT /api/trips/:tripId/collab/notes/:id` takes `{ title?, content?, category?, color?, pinned?, website? }` and returns `{ note }`; a missing note is `404 { error: 'Note not found' }`, and any collaborator with edit permission (not just the note's author) may update it — a caller without it gets `403 { error: 'No permission' }`. `title` and `category` are applied with a `COALESCE`-style fallback server-side, so sending either blank leaves the existing value untouched; `content` checks for the field being present at all, so it's the one field that can actually be cleared by sending it blank. `CollabApi.updateNote` always sends `content` (even blank) for that reason, and omits `category` entirely when blank (matching `createNote`'s convention, since blanking it wouldn't take effect anyway).

`DELETE /api/trips/:tripId/collab/notes/:id` returns `{ success: true }`; a missing note is `404 { error: 'Note not found' }`, gated by the same edit permission as update.

The note-file endpoints (`POST`/`DELETE .../notes/:id/files*`) exist server-side but aren't implemented in this client yet. Neither are the polls (`.../polls*`) or chat (`.../messages*`) sub-resources, or trip member list/add/remove.

## Offline-first read/write (`CollabRepository`)

Per [offline-first.md](offline-first.md), the Notes tab never talks to `CollabApi` directly — it goes through `CollabRepository`, which keeps the local cache as the source of truth for what's shown. Trip-scoped like `TodoRepository`, with the same pending-write shape:

- **`cachedNotes(tripId)`** reads the local store only. The Notes tab calls this on load for an instant first paint before the network is involved at all.
- **`refreshNotes(tripId)`** retries every not-yet-confirmed write — offline-created notes (`isPending`), offline edits (`needsSync`), and offline deletes (`pendingDelete`) — then fetches the real list. A note this call just retried into existence (or one still pending, offline) is kept even if the freshly-fetched server list doesn't (yet) include it, since a retry can race the list call; conversely, a server note whose local copy still has an unsynced edit keeps the local (edited) version instead of being overwritten by the stale server copy. Tombstoned (`pendingDelete`) notes stay out of the returned list but remain in the cache so the delete keeps retrying. On `NetworkException` (from any of the retries or the list call) it falls back to returning the non-tombstoned part of the cache instead of failing — only when nothing would be visible does the exception propagate, so the caller can show an explicit offline state.
- **`createNote(tripId, ...)`** writes an optimistic `CollabNote` to the cache immediately (`id: null`, so `isPending` is `true`) before attempting the network call. If the create can't reach the server, the pending note stays queued in the cache rather than being lost, and the next `refreshNotes()` call (screen load, pull-to-refresh) retries it. A genuine rejection (validation, permissions, a 5xx) instead rolls back the optimistic write and rethrows.
- **`updateNote(tripId, note, ...)`** applies the edit to the cache immediately. For an already-synced note this also marks it `needsSync` and attempts the `PUT`; if that can't reach the server the edit stays visible (not rolled back) and queued for the next `refreshNotes()`, while a genuine rejection rolls back to the pre-edit note and rethrows. For a note that's still `isPending` (never synced at all), there's no `PUT` to make yet — the edit just updates the queued note's fields in place, and the eventual create (or its retry) sends the new values itself.
- **`deleteNote(tripId, note)`** removes a still-`isPending` note from the cache outright (nothing was ever told to the server). An already-synced note is hidden from the list immediately but kept in the cache tombstoned (`pendingDelete`) until the `DELETE` actually confirms — so an offline delete is retried by `refreshNotes()` instead of forgotten. A `404` (already deleted elsewhere) is treated as success; any other rejection restores the note and rethrows.

## What's still open

- Pinning/unpinning from the client (the `pinned` flag is read and displayed, but only ever set server-side today).
- File attachments on a note.
- Trip member list, add/remove.
- Polls: create, vote, view results, close, delete.
- Chat: send message, react, delete own message, unread indicators.
- A category/color picker in the create/edit dialog (free text for now).
- A local write queue for the rest of the mutations, once they exist — see docs/offline-first.md's note on conflicts and the durable outbox tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21).
