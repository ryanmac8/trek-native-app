# Weather

The first slice of [issue #16](https://github.com/ryanmac8/trek-native-app/issues/16): current conditions and a multi-day forecast for a location, read offline-first. Weather shown inline on the itinerary day view, and forecasts driven by a trip's real places, are not built yet — they depend on Days ([#4](https://github.com/ryanmac8/trek-native-app/issues/4)) and Places ([#5](https://github.com/ryanmac8/trek-native-app/issues/5)).

## Pieces

| File | Purpose |
| --- | --- |
| [lib/weather/weather_models.dart](../lib/weather/weather_models.dart) | `WeatherReport` (one answer for a coordinate/date, with `conditionBucket`, `isMissing`, `isEstimate`), `HourlyWeather`, the `WeatherKind` / `WeatherCondition` enums, `GeoPoint` (with the 2-dp `cacheKey`), and `TravelDestination`. The wire shape and the local-cache shape are the same JSON, so `fromJson` / `toJson` round-trip through the local store. |
| [lib/weather/weather_api.dart](../lib/weather/weather_api.dart) | `WeatherApi` — wraps `GET /api/weather` and `GET /api/weather/detailed`. A thin transport layer: no caching, no offline handling. Always sends `lang=en`. |
| [lib/weather/weather_local_store.dart](../lib/weather/weather_local_store.dart) | `WeatherLocalStore` / `PreferencesWeatherLocalStore` — a bounded (60-entry, oldest-evicted) `shared_preferences` cache keyed by `lat_lng_date`. `read` returns a `CachedWeather` (the report plus an `isFresh` flag); entries are kept past their TTL for the offline fallback. |
| [lib/weather/weather_repository.dart](../lib/weather/weather_repository.dart) | `WeatherRepository` — the offline-first front door the screen uses instead of `WeatherApi`. See below. |
| [lib/weather/weather_format.dart](../lib/weather/weather_format.dart) | Presentation helpers — `weatherIcon`, `formatTemp`, `formatRange`, `formatForecastDay`, `weatherQualifier`. |
| [lib/weather/weather_destinations.dart](../lib/weather/weather_destinations.dart) | `popularDestinations` — a small bundled list of well-known places (name + country + coordinate). A stand-in coordinate source until geocoding ([#17](https://github.com/ryanmac8/trek-native-app/issues/17)) or a trip's places exist. |
| [lib/features/weather/weather_screen.dart](../lib/features/weather/weather_screen.dart) | `WeatherScreen` — the `/weather` screen, reachable from the trip list's app-bar weather icon. Pick a destination, then see current conditions and a seven-day forecast. |

## API contract

Both endpoints are JWT-guarded (`WeatherController`, `server/src/nest/weather/`), so this uses the authenticated `ApiClient` (`apiClientProvider` in `lib/app/providers.dart`), which attaches `AuthService.currentAccessToken` to every request and clears the local session on a 401.

Trek fetches from [Open-Meteo](https://open-meteo.com) server-side (no API key) and caches per coordinate. Because Trek is self-hosted, weather works as long as the instance can reach Open-Meteo; a `502 { error: 'Open-Meteo API error' }` is the expected "provider unavailable" signal.

- **`GET /api/weather?lat=&lng=&date=&lang=&time=`** → a `WeatherReport`. `lat` / `lng` are required — a missing one is `400 { error: 'Latitude and longitude are required' }`. `date` (`YYYY-MM-DD`) is optional; without it the server returns **current** conditions. `lang` defaults to `de` server-side, so this app always sends `en`. `time` (`HH:MM`) refines a past-date lookup to that hour — unused by this slice.
- **`GET /api/weather/detailed?lat=&lng=&date=&lang=`** → the same shape plus an `hourly` array. `date` is required here — a missing one is `400 { error: 'Latitude, longitude, and date are required' }`. Wired in `WeatherApi.fetchDetailed` but not yet surfaced in the UI (an hourly breakdown belongs with the day view).

`WeatherReport` is one flat object; which fields are populated depends on the request:

| Field | When present |
| --- | --- |
| `temp`, `main`, `description`, `type` | always (`description` is empty for the archive-hourly and climate paths) |
| `temp_max`, `temp_min` | forecast and climate answers, not current conditions |
| `sunrise`, `sunset`, `precipitation_sum`, `precipitation_probability_max`, `wind_max`, `hourly` | the detailed endpoint (and a climate estimate) |
| `error: 'no_forecast'` | the provider had no data for that coordinate/date |

`type` is `current`, `forecast`, or `climate` — `climate` is a historical-average estimate the server falls back to for dates beyond Open-Meteo's ~16-day forecast horizon, surfaced in the UI as "Seasonal average". A `no_forecast` answer arrives with `type: ''`; the model maps both `''` and an `error` to `WeatherReport.isMissing`.

## Offline-first (`WeatherRepository`)

Per [offline-first.md](offline-first.md), the screen never calls `WeatherApi` directly. Weather is an online read — there is no bundled model — but the local cache stays the source of truth for *what is shown*:

- **`cachedReport`** reads the local store only, so a screen can paint the last answer for a coordinate/date instantly.
- **`report`** returns a still-fresh cache entry as-is (no request). Otherwise it fetches, writes the cache, and returns. On a `NetworkException` it falls back to a stale cached entry, flagged `WeatherSnapshot.stale`; only when nothing is cached does the exception propagate, so the screen can show an explicit offline state with a retry. The freshness windows mirror the server's own TTLs — 15 minutes for current conditions, 1 hour for a forecast, 24 hours for a climate estimate.
- **`forecast`** runs `report` over a span of days (clamped to `1..14`) three requests at a time, mirroring the web client's `weatherQueue`. Each day degrades independently: an offline day with a stale cache entry is served from it; an offline day with nothing cached becomes a `null` `ForecastDay.weather` (rendered "Unavailable offline") rather than failing the whole forecast. `TripForecast.isPartial` is true when any day was missing or stale, which drives the screen's offline banner.

There are no local writes — weather is read-only — so this has no outbox. The `shared_preferences` cache here is a minimal, feature-scoped stand-in for the local-persistence mechanism [#21](https://github.com/ryanmac8/trek-native-app/issues/21) will decide on.

## What's still open

- Weather shown inline on the itinerary day view, and forecasts for a trip's real places instead of the bundled `popularDestinations` list — both need Days ([#4](https://github.com/ryanmac8/trek-native-app/issues/4)) and Places ([#5](https://github.com/ryanmac8/trek-native-app/issues/5)).
- The hourly breakdown from `/api/weather/detailed` (the API layer and model already carry it; no UI yet).
- Sunrise / sunset, precipitation, and wind details beyond the temperature summary.
- Fahrenheit — the web client has a per-user temperature-unit setting; this app has no settings surface yet ([#27](https://github.com/ryanmac8/trek-native-app/issues/27)).
- Localised condition text and dates — the app has no locale system yet.
