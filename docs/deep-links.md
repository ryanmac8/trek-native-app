# Deep Links & Trip Invites

First slice of [issue #25](https://github.com/ryanmac8/trek-native-app/issues/25): links into the app, and joining a trip from a Trek invite link.

## Link formats

[lib/deep_links/deep_link.dart](../lib/deep_links/deep_link.dart)'s `DeepLink.parse(Uri)` turns a URI into one of:

| Link | Matches | In-app location |
| --- | --- | --- |
| `JoinTripLink(token)` | `/join/<token>` | `/join/<token>` → `JoinTripScreen` |
| `OpenTripLink(tripId)` | `/trips/<positive int>` | `/trips/<tripId>` → `TripDashboardScreen` |

These mirror the Trek web client's own routes (`client/src/App.tsx` in the [backend repo](https://github.com/liketrek/TREK)), so a link copied from the web app works here unchanged. Each path is accepted in three forms:

- **`trek://` custom scheme** — `trek://join/<token>` (first segment in the URI host) or `trek:///join/<token>`. Registered with the OS: `CFBundleURLTypes` + `FlutterDeepLinkingEnabled` in `ios/Runner/Info.plist`, and a `VIEW`/`BROWSABLE` intent filter + `flutter_deeplinking_enabled` in `android/app/src/main/AndroidManifest.xml`.
- **`http(s)://<host>/…`** — a Trek web URL on any host. `DeepLink.sourceHost` records the host so callers can check it against the configured server.
- **Bare path** — `/join/<token>`.

Anything else (other paths, extra segments, other schemes) parses to `null`.

Because Trek is self-hosted there is no single domain to claim, so the app does not register iOS Universal Links / Android App Links for `https` — that requires an `apple-app-site-association` / `assetlinks.json` file served from each Trek server. Web links reach the app by pasting instead (below).

### Routing

`buildAppRouter` ([lib/app/router.dart](../lib/app/router.dart)):

- A location with a scheme (how the OS delivers a `trek://` link) is redirected to `DeepLink.parse(uri).location`, or `/trips` if it isn't a recognized link.
- A route that doesn't match anything goes to `/trips` (`onException`) instead of an error page.
- The server-setup and login gates apply to deep links like any other location.

### Pasting a link

The trip list's **Open a Trek link** action (`showOpenLinkDialog`, [lib/features/trip_invites/open_link_dialog.dart](../lib/features/trip_invites/open_link_dialog.dart)) accepts any of the forms above. A web link must be on the configured server — its host must match the public or private server URL's host — since invite tokens and trip ids only mean something to the server that issued them.

## Trip invites

Trek trip owners (or members with the `share_manage` permission) can create one rotating invite link per trip; opening it lets any signed-in user with an existing account join the trip as a member.

### API contract

Both endpoints are JWT-guarded and rate-limited per IP (429 `{ "error": "Too many attempts. Please try again later." }`). An unknown, rotated, disabled, or expired token is a 404 `{ "error": "Invalid or expired invite link" }`.

| Endpoint | Response |
| --- | --- |
| `GET /api/trip-invites/:token` | `{ "trip_id": number, "title": string }` |
| `POST /api/trip-invites/:token/accept` | `{ "trip_id": number, "joined": boolean }` — `joined` is `false` when the user already had access (owner or existing member); the join is idempotent |

`TripInviteApi` ([lib/features/trip_invites/trip_invite_api.dart](../lib/features/trip_invites/trip_invite_api.dart)) wraps these using the authenticated `apiClientProvider`. Creating/rotating/disabling a trip's link (`/api/trips/:tripId/invite-link`) is not wrapped.

### Local state

`PendingInviteStore` ([lib/features/trip_invites/pending_invite_store.dart](../lib/features/trip_invites/pending_invite_store.dart)) is a durable list of `PendingInvite`s, stored as one JSON list in `shared_preferences` under `trek.trip_invites.pending`:

| Field | Meaning |
| --- | --- |
| `token` | the invite token |
| `server` | the configured public server URL it was opened against |
| `acceptQueued` | `true` once the user confirmed the join but it hasn't reached the server; `false` for a link opened but not yet confirmed |
| `tripId`, `tripTitle` | the last preview seen, so the invite can be described while offline |

Entries are keyed by (`server`, `token`). `TripInviteRepository` only ever reads and writes entries for the currently configured public server URL, so switching servers never sends one server's token to another.

### TripInviteRepository

[lib/features/trip_invites/trip_invite_repository.dart](../lib/features/trip_invites/trip_invite_repository.dart), exposed as `tripInviteRepositoryProvider` (one app-wide instance). Store read-modify-write cycles and accept calls are serialized through one in-process lock, so a background flush and a user-initiated accept can't both send the same invite.

| Method | Behavior |
| --- | --- |
| `lookup(token)` | `InviteFound(tripId, title)` · `InviteOffline(cached)` on `NetworkException` · `InviteInvalid(message)` on 404 (drops the local entry) · `InviteLookupFailed(message)` on other errors. Refreshes a remembered entry's cached title; doesn't create entries. |
| `accept(token)` | `JoinCompleted(tripId, joined)` (drops the entry) · `JoinQueued` on `NetworkException` (entry saved with `acceptQueued: true`) · `JoinInvalid` on 404 (drops the entry) · `JoinFailed(message)` on other errors (nothing queued). |
| `flushQueued()` | Sends every queued join for the current server, oldest first; stops at the first `NetworkException`. Completed and invalid entries are dropped; `JoinFailed` ones stay queued. |
| `remember(token)` | Saves an unconfirmed entry unless one already exists. |
| `firstUnconfirmed()` / `queued()` | The current server's unconfirmed / queued entries. |
| `discard(token)` | Drops the entry. |

`lookup` and `accept` rethrow `UnauthorizedException` (the session was cleared and the router is heading to login) after remembering the invite.

### Flow

1. **Signed out** — opening `/join/<token>` remembers the token (`remember`) and redirects to login. After login, the redirect sends the user to the first unconfirmed invite (`firstUnconfirmed`) instead of `/trips`. A link opened before any server is configured is not kept, since it can't be tied to a server.
2. **Join screen** (`JoinTripScreen`) — shows the trip title from `lookup` with **Join trip** / **Not now**. Joining navigates to the trip; **Not now** calls `discard`.
3. **Offline** — the screen shows the cached title if one exists and still offers **Join trip**, which queues the join and returns to the trip list, plus **Check again** to retry the lookup.
4. **Queued joins** are sent by `flushQueued` each time `TripListScreen` opens, with a snackbar for each completed or no-longer-valid invite.

Local storage failures in the router's invite lookups and in the trip list's flush are logged and skipped, never blocking navigation.
