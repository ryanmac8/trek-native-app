# Vacay

Vacay is Trek's vacation-day planner ([#19](https://github.com/ryanmac8/trek-native-app/issues/19)). It tracks leave per year for one person or for a shared plan, independently of trips. The app currently implements a **read-only plan overview**:

- a switcher over the plan's tracked years
- each member's allowance for the selected year
- the booked days off and company holidays, grouped by month
- the plan's members, pending invites, and settings

These are not built yet: toggling days, adding and removing years, holiday calendars, editing settings and colors, invites, and the calendar grid.

## Pieces

| File | What it is |
| --- | --- |
| [lib/vacay/vacay_models.dart](../lib/vacay/vacay_models.dart) | `VacayPlan` (plan overview: `VacayPlanSettings`, `VacayPlanUser`s, invite counts, tracked years), `VacayYear` (`VacayUserStats`, `VacayEntry`s, `VacayCompanyHoliday`s), `VacayHolidayCalendar`, `VacayEntryKind`, `CachedVacay<T>` (a snapshot plus its `fetchedAt`), and `formatVacayDays`. |
| [lib/vacay/vacay_api.dart](../lib/vacay/vacay_api.dart) | `VacayApi.fetchPlan()` and `fetchYear(year)`. Transport only, no caching. Each call makes two requests in parallel. |
| [lib/vacay/vacay_local_store.dart](../lib/vacay/vacay_local_store.dart) | `VacayLocalStore` interface + `PreferencesVacayLocalStore`. Stores one JSON snapshot for the plan and one per year, per account scope, in `shared_preferences`. |
| [lib/vacay/vacay_repository.dart](../lib/vacay/vacay_repository.dart) | `VacayRepository`, the offline-first front door. `cachedPlan()` and `cachedYear(year)` read only the local cache. `refreshPlan()` and `refreshYear(year)` fetch, write the result to the cache, and return it. |
| [lib/features/vacay/vacay_screen.dart](../lib/features/vacay/vacay_screen.dart) | `VacayScreen` at `/vacay`, opened from the trip list's beach-umbrella action. |

The providers are `vacayApiProvider`, `vacayLocalStoreProvider`, `vacayCacheScopeProvider`, and `vacayRepositoryProvider`, all in [lib/app/providers.dart](../lib/app/providers.dart). `VacayApi` uses the authenticated `apiClientProvider`.

## API contract

These endpoints live in `VacayController` in Trek's `server/src/nest/vacay/`, under `/api/addons/vacay`:
- They are JWT-guarded with no addon gate.
- They always act on the caller's **active plan**: the plan they've accepted an invite to, or otherwise their own.
- `GET /plan` creates the caller's own plan on first use. The new plan is seeded with the current leave year, 30 days, and color `#6366f1`.

`GET /plan`:

```jsonc
{
  "plan": {
    "id": 3, "owner_id": 1,
    "block_weekends": true, "weekend_days": "0,6",   // 0 = Sun … 6 = Sat; null → Sat/Sun
    "week_start": 1,
    "holidays_enabled": true, "holidays_region": null,
    "school_holidays_enabled": false, "company_holidays_enabled": true,
    "carry_over_enabled": true,
    "holiday_calendars": [
      { "id": 7, "plan_id": 3, "type": "public_holiday",   // or school_holiday
        "region": "NZ", "label": "NZ Public Holidays", "color": "#fecaca", "sort_order": 0 }
    ]
  },
  "users": [ { "id": 1, "username": "ryan", "email": "…", "color": "#6366f1" } ],
  "pendingInvites":  [ { "id": 9, "user_id": 4, "username": "…", "email": "…", "created_at": "…" } ],
  "incomingInvites": [ { "id": 9, "plan_id": 5, "username": "…", "email": "…", "created_at": "…" } ],
  "isOwner": true,
  "isFused": true        // more than one member
}
```

`GET /years` → `{ "years": [2025, 2026] }`, ascending.

`GET /stats/:year` → `{ "stats": [...] }`, one row per plan member:

```jsonc
{ "user_id": 1, "person_name": "ryan", "person_color": "#6366f1", "year": 2026,
  "vacation_days": 25, "carried_over": 3, "total_available": 28,
  "used": 4.5,          // half days count 0.5; comp days count 0
  "remaining": 23.5,    // negative when overbooked
  "comp_used": 1,
  "window_start": "2026-01-01", "window_end": "2027-01-01" }   // [start, end)
```

`GET /entries/:year` → `{ "entries": [...], "companyHolidays": [...] }`:

```jsonc
// entries
{ "id": 11, "plan_id": 3, "user_id": 1, "date": "2026-03-02", "note": "",
  "fraction": 0.5,      // 1 or 0.5
  "kind": "vacation",   // or "comp"
  "person_name": "ryan", "person_color": "#6366f1" }
// companyHolidays
{ "id": 5, "plan_id": 3, "date": "2026-12-24", "note": "Office closed" }
```

- **Leave years.** A year number names a leave-year *period*. Each user's `/year-settings` picks the type:
  - `calendar` (the default): Jan 1 – Dec 31.
  - `fiscal`: starts on a configured month and day.
  - `anniversary`: starts on the hire date.

  `window_start`/`window_end` in the stats give the period each row covers. `/entries/:year` returns the twelve whole months the caller's period starts in.
- **Carry-over.** When carry-over is off, `carried_over` reads as 0. `GET /stats/:year` also refreshes the next year's carry-over on the server when that year exists.
- **Missing fields.** Entries predating half days or comp days lack `fraction` and `kind`; they read as a full vacation day. Plan flags are serialized as booleans, and the parser also accepts 0/1.
- **Errors.** Failures use the standard `{ error }` envelope.

## Offline behavior

- **Cache first.** `VacayScreen` paints the cached plan, and the cached year it would select, before refreshing either.
  - If a refresh fails and a snapshot exists, the snapshot stays on screen with an "Offline — showing your plan from …" banner and a retry. The banner shows the older of the plan and year fetch times.
  - With no cached plan, a `NetworkException` shows an explicit offline state with a retry for the whole screen. Any other error shows a generic error state.
  - When the plan is cached but the selected year never was, only the year section shows an offline state with its own retry.
- **Year selection.** The default year is the current calendar year if it's tracked. Otherwise it's the latest tracked year before it, and otherwise the earliest tracked year. This keeps the choice independent of the network.
- **Per-account cache.** Snapshots are keyed by account scope: the configured public server URL plus the session's user id (the JWT `id` claim, via `AuthService.currentUserId`). A different account or server on the same device never sees another account's plan.
  - Without a live session the repository neither reads nor writes the cache.
  - A corrupt entry reads as a cache miss.
  - Members' email addresses are dropped before caching.
- **No outbox yet.** This slice is read-only. Toggling days, company holidays, and every other Vacay write are mutations that depend on the write-queue mechanism tracked in [#21](https://github.com/ryanmac8/trek-native-app/issues/21). See [offline-first.md](offline-first.md).
