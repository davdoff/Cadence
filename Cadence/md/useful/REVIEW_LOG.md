# Review log

Running record of what code review has already covered, so later review
sessions don't re-plow the same ground. Newest entry first. (This file is
gitignored like all .md except CADENCE_README.md — local context only.)

## 2026-07-10 — UI pass: all of Cadence/Views/ (+ ContentView, Color+Hex)

**Scope reviewed:** all 18 files in `Cadence/Views/`, `ContentView.swift`,
`Extensions/Color+Hex.swift`. Findings + todo list + gradient migration plan
written to **`UI_REVIEW.md`** (that file is the source of truth for open UI
work; don't re-derive these findings here).

**Headline confirmed bugs:** AddEventView `DateInterval` crash when end <
start; MissedEventsView reschedule deletes the event before the user commits;
meal-suggestion quota burned on failed fetches; AI slot buttons title events
with the raw prompt text; EventDetailView reachable only from the weekly-meals
dinner slot.

**Not reviewed:** `CadenceWidget/` UI, services, server (unchanged from below).

## 2026-07-10 — calendar-import + ICS endpoint (pre-merge, high effort)

**Scope reviewed** (merged to main as 7fd45ae; feature commit 3f8c9d3):
- `server/services/ics.js`, `server/routes/v1.js` (the `/calendar/ics` route),
  `server/app.js` (fetchImpl injection), `server/test/ics.test.js`
- `Cadence/Services/CalendarImportService.swift`, `EventKitReader.swift`,
  `ICSImporter.swift`
- `Cadence/Models/CalendarImportSource.swift`, `Event.swift` (new fields),
  `Models/Shared/SharedModelContainer.swift` (schema addition)
- `Cadence/Views/CalendarImportView.swift`, plus the touched hunks of
  `ScheduleView`, `MissedEventsView`, `SettingsView`, `CadenceApp`
- `Info.plist`, `package.json` / `package-lock.json`

**Method:** 8 finder angles (line-by-line, removed-behavior, cross-file,
reuse, simplification, efficiency, altitude, CLAUDE.md conventions) →
dedupe → per-candidate verification. 48/48 server tests passing.

**Fixed before merge (3 confirmed):**
1. Sync deletion pass deleted `.displaced` imported events → now pending-only.
2. Dense RRULE (FREQ=SECONDLY/MINUTELY) leaked rrule-temporal's 10k-iteration
   Error as HTTP 500 → now a clean 400.
3. Category lookup did a full table fetch per inserted event → one fetch per
   sync pass.

**Known open findings (plausible/minor — a future cleanup pass, not TODOs to
rediscover):**
1. `ics.js` `toZoned(ev.end)`: zoned DTSTART + floating DTEND (spec-violating
   feeds) yields wrong durations.
2. `ics.js` `pushOverride`: overrides skip the `end <= start` normalization the
   master event gets; malformed all-day overrides silently drop.
3. Tombstone-delete ritual (noteLocalDeletion + delete + save + WidgetSync)
   duplicated in 3 view call sites → belongs in one
   `CalendarImportService.delete(_:)` entry point.
4. `ics.js` builds the `{title,start,end,allDay,externalIdentifier}` instance
   DTO in 4 places → extract a helper.
5. `noteLocalDeletion` fetch-all+sort to find one source → targeted #Predicate.

**Explicitly judged fine (don't re-flag):**
- The `> 91` day window check in `routes/v1.js` — deliberate slack for the
  inclusive date-only `windowEnd` (`endOf("day")`); `> 90` would reject the
  iOS client's own 90-day request.
- All-day events skipped on import — documented design (they'd pollute the
  free-slot finder).
- `kindRaw` string storage on `CalendarImportSource` — deliberate
  SwiftData-safe enum pattern.
- Startup `syncAll` in `.task` — async, doesn't block first render.

## Never yet reviewed (candidates for a whole-project pass)

Everything that predates the calendar-import diff, notably: `SchedulerService`,
`MealSchedulerService`, `MealPlanningCoordinator`, `NotificationService`,
`WidgetSync` + the whole `CadenceWidget/` target, `AIService` (+Interpret),
`server/services/scheduler.js`,
`contextBuilder.js`, `parsers.js`, `expander.js`, `prompts/`, and the legacy
`/api` routes (deletion candidate once the new client ships).
