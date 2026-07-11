# iOS Smart Scheduler App — Project README

## Project Overview

A native iOS scheduling and productivity app for a first-time solo release. The app allows users to manage events intelligently using Claude AI, track performance over time, and plan meals — all while keeping API usage lean and efficient.

---

## Developer Context

- First app release (solo developer)
- Native iOS (Swift / SwiftUI)
- Working with Claude Code in a CI/CD environment
- Needs guidance on: app release flow, prompt engineering, data architecture, and CI/CD practices
- Claude API is used for intelligent event analysis and scheduling

---

## Core Features

### 1. Event Input Methods
- **Import from external links** (e.g., calendar links, ICS files, URLs with event data)
- **AI-assisted input** — user describes an event in natural language; Claude analyses it against current schedule and user preferences before adding
- **Manual input** — title, date, time, duration, category

#### 1.1 Device-calendar import (implemented — calendar-import.md §1–§3)

Settings → Calendars → **Import calendars** connects the user's device
calendars (Google, Outlook, iCloud, Exchange — everything iOS surfaces via
EventKit) and imports their events into Cadence's own store, where the
scheduler, conflict detection, reports, and widgets treat them like any other
event. No AI involved anywhere in the import.

- **Permission**: iOS 17+ full-access flow (`requestFullAccessToEvents`);
  `NSCalendarsFullAccessUsageDescription` is in `Cadence/Info.plist`. The OS
  grant is all-or-nothing, so the screen has its own per-calendar picker;
  denied/write-only states deep-link to Settings.
- **Pieces**: `EventKitReader` (pure EventKit → `DeviceEventInstance` value
  structs, one shared `EKEventStore`) → `CalendarImportService` (@MainActor
  sync orchestration, SwiftData writes) → `CalendarImportView` (picker +
  source management UI). New model `CalendarImportSource` (member of the
  shared schema — app **and** widget targets) records each connected
  calendar plus its tombstones.
- **Event model additions**: `externalIdentifier` (stable per occurrence —
  EventKit's `calendarItemExternalIdentifier`, suffixed with the occurrence
  date for recurring events) and `importSourceID` (which calendar/feed);
  both nil for manual/AI events. `source = .imported`.
- **Sync lifecycle** (90-day window): on launch, on `.EKEventStoreChanged`
  (debounced), on manual "Sync now", and when connecting a calendar. Re-sync
  updates title/times in place by `externalIdentifier`, preserves
  `.completed`/`.missed` status, deletes local copies of events removed at
  the source (pending only), rebuilds notifications for changed events, and
  refreshes widgets once per pass. All-day events are skipped (they'd block
  free slots). Locally deleted imports are **tombstoned** on their source so
  a re-sync never resurrects them (delete hooks live in `ScheduleView` and
  `MissedEventsView`).
- **Category mapping**: calendar title → existing category (case-insensitive)
  else a shared `"Imported"` category, created on first use. Local only,
  never Claude.
- **ICS subscription feeds** (same screen, "Calendar links" section): the
  user pastes a `webcal://`/`https://…ics` URL; the thin `ICSImporter`
  client POSTs it to `POST /v1/calendar/ics` (the server fetches and expands
  the feed — see the routes table) and decodes plain event DTOs. Both
  EventKit and ICS produce the shared `ImportedEventInstance` value struct,
  so feeds run through the **same dedupe/tombstone pass** as device
  calendars, with `importSourceID` = the feed URL and category hint = the
  feed's `X-WR-CALNAME`. Feeds re-sync at launch and on "Sync now" (needs
  the server reachable; a failed fetch skips the source, deleting nothing).
  Events stay entirely inside Cadence — nothing is added to Apple Calendar,
  so Cadence is the single source of truth for reminders (no `VALARM`
  double-notification trap).

### 2. Event Management
Each event supports:
- Delete single occurrence
- Delete all occurrences (recurring events)
- Edit title, date, time, duration, and category from the event detail view (implemented — reuses the Add Event form in edit mode; `id`/`source`/`status` are never changed, and time changes cancel and reschedule the notification)
- Mark as **Completed** or **Missed**
- Assign to a **Category**
- **Tap-through**: event rows on Today and Schedule open `EventDetailView`
  (via `navigationDestination(item:)`); the detail view has an edit (pencil)
  toolbar button that opens the same edit sheet
- **Add from Schedule**: the Schedule tab has a toolbar `+` that opens
  Add Event pre-set to the selected day (`AddEventView(initialDate:)`);
  the "Today" toolbar button hides when today is already selected
- **Week / Month modes**: a segmented toggle pinned under the title switches
  the Schedule tab between two browsing styles (`ScheduleMode` enum in
  `ScheduleView`). **Week** shows a paged, one-week-at-a-time day strip (swipe
  to change weeks) with full event cards. **Month** shows a calendar grid with
  per-day event dots (`monthDayCell`, up to 3) and prev/next month navigation,
  and switches the day list to a dense single-line layout
  (`EventRowView(compact:)`) so more events fit at once. Both modes share the
  same selected day, day-stats bar, and category filter; `visibleWeekStart` /
  `visibleMonth` stay in sync with the selected day (and the "Today" button)
- Add Event validates the time range: Save is disabled and an inline
  warning shows while end ≤ start (`DateInterval` would trap otherwise)

### 3. Categories
- User-defined categories applied to all events
- Used for performance tracking and filtering

### 4. Performance Reports
- **Weekly** and **Monthly** views
- Tracks: completed vs missed events, time spent per category, trends over time
- Generated locally (no API call needed for basic stats)

### 5. Missed Events
- Dedicated view listing all missed events
- Option to **reschedule** missed events (AI-assisted or manual)
- Reschedule opens Add Event prefilled from the original
  (`AddEventView(reschedulingSource:)`) — the original event (title, category,
  times) is deleted **only when the replacement is saved**; cancelling the
  sheet keeps it. Imported events are tombstoned at that same save point so
  calendar sync doesn't re-insert them.

### 5b. UI theme layer (`Extensions/Theme.swift`)
- `Theme` has **two independent axes** (see `CADENCE_DESIGN_SYSTEM.md`):
  the **accent** (`accentHex`, from the Settings color picker) drives accent
  gradients; the **surface** (`Surface.light` / `Surface.dark`) drives all
  mode-dependent chrome (text, cards, chips, tab bar, dividers, tracks).
  Injected once from `ContentView` via `.environment(\.theme, …)`; every view
  reads `@Environment(\.theme)`.
- **Light/dark mode:** `@AppStorage("themeMode")` (`ThemeMode` = `.system` /
  `.light` / `.dark`) is the live driver, mirrored into `UserPreferences.themeModeRaw`
  for durability. `ContentView` resolves it against `@Environment(\.colorScheme)`
  (`.system` follows the device) to pick `Surface.dark` vs `.light`, and sets
  `.preferredColorScheme` (nil for `.system`). Chosen in Settings →
  Personalisation → Appearance, beneath the accent swatches.
- Accent palette: `theme.accent / deep / light / dark`. Surface palette:
  `text / text2 / background / cardSurface / cardRing / cardShadow / chipBg /
  chipText / divider / track`. Gradients: `pillGradient` + `pillGlow` (filled
  controls), `accentGradient` (legacy filled), `backgroundGradient` (page wash),
  `barGradient` (progress bars), `cardGradient` (card wash), `ringGradient`
  (conic habits ring), `emptyOrb` (radial empty-state), `tabbarGradient`,
  and `categoryGradient(hex:)` (180° bar/dot from any category/habit hex).
- `.cardStyle(prominent:)` is the shared card chrome (gradient surface + corner
  radius + soft colored shadow + 1px translucent ring) used by all cards; hero
  cards (Overview ring, Habits summary) pass `prominent: true`.
- **Typography (`Extensions/Font+Cadence.swift`):** two bundled families —
  **Bricolage Grotesque ExtraBold** (big headlines/numbers only) and **Manrope
  500–800** (all other UI text). Call sites use semantic `Font` roles, never raw
  sizes: `.cadHero / .cadHeadline / .cadNumber(_:)` (Bricolage) and
  `.cadBody / .cadBodyStrong / .cadSubheadline / .cadFootnote / .cadCaption /
  .cadUI(_:weight:relativeTo:)` (Manrope). `CadenceType.bundled` checks at
  runtime whether the faces are registered; if not, every role falls back to the
  **rounded** system design at a heavy weight — an explicit placeholder, never a
  silent San-Francisco swap. Fonts are added to the app target + `UIAppFonts` by
  David; PostScript names live in `CadenceType` and must match Font Book.
- **Per-habit tile colors (`Extensions/HabitTileColor.swift`):** an extensible
  catalog of color identities (starter set orange/pink/slate), each with a light
  and dark `Tokens` set — `tileGradient` (icon tile), `icon` tint,
  `buttonGradient` (+/− and progress fills), and `solid`/`solidHex`. `Habit`
  stores a `tileColorID` (plain String, so the widget-shared model stays
  Foundation-only; declaration default `"orange"` migrates existing habits) and
  keeps `colorHex` mirrored to the tile's `solidHex` for the widget. AddHabit's
  color picker is driven by `HabitTileColor.all`, so new tiles appear
  automatically. Resolve with `HabitTileColor.by(id:).tokens(dark: theme.isDark)`.
- **Tab bar (`Theme.configureTabBarAppearance()`):** sets the global `UITabBar`
  appearance to the `tabbar-bg` wash over the system blur, a 1px top divider, and
  accent-tinted selection; `ContentView` re-applies it on appear and whenever the
  accent or surface changes. (The active-tab "pill chip" is intentionally not
  done — stock `TabView` has no per-item background.)
- **Widget light/dark (`WidgetTheme.background(accentHex:dark:)`):** widgets pick
  their container background from their **own** `@Environment(\.colorScheme)` — a
  dark surface in dark mode, the accent wash in light — so background and text
  stay consistent. (Widgets follow the system scheme, not the app's manual
  override, since home-screen widgets can't force a scheme.)
- **Status:** the gradient-refresh reskin (Phases 1–6) is complete — theming
  core, typography, Today/Schedule/Habits tabs, per-habit tile colors, tab-bar
  chrome, and widget light/dark parity. Accent is still mirrored to widgets via
  `WidgetSync.mirrorAccent`.

## 6. Meal Planning (Detailed)

The meal planning system has two distinct scheduling tracks — breakfast and dinner — with different logic, different automation levels, and one targeted API call for new meal discovery. The goal is a system that runs itself week to week with minimal user input after initial setup.

---

### 6.1 Breakfast — Recurring Local Event

Breakfast is a daily recurring event created automatically at a user-defined time. It requires no API call and no interaction once configured.

**Behaviour:**
- Created day-by-day during the daily meal pass (`source: .ai`, category = Meal) — each day gets its own event, no recurrence rule
- Default time: configurable by user (e.g. 08:00), duration capped at 30 minutes
- Breakfast times already in the past are skipped (day-start planning)
- If a conflicting event already starts within 30 minutes of the breakfast slot on a given day, that day is silently skipped — no conflict is created
- The user marks each instance `.completed` or `.missed` like any other event
- If breakfast is missed 3 days in a row, a local notification fires at breakfast time on day 4: *"You've missed breakfast 3 days in a row. Want to adjust the time?"* — no API call, purely threshold-triggered

**User setup (one-time):**
- Set breakfast time in Food Preferences
- Toggle breakfast reminders on/off per the existing per-category notification preference

---

### 6.2 Dinner — Slot-First, Fit-Aware, Local Logic

Dinner scheduling is fully local. Randomness within the constraints is intentional — variety without manual planning.

**Behaviour:**
- Window: 19:00–22:00 every day, including weekends (configurable: `dinnerWindowStart`, `dinnerWindowEnd`)
- Duration per dinner = meal's `prepTimeMinutes` (default 45 min if unset)
- **Slot-first selection**: `MealSchedulerService` finds the free slots inside the dinner window, picks one at random, then picks a random meal **that fits the slot's length** — busy evenings automatically get quick meals
- **No repeats within 7 days**: meals cooked or scheduled in the previous 7 days are excluded from the pick (falls back to the full list when the catalog is too small to avoid repeats)
- If no free slot exists within the window on a given day, that day is skipped silently — no forced conflict
- **Planned at day start for today only** — the daily pass runs on app launch (once per calendar day), when Food Preferences closes, and when the Meals screen opens; future days are never pre-booked, and leftover pending AI meal events on future days are cleaned up
- **Swap tonight's dinner**: today's pending dinner can be re-rolled from the Meals screen (circular-arrows button). The replacement must fit before the next event (minus buffer) or the window end, applies the same no-repeat filter, and the event's notification is cancelled and rescheduled

**What the user maintains:**
- A list of meals they can cook (`Meal` records with name and prep time)
- This list is managed in Food Preferences; no AI is involved in maintaining it

---

### 6.3 New Meal Suggestions — User-Triggered, Choice-Based

The user asks for new meal ideas from the Meals screen ("✨ Discover a new meal" card). One API call returns **three options**; nothing is scheduled until the user picks one. This is the only AI call in the entire meal planning system — the daily pass never calls the API on its own.

**Trigger conditions:**
- `newMealSuggestionEnabled == true` in preferences (card is hidden otherwise)
- User-initiated tap on the discover card — never automatic
- **Capped at 2 fetches per calendar day** (`mealSuggestionFetchCount` / `mealSuggestionFetchDate`, helpers `canFetchMealSuggestion` / `recordMealSuggestionFetch` on `UserPreferences`); the card shows a disabled state once the cap is hit
- Requires at least one free dinner slot left today (via `remainingDinnerSlots`); otherwise an alert is shown and no call is made
- The card is highlighted with an accent outline when no suggestion has been accepted for 7+ days (`lastNewMealSuggestedDate`) — the weekly-discovery nudge

**What gets sent (token-efficient):**

```
INTENT: new_meal_suggestion
EXISTING_MEALS: Pasta Bolognese(45min), Stir Fry(30min), Omelette(15min)
FREE_DINNER_SLOTS: WED 19:00-20:30, WED 20:45-22:00
PREFS: dinnerWindow=19:00-22:00
GUIDANCE: "vegetarian, more rice dishes"
```

The `GUIDANCE` line comes from the free-text `mealGuidance` preference (Food Preferences → Meal Discovery) and is omitted when empty. Dietary restrictions in it are hard constraints for the AI; ingredient/cuisine hints steer the choice. Nothing else is sent — no full event objects, no habit data, no other schedule context.

**Expected JSON response (strict schema):**

```json
{
  "meals": [
    { "name": "Thai Green Curry", "prepTimeMinutes": 40, "tags": ["spicy", "one-pot"], "scheduledSlot": "WED 20:00" },
    { "name": "Shakshuka", "prepTimeMinutes": 25, "tags": ["vegetarian"], "scheduledSlot": "WED 19:30" },
    { "name": "Beef Tacos", "prepTimeMinutes": 30, "tags": ["quick"], "scheduledSlot": "WED 20:30" }
  ]
}
```

Options with an unparseable `scheduledSlot` are dropped client-side; if none parse, the call fails with an alert.

**When the user accepts an option (tap in the suggestion sheet):**
1. A new `Meal` record is created (`isUserDefined: false`, `tags` populated from response)
2. An `Event` is created for the returned `scheduledSlot` with a meal notification
3. The meal **joins the rotation immediately** (`knownMealIDs`) — explicit acceptance replaces the old cook-it-first rule
4. `lastNewMealSuggestedDate` is updated to today

Dismissing the sheet inserts nothing (the fetch still counts against the daily cap).

---

### 6.4 SchedulingIntent Extension

Add to the existing `SchedulingIntent` enum:

```swift
case mealSuggestion(existingMeals: [Meal], freeDinnerSlots: [TimeSlot])
```

The `SchedulingContextBuilder` produces the compact plain-text payload above for this intent — consistent with all other intents. No JSON sent to the API; JSON only comes back.

---

### 6.5 Data Model Extensions

New fields added to existing models (no existing fields changed):

```swift
// UserPreferences additions
- breakfastEnabled: Bool                        // default true
- breakfastHour / breakfastMinute: Int          // e.g. 08:00
- breakfastDuration: Int                        // minutes, max 30
- dinnerWindowStartHour / StartMinute: Int      // default 19:00
- dinnerWindowEndHour / EndMinute: Int          // default 22:00
- knownMealIDs: [UUID]                          // references into Meal store
- newMealSuggestionEnabled: Bool
- lastNewMealSuggestedDate: Date?
- mealGuidance: String                          // free text sent as the GUIDANCE line
- mealSuggestionFetchCount: Int                 // daily AI fetch cap (max 2/day)
- mealSuggestionFetchDate: Date?                // day the count applies to

// Meal additions
- isUserDefined: Bool    // false = AI-suggested
- tags: [String]         // populated only for AI-suggested meals
```

---

### 6.6 Notifications

All meal notifications are scheduled locally via `UNUserNotificationCenter`, using the existing `NotificationService`. No new notification infrastructure is needed.

| Trigger | Notification copy | Timing |
|---|---|---|
| Breakfast approaching | "Breakfast in [N] min — don't skip it!" | `defaultReminderMinutes` before start |
| Dinner approaching | "Time to cook: [Meal Name]" | `defaultReminderMinutes` before start |
| Breakfast missed 3 days in a row | "You've missed breakfast 3 days. Adjust the time?" | Fires at `breakfastTime` on day 4 |

On event edit or deletion, cancel and reschedule the associated notification — same rule as all other events.

---

### 6.7 Widget Integration

Widgets read the shared App Group SwiftData store directly (see section 9) — there is no snapshot to write. After any save that changes meal events, call `WidgetSync.refresh()` so the **Next Meal** widget's timeline reloads and re-queries the store.

---

### 6.8 MealSchedulerService + MealPlanningCoordinator (Local — No API)

`MealSchedulerService` is a pure struct: it takes existing data in, returns objects to persist, and never touches the SwiftData context or the AI service. Time-dependent methods take `now: Date = Date()` so tests can pin the clock.

```swift
struct MealSchedulerService {

    // Breakfast events for targetDates. Skips days with a conflict within 30 min
    // of breakfast time and times already in the past.
    func scheduleBreakfastIfNeeded(existingEvents:preferences:targetDates:now:) -> [Event]

    // Slot-first dinner scheduling: random free slot, then a random meal that fits it.
    // Excludes meals cooked/scheduled in the previous 7 days (with small-catalog fallback).
    func scheduleDinnerSlots(existingEvents:meals:preferences:targetDates:now:) -> [Event]

    // Unclaimed dinner-window slots — used to gate and place AI suggestions.
    func remainingDinnerSlots(for:existingEvents:scheduledDinnerEvents:preferences:minimumMinutes:now:) -> [TimeSlot]

    // Replacement meal + end time for a dinner event, fitting between the event's
    // start and the next event (minus buffer) or window end. Nil if nothing fits.
    func swapDinner(for:meals:existingEvents:preferences:) -> (meal: Meal, endTime: Date)?

    // Consecutive missed breakfasts (drives the 3-day nudge).
    func breakfastMissedStreakCount(events:) -> Int

    // Nearest upcoming meal event (widget helper).
    func nearestUpcomingMeal(from:) -> Event?
}
```

`MealPlanningCoordinator` (`@MainActor`) orchestrates the daily pass: stale future-meal cleanup → breakfast → dinner → notification wiring. It returns a `DailyPassResult` (`newEvents`, `eventsToDelete`) for the caller to persist (the caller also calls `WidgetSync.refresh()` after saving). AI suggestions are **not** part of the pass — they're user-triggered from the Meals screen. The daily fetch-cap helpers (`canFetchMealSuggestion(now:)` / `recordMealSuggestionFetch(now:)`) live on `UserPreferences`.

---

### 6.9 What Is Not in Scope (v1)

- Lunch scheduling — not planned; `mealsPerDay` field is reserved for future use
- Nutritional tracking or calorie data
- Recipe steps or ingredient lists
- Multi-turn AI conversation for meal planning
- User rating or feedback on meals beyond the completed/missed status of the event

### 7. User Preferences
- Schedule preferences (working hours, buffer time, priority windows)
- Food preferences (list of meals the user can prepare)
- AI behaviour preferences (how aggressive/passive scheduling suggestions are)
- **All prefs screens autosave** on change (`onChange` → save) — the
  Settings tab has no explicit Save button anymore

### 8. Push Notifications
- **Event reminders** — notify the user ahead of upcoming events (configurable lead time, e.g. 10 / 30 / 60 minutes before)
- **Event start alerts** — a second notification exactly at event start ("Starting now"), skipped when the lead time is 0 since the reminder already fires at start (`scheduleEventStartAlert`, identifier `event-start-<id>`)
- **Start-time action buttons** — the start-time notification carries a `UNNotificationCategory` (`EVENT_ACTIONS`) with three actions: **Start** (opens the app and begins the in-app timer), **Postpone 15m** (background — slides the event +15 min and reschedules its reminder/start/missed trio), **Skip** (background — marks the event missed and schedules the reschedule nudge). Registered at launch via `NotificationService.registerCategories()`; the category + `userInfo["eventID"]` are attached to the start alert and to a zero-lead reminder (which fires at start). Taps are handled by **`NotificationDelegate`** (`Services/NotificationDelegate.swift`), the `UNUserNotificationCenterDelegate` set in `CadenceApp.init()`. The delegate owns the shared `ModelContainer`, so actions apply even when the tap cold-launched the app. It also implements `willPresent` so notifications show while the app is foreground (previously there was no delegate, so foreground banners were suppressed).
- **Missed event alerts** — notify when an event's end time passes without being marked complete
- **Start-event timer & auto-complete** — in the Today tab, tapping a pending event springs the card narrower and reveals a **Start** pill (`StartableEventRow` in `TodayView`); tapping the card again collapses it. Today intentionally does *not* open event detail (that lives on the Schedule tab, which opens `EventDetailView` on tap). Tapping Start stamps `Event.startedAt`, swaps the pill for a live `Text(timerInterval:)` countdown (self-updating, no timers), and schedules a "done!" local notification for `startedAt + duration` (`scheduleEventCompletionAlert`, identifier `event-finished-<id>`). When the countdown ends the event is **auto-marked complete** — via the same `mark(.completed)` path (so correlated habits still increment). Completion is triggered live by a per-row `.task` while the app is foreground, and by a scenePhase/`onAppear` reconciliation pass (`completeElapsedRunningEvents`) for events that finished while the app was closed; both are guarded against double-counting. (Foreground/in-app only — no Live Activity or push yet; see `whiteboard.md` for the APNs path that a Lock Screen version would need.)
- **Meal reminders** — prompt the user when a scheduled meal time is approaching
- **Rescheduling nudges** — notify the user if they have unresolved missed events older than a configurable threshold
- Notification preferences stored in `UserPreferences` (per-category toggles + global lead time)
- Use `UserNotifications` framework (UNUserNotificationCenter) — all notifications scheduled locally, no server push required for v1
- Request notification permission at first meaningful moment (e.g. after the user adds their first event), not at app launch
- On event edit or deletion, always cancel and reschedule the associated notification to keep them in sync

### 9. Lock Screen & Home Screen Widgets
- Built with **WidgetKit** in the `CadenceWidget` app extension target
- The SwiftData store lives in the App Group container (`group.com.david.Cadence`, file `Cadence.store` — see `Models/Shared/AppGroup.swift` / `SharedModelContainer.swift`); widget timeline providers query it directly via `CadenceWidget/WidgetDataStore.swift` (value snapshots only, never `@Model` objects in entries). `SharedModelContainer.migrateLegacyStoreIfNeeded()` copies the pre-App-Group store across once, from the app process.
- **Never call the Claude API from a widget** — widgets must be fully local and fast

#### Widget Types (implemented)

| Widget | Kind | Families | Content |
|--------|------|----------|---------|
| Next Events | `NextEvents` | Small + rectangular accessory | Next 2 events (small); next event only (lock screen) |
| Today's Schedule | `TodaySchedule` | Medium | Day name + completed/total ring, next 3 events |
| Daily Progress | `DailyProgress` | Small + circular accessory | Completed vs total events ring |
| Next Meal | `NextMeal` | Small | Upcoming meal name and time |
| Habit Goal | `Habit` | Small + circular accessory | One configurable habit: daily ring, weekly line, interactive + button |
| Habit Grid | `HabitGrid` | Small | Up to 4 configurable habits, mini rings with + buttons |

#### Interactivity & configuration
- Habit widgets are configured via `AppIntentConfiguration` (`SelectHabitIntent` / `SelectHabitsIntent`, backed by `HabitEntity`); only good habits are offered
- `IncrementHabitIntent` runs in the widget process: fetches the habit from the shared store, `increment()`, save, `reloadAllTimelines()`

#### Implementation Notes
- App Group entitlement `group.com.david.Cadence` on both targets
- The app calls `WidgetSync.refresh()` (→ `WidgetCenter.shared.reloadAllTimelines()`) after every save that changes events, habits, meals, or category colours, and `WidgetSync.mirrorAccent(_:)` on launch and theme change (the widget process can't read the app's standard UserDefaults, so the accent hex is mirrored into App Group defaults; widgets theme via `WidgetTheme` + the `Color.app*` helpers)
- Schedule widgets share `ScheduleProvider`: one timeline entry now plus one at each remaining event's start/end (cap 12), reload policy `.after(midnight)`; habit widgets use a single entry and rely on explicit reloads
- Tapping a widget deep-links via `widgetURL` — scheme `cadence://` (`today`, `meals` → Schedule, `habits`), handled in `ContentView.onOpenURL`
- Do not attempt to display live AI-generated content in widgets — show only local data

### 10. Habit Tracking
- User defines habits, each tagged as either a **good habit** (something to do more of) or a **bad habit** (something to reduce)
- Both types are tracked by **count**, not boolean — e.g. "went to gym 4 times", "smoked 3 times"
- A habit can be **correlated to an event category by name** — when a matching event is marked as Completed, the habit count auto-increments; otherwise the user increments manually
- Habits are **created and edited** through `AddHabitView` — a **long-press** on a habit card opens a context menu (View Details / Edit / Delete); Edit reuses the same sheet via `AddHabitView(editingHabit:)` and updates in place
- Each habit shows a **graph of count over time** (daily/weekly view)
- **Weekly habit message** — once a week the user receives a habit analysis:
  - Hardcoded threshold responses trigger automatically (e.g. streak broken, new personal best, bad habit spiking) — no API call, always fires
  - An optional **AI-generated analysis** is available on demand — user taps to generate, app makes a single API call with the week's habit data and returns a tailored insight; prompt details to be refined through experimentation
- Monthly summary also includes habit trends (generated locally)

### 11. Deep Project Planner
- Designed for large, multi-session tasks (e.g. coding projects, assignments, learning goals)
- User fills a **structured intake form** — goal description, deadline, weekly hours available, any known constraints
- App builds a structured prompt from the form and sends it to Claude, which returns a **phased breakdown** with concrete subtasks and time-boxed milestones
- Each subtask can be **scheduled as an event** (manual placement for v1)
- When a planning session is scheduled, the relevant subtask goal is surfaced in the event detail so the user knows exactly what to work on
- App provides a **"copy prompt"** option — power users can take the generated prompt to any external LLM
- Input types supported in v1: **project-based** tasks (deadline + deliverables). Skill/habit-based goals (e.g. "learn Spanish") are a candidate for a future input type but not in scope yet

#### Post-Release: Conversational Intake (Planned)
After v1, add an optional **multi-turn intake flow** where Claude asks the user clarifying questions before generating the plan. This is more flexible for complex or ambiguous goals but requires managing conversation state and multiple API calls — defer to post-release.

---

## AI Request Architecture — /v1 Planning API (Implemented)

The AI "brain" lives entirely **server-side**. The Node/Express backend (the
`server/` directory, run via `server/index.js`) owns the system prompts,
context/prompt building, free-slot computation, Claude calls, and response
parsing (with a **retry-once rule** on unparseable model output). The iOS
client only exchanges **typed JSON DTOs** — it never sees a prompt or raw
model output. Design docs: `BACKEND_PLAN.md` (migration + contract) and
`ai-planner.md` (planner contract, intents, UX rules).

### Backend layout (`server/`)

```
server/
  index.js            # entry point: reads ANTHROPIC_API_KEY, starts the app
  app.js              # Express app factory; callClaude is injectable for tests
  routes/v1.js        # all /v1 endpoints (validate → slots → prompt → parse)
  routes/legacy.js    # old /api/* passthrough for the shipped build (delete later)
  prompts/index.js    # all system prompts (scheduling, interpret, generate, …)
  services/
    scheduler.js      # free-slot finding, dinner slots, compact schedule + id map
    contextBuilder.js # per-intent payload builders (port of the old Swift builder)
    parsers.js        # Claude-response → typed JSON parsers
    expander.js       # shared goals/phases → concrete-events expander
    ics.js            # ICS feed fetch + RFC 5545/RRULE expansion (node-ical + rrule)
  lib/                # claude call + retry-once, DTO validation, errors, time
  test/               # routes / scheduler / parsers / ics tests (fake Claude + fake fetch, no network)
```

The server is **stateless and OS-blind**: every request carries `now` +
`timezone` from the device, all times are ISO8601 with the device UTC offset
(never `Z`), and the device stays the source of truth for data.

### Routes

| Route | Purpose |
|---|---|
| `GET /v1/health` | Health check |
| `POST /v1/schedule/interpret` | **The "Ask AI" secretary box** — classifies free text into an intent and returns a typed decision (see below) |
| `POST /v1/schedule/add` | Add event from natural language → scheduling decision |
| `POST /v1/schedule/move` | Move an existing event → decision + alternatives |
| `POST /v1/schedule/reschedule` | Reschedule a missed event into a free slot |
| `POST /v1/schedule/generate` | Fill a period with events for stated goals (uses the shared expander) |
| `POST /v1/meal/suggestions` | New-meal options fitted to dinner slots (returns `[]` without an AI call when no slots exist) |
| `POST /v1/habits/analysis` | Weekly habit insight (plain text) |
| `POST /v1/project/plan` | Deep project phase breakdown |
| `POST /v1/calendar/ics` | **Deterministic — no Claude call.** Fetches an `.ics` feed URL (`webcal://` normalised) and expands it (RRULE/EXDATE/RDATE/RECURRENCE-ID, UTC/TZID/floating/all-day forms) into concrete event DTOs within a ≤ 90-day window. Stateless: the URL is re-sent on every sync, never stored or logged (secret feed URLs carry auth). Spec: `calendar-import.md` §4 |

The old `/api/*` passthrough routes stay mounted (only when an API key is
present) so the currently shipped iOS build keeps working during migration.
Errors use a uniform `{ error: { code, message } }` envelope, surfaced in
Swift as `AIServiceError.serverError`.

### The AI planner — `/v1/schedule/interpret`

The single endpoint behind the natural-language box (`AIInputView`). One
Claude call both classifies the intent and produces the decision — a
discriminated union on `intent`, always with a human-readable
`interpretation` string that is shown before anything is committed:

| Intent | Meaning | Client applies as |
|---|---|---|
| `add` | New event (incl. conflict / suggest-alternative sub-states) | insert `Event(source: .ai)` |
| `move` | Move an existing event (targeted by stable id) | reschedule that event |
| `reschedule` | Re-slot a missed/displaced event | move it to the returned slot |
| `reorganize` | Multi-event cleanup: `moves` + `displaced` ids | apply moves; mark displaced |
| `generate` | Batch of generated events for a goal | insert the batch |
| `clarify` | Ambiguous request — question + options | show question card; answer feeds back into a new interpret call |

Key rules (from `ai-planner.md`):

- **Server computes free slots** from the event snapshots + prefs; it also
  builds a compact schedule string with a **stable id map** so `move` /
  `reschedule` / `reorganize` can point at specific events.
- **Clarify over guessing** — when the target event or time is ambiguous, the
  prompt is hardened to return `clarify` instead of a wrong mutation.
- **Always-confirm** — every mutating intent renders a preview card in
  `AIInputView` (add/conflict/suggest, move/reschedule, reorganize plan,
  generate list) and nothing is written until the user confirms. The box also
  shows a helper line + tappable example chips to teach its range.
- **`EventStatus.displaced`** — reorganize may set events aside; they get
  status `.displaced`, surface in a **"Needs rescheduling" tray** inside
  `MissedEventsView`, and are **excluded from missed/completion stats**
  (`OverviewView`) — "the planner moved this aside" is not "you failed it".

### Plan a period — direct generate (`/v1/schedule/generate`)

Besides the generate *intent* (reachable through free text in the box, capped
at interpret's 7-day window), there is a structured entry: the **"Plan a
period…" button** in `AIInputView` opens **`GeneratePlanSheet`** — quick-range
chips (Today / This week / Next 7 days / Next week), start/end date pickers,
and a goals field. It calls `AIService.generate(periodStart:periodEnd:goals:…)`
→ `POST /v1/schedule/generate`, and hands the returned drafts to the same
generate confirm card — nothing is inserted without the user's confirm.

Config layering (ai-planner.md §7): standing truths (work hours, buffers,
avoid-blocks, priority categories, AI level) ride along automatically in
`PrefsSnapshotDTO`; the sheet only asks for the momentary intent (period +
goals). There is deliberately **no generation settings screen** — the density
dial is the existing `aiAggressiveness` slider, which the generate prompt
reads as `AILevel` (passive = plan lightly, aggressive = fill the free slots).
The server clips the slot window to `now` so a period starting today never
offers already-past slots (`scheduler.freeSlots` drops anything before its
`windowStart`, same rule as `dinnerSlots`).

### Client side (thin by design)

`AIService` is a plain struct that encodes snapshots (`EventSnapshotDTO`,
`PrefsSnapshotDTO`) and decodes typed decisions (`AssistantDecision`,
`SchedulingDecision`, `EventDraft`, `MealSuggestionResult`,
`ProjectPhaseData`). It never imports SwiftUI, touches SwiftData, schedules
notifications, or calls `WidgetSync` — views apply the returned values. The
old client-side `SchedulingContextBuilder.swift` and
`AIService+SystemPrompt.swift` were **deleted**; their logic now lives in
`server/services/` and `server/prompts/`. A `_callAPI` closure hook lets
tests exercise encode/decode without the network. `AIService.proxyBaseURL`
points at the proxy — during development it's an ngrok URL that must be
updated whenever ngrok restarts.

### Intent Types and Their Context Shape

The per-intent context shapes below are unchanged in spirit, but they are now
**built by the server** (`server/services/contextBuilder.js`) from the
snapshots in the request — the client no longer precomputes slots or formats
any of this.

**Intent: Add to free slot**
The user wants to place something new. Claude only needs to know where gaps are — not what fills them.
```
FREE_SLOTS: MON 13:00-15:30, MON 18:00-20:00, TUE 09:00-11:00
NEW_EVENT: "dentist appointment, about an hour, prefer morning"
PREFS: BufferBetweenEvents=15min, AvoidScheduling=[Tue afternoon]
```
The local scheduler computes gaps first; Claude never sees existing event details.

**Intent: Move an existing event**
Claude needs to understand what's committed and the cost of each candidate slot, including neighbouring events.
```
ANCHOR_EVENT: Work Meeting | MON 14:00-15:00 | category=Work
SURROUNDING_EVENTS: MON 13:00-14:00[Study] MON 15:30-16:30[Gym]
FREE_SLOTS: MON 16:30-18:00, TUE 10:00-12:00, TUE 14:00-16:00
REASON_FOR_MOVE: "conflict with dentist"
PREFS: PriorityCategories=[Work], BufferBetweenEvents=15min
```

**Intent: Reschedule a missed event**
Similar to move, but adds missed count so Claude can weight suggestions realistically.
```
MISSED_EVENT: Gym Session | WAS: MON 07:00-08:00 | missed_count=2
FREE_SLOTS (next 7d): TUE 06:30-08:00, WED 07:00-08:30, SAT 09:00-10:00
PREFS: PreferMornings=true, MissedEventHandling=aggressive
```

**Intent: Habit weekly analysis (optional AI call)**
Only triggered on user request. Sends the week's habit counts and basic trend direction.
```
HABITS_WEEK: Gym=4(↑ from 2), Smoking=3(↓ from 5), Reading=6(→ stable)
PREFS: GoalGym=5/week, GoalSmoking=0
```
Prompt details to be experimented with — start minimal and iterate.

**Intent: Deep project breakdown**
Sends the structured intake form data; expects a phased plan back as JSON.
```
GOAL: "Build SwiftUI habit tracker app"
DEADLINE: 2025-09-01
WEEKLY_HOURS: 10
CONSTRAINTS: "Weekends only, no Swift experience needed for UI layer"
```

### Context builders (server-side)

Each route has a dedicated builder in `server/services/contextBuilder.js`
(add / move / reschedule / interpret / meal suggestion / habits / project
plan) that runs before the Claude call. Claude receives exactly the context
it needs — nothing more. This replaced the old Swift
`SchedulingContextBuilder`.

---

## Data Architecture (Token Efficiency First)

This is the most critical design concern. The goal is to send the minimum necessary context to Claude while maintaining high-quality outputs.

### Principle: Never send raw data to Claude — send summaries and deltas

#### Local Data (never sent to API unless needed)
- Full event history
- Completed/missed status logs
- Raw meal list
- Performance stats
- Habit count history

#### What gets sent to Claude API
Only the **minimum structured context** required for the current task:

| Task | What to send |
|------|-------------|
| Add event from prompt | Free slots only (next 48–72h) + event description + preferences |
| Move existing event | Anchor event + neighbours + free slots + reason |
| Reschedule missed event | Missed event + missed count + free slots (next 7 days) + preferences |
| Meal planning | Meal list + upcoming schedule gaps + meal frequency preference |
| Habit weekly analysis | Week's habit counts + trends + goals (user-triggered only) |
| Deep project breakdown | Structured intake form fields |
| Weekly/Monthly report | Send nothing — generate locally from stored data |

#### Compressed Schedule Format (design this carefully)
Instead of sending full event objects, send a compact time-block string:

```
MON 09:00-10:00[Work] 12:00-13:00[Meal] 14:00-15:30[Study]
TUE 08:00-09:00[Gym] 11:00-12:00[Work] FREE:13:00-17:00
```

This dramatically reduces tokens versus sending JSON event arrays.

#### Preferences Summary Block
Store a short, pre-formatted preferences string that gets prepended to every Claude call:

```
Prefs: WorkHours=9-18, BufferBetweenEvents=15min, PriorityCategories=[Study,Work], MealsPerDay=3, AvoidScheduling=[Sat morning]
```

Regenerate this string only when the user updates preferences — not on every API call.

#### System Prompt Strategy
- All system prompts live **server-side** in `server/prompts/index.js` — the client never holds or builds a prompt
- Each defines Claude's role, output format (always structured JSON, except the plain-text habit insight), and constraints
- Never regenerate them dynamically — they're static until deliberately updated

#### Output Format Contract
Always instruct Claude to return a strict JSON schema. Example for event scheduling:

```json
{
  "action": "add" | "conflict" | "suggest_alternative",
  "event": { "title": "", "start": "", "end": "", "category": "" },
  "conflict_reason": "",
  "alternatives": []
}
```

Parsing a known schema locally is cheaper and more reliable than open-ended responses.

---

## App Architecture (High Level)

```
App Layer (SwiftUI)
    ↓
Local Data Layer (SwiftData or Core Data)
    ↓
Scheduler Service (local logic: conflict detection, free slot finder)
    ↓
AI Service (typed DTO exchange with the /v1 backend — only when needed)
    ↓
Backend server (server/: prompts, context building, Claude calls, parsing)
    ↓
Preferences Store (UserDefaults or local DB)
    ↓
Notification Service (UNUserNotificationCenter — local only for v1)
    ↓
Widget Extension (WidgetKit — reads from shared AppGroup store)
```

### Key Design Rule
**Do local logic first.** Only escalate to Claude API when the task requires language understanding or preference-based reasoning. Free slot detection, basic conflict checking, stats generation, habit threshold responses, notification scheduling, and widget data writing — all local.

---

## CI/CD Environment

### Recommended Flow (First App)

```
Local Dev (Claude Code)
    → Git (feature branches)
    → GitHub Actions (CI)
        → SwiftLint (linting)
        → Unit Tests (XCTest)
        → Build check (xcodebuild) — must build both app and widget targets
    → TestFlight (CD for beta)
    → App Store (manual release gate for v1)
```

### Branching Strategy (keep it simple for solo dev)
- `main` — always shippable, protected
- `dev` — active development
- `feature/xyz` — one branch per feature, merged into dev via PR

### For Claude Code Usage
- Work feature by feature — one clear scope per session
- Always start a Claude Code session by pasting the relevant section of this README as context
- Use Claude Code for: generating boilerplate, SwiftUI views, data model structs, writing tests
- Do not use Claude Code for: architectural decisions (make those yourself first, then implement)

#### Using Claude Code via Claude.ai (Web/App)
Claude Code runs in the terminal or VS Code — it is a separate tool from the Claude.ai chat interface and the two are currently not linked. You cannot connect a Claude.ai chat session or project directly to a Claude Code terminal session; they do not share context automatically.

For this project, the recommended approach is:
- **Use Claude Code in terminal or VS Code** for active coding tasks (it can read your actual files)
- **Use this Claude.ai project** for architecture discussion, README updates, prompt engineering decisions, and planning
- When switching to a Claude Code session, paste the relevant README section as your opening context — the `CLAUDE.md` file in your project root is the right place to store persistent context that Claude Code loads automatically at the start of every session

A GitHub issue exists requesting Claude Code ↔ Claude.ai Projects integration, but it is not currently available.

---

## App Release Flow (First Release Checklist)

### Phase 1 — Development
- [ ] Core data model defined (Event, Category, Preference, Meal, Habit)
- [ ] Local CRUD working for all event types
- [ ] AI Service wrapper built (with token-efficient formatting)
- [ ] SchedulingContextBuilder implemented (intent-based context shaping)
- [ ] Preferences screen complete
- [ ] Performance report screen (local only)
- [ ] Meal planning flow complete
- [ ] Habit tracking screen (count-based, graph view, event correlation)
- [ ] Weekly habit threshold messages (local, hardcoded conditions)
- [ ] Optional AI habit analysis (single API call, user-triggered)
- [ ] Deep project planner (intake form + Claude breakdown + event scheduling)
- [ ] Push notification service built (local scheduling via UNUserNotificationCenter)
- [ ] Notification preferences added to UserPreferences
- [x] AppGroup entitlement configured on app + widget targets (`group.com.david.Cadence`)
- [x] WidgetKit extension created with Small and Medium home screen widgets (6 widgets incl. interactive habit logging)
- [x] Lock screen widgets implemented (circular + rectangular accessories)
- [x] Widget timeline refresh wired to schedule changes (`WidgetSync.refresh()` after every relevant save)

### Phase 2 — Pre-Release
- [ ] Apple Developer account active ($99/year)
- [ ] App icons and launch screen created
- [ ] **Widget preview screenshots** prepared for App Store
- [ ] Privacy Policy written (required by Apple — you use AI and potentially calendar data)
- [ ] App Store screenshots prepared (6.5" and 5.5" iPhone)
- [ ] App description and keywords written — mention widgets and smart notifications
- [ ] TestFlight beta testing (invite yourself + a few testers)
- [ ] All crashes resolved, memory usage checked
- [ ] Notification permission flow tested on a real device (not simulator)

### Phase 3 — Submission
- [ ] Archive build in Xcode → upload to App Store Connect
- [ ] Fill in App Store Connect metadata
- [ ] Submit for Apple Review (typically 1–3 days)
- [ ] Monitor for rejection reasons and resolve

### Phase 4 — Post-Release
- [ ] Monitor crash reports (Xcode Organizer or Sentry)
- [ ] Version bump strategy: MAJOR.MINOR.PATCH
- [ ] Push updates via the same CI/CD pipeline
- [ ] Conversational intake for Deep Project Planner (multi-turn Claude flow)

---


---

## Data Models (Starter Reference)

```swift
Event
- id: UUID
- title: String
- startTime: Date
- endTime: Date
- category: Category
- recurrenceRule: RecurrenceRule?
- status: EventStatus // .pending, .completed, .missed
- source: EventSource // .manual, .ai, .imported
- notificationIdentifier: String? // UUID string used to cancel/reschedule UNNotificationRequest

Category
- id: UUID
- name: String
- colorHex: String

Habit
- id: UUID
- name: String
- type: HabitType // .good, .bad
- correlatedCategoryName: String? // auto-increments when matching event is completed
- countLog: [Date: Int] // date → count for that day

UserPreferences
- workStartHour / workEndHour: Int
- bufferMinutes: Int
- priorityCategoryIDs: [UUID]
- avoidScheduling: [TimeBlock]
- mealsPerDay: Int // reserved for future lunch support
- aiAggressiveness: Int // 1 = passive suggestions, 5 = aggressive scheduling
- compactPreferenceString: String // pre-formatted for API
- notificationsEnabled: Bool
- defaultReminderMinutes: Int // e.g. 15 — lead time before event
- perCategoryNotificationsData: Data // JSON-encoded [UUID: Bool] (SwiftData limitation)
- meal planning fields — see section 6.5 (breakfast/dinner windows, knownMealIDs,
  mealGuidance, newMealSuggestionEnabled, lastNewMealSuggestedDate, suggestion fetch cap)

Meal
- id: UUID
- name: String
- prepTimeMinutes: Int
- isUserDefined: Bool // false = AI-suggested
- tags: [String]

ProjectPlan
- id: UUID
- title: String
- deadline: Date
- weeklyHoursAvailable: Int
- constraints: String
- phases: [ProjectPhase]

ProjectPhase
- id: UUID
- title: String
- subtasks: [String]
- targetDate: Date
- linkedEventIDs: [UUID]

// Widget extension (reads the shared App Group SwiftData store directly;
// value snapshots built per timeline entry in CadenceWidget/WidgetDataStore.swift)
EventSnapshot
- id: UUID
- title: String
- startTime / endTime: Date
- colorHex: String

HabitSnapshot
- id: UUID
- name / symbolName / colorHex: String
- todayCount / dailyGoal / weekCount / weeklyGoal: Int
```

---

