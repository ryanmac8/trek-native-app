# Share-sheet place import

Part of [issue #25](https://github.com/ryanmac8/trek-native-app/issues/25): Trek appears in the Android share sheet, and a Google Maps, Apple Maps, or Amap link shared from another app can be added to a trip's place pool. Offline-first: the trip picker reads a local cache, and an import made offline is queued and sent later.

iOS isn't covered yet. Appearing in the iOS share sheet needs a Share Extension target (plus an App Group to hand the text to the app), and that doesn't exist. On iOS, `MethodChannelShareIntake` sees no channel handler and reports that nothing was shared.

## Pieces

| Piece | File | Role |
| --- | --- | --- |
| Android intent filter | [AndroidManifest.xml](../android/app/src/main/AndroidManifest.xml) | `ACTION_SEND` / `text/plain` on `MainActivity`, so Trek is listed for shared text |
| `MainActivity` | [MainActivity.kt](../android/app/src/main/kotlin/com/trek/trek/MainActivity.kt) | Forwards the shared text over the `trek/share_intake` method channel. It puts `EXTRA_SUBJECT` in front of `EXTRA_TEXT` when the text doesn't already contain it |
| `ShareIntake` | [lib/share_intake/share_intake.dart](../lib/share_intake/share_intake.dart) | Dart side of the channel: `takeInitialShare()` (the text that launched the app, returned once) and `shares` (text shared while it's running) |
| `SharedMapLink` | [lib/share_intake/shared_map_link.dart](../lib/share_intake/shared_map_link.dart) | Finds the first supported map link in shared text. Parses what it can locally: provider, suggested name, coordinates |
| `ShareImportApi` | [lib/features/share_import/share_import_api.dart](../lib/features/share_import/share_import_api.dart) | The three Trek endpoints below |
| `ShareImportStore` | [lib/features/share_import/share_import_store.dart](../lib/features/share_import/share_import_store.dart) | `shared_preferences`: the trip-list cache per server, plus the queue of pending imports |
| `ShareImportRepository` | [lib/features/share_import/share_import_repository.dart](../lib/features/share_import/share_import_repository.dart) | Cached and refreshed trip list, `importLink`, `flushPending` |
| `ShareImportCoordinator` | [lib/features/share_import/share_import_coordinator.dart](../lib/features/share_import/share_import_coordinator.dart) | App-lifetime glue: shared text → `incomingShareProvider`, and the flush triggers |
| `ShareImportScreen` | [lib/features/share_import/share_import_screen.dart](../lib/features/share_import/share_import_screen.dart) | `/share-import`: the shared link, a name field, a trip picker, and **Add to place pool** |

## Flow

1. Another app shares text. On a cold start, `TrekApp` reads it with `takeInitialShare()` after `AuthService.restoreSession()` and before building the router. A share that arrives while the app is running comes through `shares` instead.
2. `ShareImportCoordinator.handleSharedText` parses the text with `SharedMapLink.parse`. If there's no supported link, a snackbar says so. Otherwise the link goes into `incomingShareProvider` (a `ValueNotifier<SharedMapLink?>`).
3. The router includes that notifier in its `refreshListenable`. While it holds a link:
   - a signed-in user is redirected to `/share-import`;
   - a signed-out user goes through `/login` first and lands on `/share-import` afterwards.

   Clearing the notifier (**Cancel**, or an import that finishes) sends the router back to `/trips`. `/share-import` with nothing shared also redirects to `/trips`.
4. The screen pre-fills the name with the link's suggested name, then lists trips. The cached list shows first, and a refresh runs in the background.

## Recognized links

The host rules match Trek's server (`isGoogleMapsHost`, `GOOGLE_SHORT_HOSTS`, and `AMAP_HOSTS` in `server/src/nest/maps/`) and the web client's `isGoogleMapsUrl`:

| Provider | Hosts |
| --- | --- |
| Google | `maps.app.goo.gl`; `maps.google.<tld>`; `goo.gl/maps…`; `google.<tld>/maps…` and `www.google.<tld>/maps…`. `<tld>` is 2–3 letters, optionally followed by a second 2-letter label, so `google.evil.com` is rejected |
| Apple | `maps.apple.com` |
| Amap | `amap.com`, `www.amap.com`, `uri.amap.com`, `wb.amap.com`, `surl.amap.com`, `gaode.com`, `www.gaode.com` |

What gets parsed locally, with no network:

- **Coordinates.** The same three encodings the server's `extractCoords` reads: `/@lat,lng`, `!3dlat!4dlng`, and `?q=lat,lng` / `?ll=lat,lng`. Out-of-range values are ignored. Amap links are never parsed locally, because they use `lng,lat` in GCJ-02 and the server owns that datum conversion. Short links carry no coordinates.
- **Suggested name.** The first non-empty line of text before the link, which is how Google and Apple Maps start their shared text. Failing that, Google's `/place/<name>/` path segment, or Apple's `q=` when it isn't a coordinate.

## Trek API contract

All three endpoints are JWT-guarded and use `apiClientProvider`, the authenticated client.

| Call | Request | Response |
| --- | --- | --- |
| `GET /api/trips` | — | `{trips: [...]}`: the caller's non-archived trips, owned or shared, newest first. The picker reads `id`, `title`, `start_date`, `end_date` |
| `POST /api/maps/resolve-url` | `{url}` | `200 {lat, lng, name, address, google_ftid?}`. Follows Google/Amap short links and reverse geocodes an address. `400 {error: "Could not extract coordinates from URL"}` if there's no coordinate; `403` if the URL is SSRF-blocked |
| `POST /api/trips/:tripId/places` | `{name, lat?, lng?, address?, google_ftid?, notes?}` | `201 {place}`. `404 {error: "Trip not found"}` if the trip doesn't exist or isn't shared with the caller; `403 {error: "No permission"}` without `place_edit` |

## Building the place

`ShareImportRepository` builds one place from each import:

- **Location.** It always tries `resolve-url` first. If that fails with anything other than a network error or a 401, it falls back to the locally parsed coordinates. With no coordinates at all, the place is created without a location, and the link is saved in `notes`.
- **Name.** The first available of: the name the user entered, the resolver's `name`, the link's suggested name, or `Shared place`.
- **Extra fields.** `address` and `google_ftid` come from the resolver when it returns them.

## Offline behavior

- **Trip picker.** `cachedTrips()` reads the list last fetched from the current server, and `refreshTrips()` fetches and replaces it. If the refresh fails with `NetworkException`, the cached list is kept and the screen shows an offline notice. With no cache, it shows an explicit offline state with **Try again**, never a spinner that doesn't end.
- **Writes go local first.** `importLink` appends a `PendingPlaceImport` to the queue *before* sending. It's removed only once the server has created the place or refused it. The outcome is one of:
  - `PlaceAdded`: the place exists.
  - `ImportQueued`: network failure, 401, 429 or 5xx. The entry stays queued, and the screen says the place will be added once the device is back online.
  - `ImportFailed`: 404, 403 or 400 on create. The entry is dropped and the error is shown.
- **Flushing.** `flushPending()` sends the current server's queue in order. It stops at the first network failure, drops entries the server refuses (reported as error snackbars), and keeps entries that hit a transient error. `ShareImportCoordinator` flushes:
  - once at startup, after the router is on screen;
  - whenever the app returns to the foreground;
  - whenever `AuthService.isAuthenticated` turns true.

  It only flushes when signed in.
- **Per-server scoping.** Each queued import records the public server URL it was made against, and a flush only sends the current server's entries. The trip cache is keyed the same way.
- **One lock.** Every read-then-write of the queue (`importLink` and `flushPending`) runs under a single in-process lock, so a background flush and a tap on **Add** can't send the same import twice.
- **Storage failures.** Unreadable stored JSON reads as empty. A failure during a background flush is logged and retried on the next trigger.
