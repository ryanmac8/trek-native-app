# Offline-First

This is a cross-cutting design principle, not a Phase 3 feature to bolt on later: **assume the network is unavailable, slow, or flaky at any point, for every feature.** It's the main technical reason this app exists instead of just using Trek's PWA (see [ARCHITECTURE.md](ARCHITECTURE.md)), so it has to shape data-layer decisions from the start, not just the dedicated sync work tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21).

## What this means in practice

- **Local storage is the source of truth for the UI.** Screens read from a local store (database/cache), not directly from `ApiClient`. The network's job is to keep that local store in sync in the background — the UI should never block on a network round-trip just to show data the app has already seen.
- **Every write is local-first.** A user editing a trip, checking off a packing item, or adding a budget item should see it take effect immediately, persisted locally, with the server sync happening (and retrying) independently. Don't design a mutation as "call the API, then update the UI from the response" — design it as "update local state, then sync."
- **Reads must degrade gracefully.** If a screen has no cached data yet and the network is down, show an explicit offline/empty state — never an infinite spinner or an uncaught `NetworkException`.
- **Writes must queue, not fail silently or block.** If a mutation can't reach the server, it should be retried (with backoff) once connectivity returns, not lost. This implies some durable local queue/outbox once real mutations exist — a concrete mechanism is still open, tracked in #21.
- **Auth already follows this.** `AuthService.currentAccessToken` (see [networking-auth.md](networking-auth.md)) never makes a network call — it reads the stored session and decodes the JWT's `exp` claim locally. Whether the user *appears* logged in never depends on connectivity; only actions that need the server (login, logout, MFA verify) do.
- **Conflicts are expected, not exceptional.** Multiple devices/collaborators editing the same trip while offline means the sync layer needs a real conflict strategy (last-write-wins per field, merge, or user-prompted) — to be decided as part of #21, but every mutation's shape should be designed so a future conflict-resolution pass doesn't require re-architecting it (e.g., prefer per-field updates with timestamps over whole-object overwrites where practical).

## What this means for how we build and test

- When implementing any feature that reads/writes trip data, design the local persistence and the sync/network path together — don't build the network call first and bolt on caching later.
- Tests should treat "offline" as a normal case to cover, not an edge case to skip: assert that reads still work from cache and writes still succeed locally when `ApiClient` throws `NetworkException`.
- Before picking the next roadmap item to build, ask whether it can be implemented in a way that works offline from day one, or whether it genuinely depends on #21 (offline-first sync & local cache) landing first — if the latter, that's a signal #21 may need to move up rather than stay a late Phase-3 item.
