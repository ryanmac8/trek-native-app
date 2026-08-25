# Sharing

Covers the share-link slice of [issue #14](https://github.com/ryanmac8/trek-native-app/issues/14): letting a trip's owner/editor turn on a public, read-only link and choose which sections a visitor with that link can see. Export (PDF/ICS, etc.) is not built yet.

## Pieces

| File | Purpose |
| --- | --- |
| [lib/share/share_link.dart](../lib/share/share_link.dart) | `ShareLink` — a trip's share-link state: `token`, `createdAt`, and the five `share*` permission flags. Unlike the other trip-scoped models in this app, there's at most one per trip rather than a list. `token` is null exactly when sharing has never been confirmed enabled by the server — either genuinely off, or an enable/update was just requested locally while offline (`needsSync`) with no token assigned yet. `isEnabled` accounts for both cases. `needsSync`/`pendingDelete` track an offline enable/update/disable until it syncs, the same shape as `CollabNote`. `fromJson`/`toCacheJson`/`fromCacheJson` are the API and local-cache (de)serializers. |
| [lib/share/share_api.dart](../lib/share/share_api.dart) | `ShareApi` — thin wrapper around `GET`/`POST`/`DELETE /api/trips/:tripId/share-link`. |
| [lib/share/share_local_store.dart](../lib/share/share_local_store.dart) | `ShareLocalStore`/`PreferencesShareLocalStore` — persists each trip's cached share-link state as JSON in `shared_preferences`, keyed per trip id. Stores a single nullable `ShareLink` rather than a list. |
| [lib/share/share_repository.dart](../lib/share/share_repository.dart) | `ShareRepository` — the offline-first front door the sharing screen uses instead of `ShareApi` directly. See below. |
| [lib/features/trips/share_screen.dart](../lib/features/trips/share_screen.dart) | `ShareScreen` — reached via a share icon in the trip dashboard's app bar (not a bottom-nav tab, since sharing is a trip-level setting rather than day-to-day trip content). Reads from the cache first, then refreshes from the network in the background. Shows the sharing status, a copyable link once enabled, toggle switches for which sections are included, and enable/save/stop-sharing actions. |

## API contract

`GET /api/trips/:tripId/share-link` returns `{ token, created_at, share_map, share_bookings, share_packing, share_budget, share_collab }` when a share link exists, or `{ token: null }` when it doesn't — "not shared" is a normal state, not a 404. Confirmed against Trek's actual `TripShareController`/`shareService.ts` (`server/src/nest/share/`, `server/src/services/shareService.ts`).

`POST /api/trips/:tripId/share-link` creates the link if none exists yet, or updates its permissions if one already does — 201 on first creation, 200 on a later update, both handled the same way client-side. Unlike the `GET` response, it only returns `{ token }`; the client builds the rest of the `ShareLink` from what it just sent rather than parsing it back out. Server-side defaults when a flag is omitted are `share_map`/`share_bookings: true`, `share_packing`/`share_budget`/`share_collab: false` — `ShareApi.createOrUpdateShareLink` always sends all five explicitly, so these defaults never actually apply.

`DELETE /api/trips/:tripId/share-link` returns `{ success: true }`; not id-scoped, since a trip has at most one share link. Both mutating endpoints require the `share_manage` permission (403 `{ error: 'No permission' }` otherwise); a trip the caller can't access at all is a 404 `{ error: 'Trip not found' }`.

The public `GET /api/shared/:token` endpoint (an unauthenticated snapshot of the trip, filtered by the link's permission flags) and its `/shared/:token` web-client page aren't implemented in this app — they're what the link, once copied, opens in a browser.

## Sections and permissions

Five sections gate what a link visitor sees: map & itinerary (`share_map`), bookings — accommodations and reservations (`share_bookings`), packing list, non-private items only (`share_packing`), budget (`share_budget`), and collab chat (`share_collab`). `ShareScreen` doesn't expose a toggle for `share_map` — it's sent as `true` and displayed as always-included, matching Trek's web client (`TripMembersModal.tsx` marks `share_map`'s permission entry `always: true`).

## Offline-first read/write (`ShareRepository`)

Per [offline-first.md](offline-first.md), `ShareScreen` never talks to `ShareApi` directly — it goes through `ShareRepository`, which keeps the local cache as the source of truth for what's shown. Trip-scoped like `CollabRepository`, but for a single optional resource instead of a list:

- **`cachedShareLink(tripId)`** reads the local store only. `ShareScreen` calls this on load for an instant first paint before the network is involved at all.
- **`refreshShareLink(tripId)`** retries a not-yet-confirmed enable/update (`needsSync`) or disable (`pendingDelete`), then fetches the real state. A write this call just retried into existence (or one still pending, offline) is kept even if the freshly-fetched server state would otherwise overwrite it, since a retry can race the `GET`. On `NetworkException` it falls back to the cache instead of failing, unless nothing has ever been cached, in which case the exception propagates so the caller can show an explicit offline state.
- **`setSharing(tripId, ...)`** enables sharing, or updates its permissions if already enabled — it writes the optimistic state to the cache immediately (`needsSync: true`) and returns it. If the request can't reach the server, the change stays queued in the cache rather than being lost, and the next `refreshShareLink()` call retries it. A genuine rejection (permissions, a 5xx) instead rolls back to the previous cached state and rethrows. An update to an already-enabled link keeps its existing token visible locally while the update syncs.
- **`disableSharing(tripId)`** hides the link (`isEnabled` false) immediately but keeps it in the cache, tombstoned (`pendingDelete`), until the `DELETE` actually confirms — so an offline disable is retried by `refreshShareLink()` instead of forgotten. A no-op if sharing isn't currently enabled.

## What's still open

- Export (PDF/ICS, etc.) — the rest of issue #14.
- A `share_map` toggle from the client (the web client doesn't offer one either — it's structurally always on).
- The public `/shared/:token` viewing experience itself — this app only manages the link, it doesn't render what a recipient sees.
- Regenerating/rotating a token (the current flow only ever has one live token per trip, matching the server's one-row-per-trip `share_tokens` model).
