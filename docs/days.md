# Days

Covers part of [issue #4](https://github.com/ryanmac8/trek-native-app/issues/4): the Days tab of the trip dashboard, a per-day screen, and day notes, all backed by a trip-scoped local cache. Day create/reorder/edit and place assignments are not built yet. Place assignments depend on the places data model ([#5](https://github.com/ryanmac8/trek-native-app/issues/5)).

## Pieces

| File | Purpose |
| --- | --- |
| [lib/days/day.dart](../lib/days/day.dart) | `Day`, the day model. `fromJson`/`toCacheJson`/`fromCacheJson` are the API and local-cache (de)serializers. `assignmentCount` comes from the length of the response's nested `assignments` array, since no place model exists yet to render those assignments. `noteItems` holds the day's notes, in server order. |
| [lib/days/day_note.dart](../lib/days/day_note.dart) | `DayNote`, one day note. A note created offline has a `localId` and no `id` until its create syncs. `isPending` marks a note whose latest local change hasn't reached the server. |
| [lib/days/days_api.dart](../lib/days/days_api.dart) | `DaysApi` wraps `GET /api/trips/:tripId/days` and the day-note `POST`/`PUT`/`DELETE` endpoints. |
| [lib/days/days_local_store.dart](../lib/days/days_local_store.dart) | `DaysLocalStore`/`PreferencesDaysLocalStore` persist each trip's cached day list, notes included, as JSON in `shared_preferences` under `trek.days.cache.<tripId>`. |
| [lib/days/day_note_outbox.dart](../lib/days/day_note_outbox.dart) | `DayNoteOutbox`/`PreferencesDayNoteOutbox` hold the per-trip queue of note writes that haven't reached the server (`trek.day_notes.pending.<tripId>`). `DayNoteOutbox.enqueue` keeps at most one queued op per note. |
| [lib/days/days_repository.dart](../lib/days/days_repository.dart) | `DaysRepository` is the offline-first front door for days and notes. Screens use it instead of calling `DaysApi` directly. See below. |
| [lib/design/day_note_style.dart](../lib/design/day_note_style.dart) | `DayNoteStyle` holds Trek's note icon set (lucide names mapped to Material icons) and its seven-color note palette. |
| [lib/features/trips/trip_dashboard_screen.dart](../lib/features/trips/trip_dashboard_screen.dart) | `_DaysTab` is the Days section of the trip dashboard. It paints from the cache, then refreshes from the network in the background. Each row shows place and note counts. Tapping a row opens `DayDetailScreen`. |
| [lib/features/trips/day_detail_screen.dart](../lib/features/trips/day_detail_screen.dart) | `DayDetailScreen` shows one day's notes as cards (icon, color, title, details, and an unsynced marker), with add and edit actions and pull-to-refresh. |
| [lib/features/trips/day_note_editor_sheet.dart](../lib/features/trips/day_note_editor_sheet.dart) | `showDayNoteEditor` is the add/edit bottom sheet: title, details, icon, color, and delete (behind a confirmation) when editing. |

## API contract

`GET /api/trips/:tripId/days` returns `{ days: [...] }`, never a bare array. Each day carries `id`, `trip_id`, `day_number`, `date` (`YYYY-MM-DD`, or `null` for an undated trip), `notes`, `title`, plus nested `assignments` and `notes_items` arrays. The server generates days from a trip's date range when the trip is created (see [trips.md](trips.md)), so the client never creates the initial set.

The client models `day_number`, `date`, `notes`, `title`, the assignment count, and `notes_items` in full. The full assignment/place shape and the day create (`POST`), reorder (`PUT .../reorder`), update (`PUT .../:id`), and delete (`DELETE .../:id`) endpoints exist on the server, but this client doesn't implement them yet.

### Day notes

A day note is a row of Trek's `day_notes` table: `id`, `day_id`, `trip_id`, `text`, `time`, `icon`, `color`, `sort_order` (a real number), and `created_at` (SQLite `YYYY-MM-DD HH:MM:SS`, UTC). The server lists a day's notes ordered by `sort_order`, then `created_at`.

| Field | Meaning |
| --- | --- |
| `text` | The note's title. Required and non-blank on create; at most 500 characters. |
| `time` | Optional secondary text, at most 2000 characters. Despite the column name, Trek's web client uses it as the note's body (it renders it as Markdown); this client shows it as plain text, labeled "Details". |
| `icon` | A lucide icon name from the web client's `NOTE_ICONS` (e.g. `FileText`, `Plane`), or a single emoji, at most 64 characters. Notes created without one get `📝` from the server; the web client and this one send `FileText`. Unknown names fall back to `FileText`; emoji render as text. |
| `color` | One of `#dc2626`, `#ea580c`, `#d97706`, `#16a34a`, `#0891b2`, `#2563eb`, `#9333ea`, or `null` for the neutral card. The server stores anything else as `null` rather than rejecting it. |
| `sort_order` | Defaults to `9999` when not sent on create, which places the note after everything already on the day. This client never sends it. |

Endpoints, under `/api/trips/:tripId/days/:dayId/notes`:

| Request | Response |
| --- | --- |
| `GET` | `{ notes: [...] }` |
| `POST` `{ text, time?, icon?, color?, sort_order? }` | `201 { note }`. `404 { error: 'Day not found' }`; `400 { error: 'Text required' }` for blank text. |
| `PUT /:id` (any subset of the create fields) | `{ note }`. A missing key keeps the field and an explicit `null` clears `time`/`icon`/`color`. `404 { error: 'Note not found' }`. |
| `DELETE /:id` | `{ success: true }`. `404 { error: 'Note not found' }`. |

Writes need the trip's `day_edit` permission (`403` otherwise). An inaccessible trip is a `404`. Body validation (`400`) runs before both checks.

## Offline-first reads and writes (`DaysRepository`)

Per [offline-first.md](offline-first.md), the Days tab and day screen never call `DaysApi` directly. They go through `DaysRepository`, which treats the local cache as the source of truth for what's shown:

- **`cachedDays(tripId)`** reads the local store only, with no network call. It gives an instant first paint.
- **`refreshDays(tripId)`** first replays queued note writes, then fetches the real day list and re-applies any writes still queued on top of it before caching. A refresh never hides an unsynced change. On `NetworkException` it returns the cache instead of failing. The exception propagates only when the cache is empty, so the caller can show an explicit offline state.
- **`createDayNote`, `updateDayNote`, `deleteDayNote`** change the cached day right away, queue the write in the `DayNoteOutbox`, then try to send everything queued, in order. Each returns the server's copy of the note when the write gets through, or the local copy (`isPending`) when it doesn't.

Every repository operation runs one at a time, so a sync that's already running can't send the same queued write twice.

### The note outbox

`DayNoteOutbox.enqueue` keeps the queue at one op per note:

- An edit to a note whose create is still queued merges into that create. An edit after an edit merges into the earlier edit.
- Deleting a note whose create is still queued drops the create, so the server never hears about the note. A delete after an edit replaces the edit.
- An edit or delete addressed only by a local id, with no queued create to merge into, is dropped. The repository first resolves a caller's copy against the cache, which keeps a synced note's `localId`, so this only happens when the note no longer exists.

As a result, a queued update or delete always addresses a note by server id, and creates never need temporary-id remapping.

### When a write can't be sent

| Outcome | Handling |
| --- | --- |
| Offline (`NetworkException`), any `5xx`, or `401` | The write stays queued, along with every write after it. Sending stops until the next write or refresh. A `401` here usually means the session expired; dropping the user's change would lose data. |
| Delete answered with `404` | Treated as success: the note is already gone. |
| Any other rejection (`400`, `403`, a `404` on create/update) | The write is dropped from the queue. The repository then re-reads the day list from the server (keeping the cache as is if that also fails) so the cache stops showing the rejected change. When the rejected write is the one just requested, the exception is rethrown and `DayDetailScreen` reports it. |

## What's still open

- Day create, reorder, update (`notes`/`title`), and delete (the rest of `DaysApi`/`DaysRepository` for issue #4).
- Place assignments: rendering the actual places assigned to a day, not just a count (depends on [#5](https://github.com/ryanmac8/trek-native-app/issues/5)). Trek interleaves notes and assignments on a day by `sort_order`; this client lists notes on their own.
- Note reordering and moving a note to another day (the web client re-creates the note on the target day).
- Markdown rendering of a note's details.
- Folding the note outbox into the shared outbox/sync engine tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21).
