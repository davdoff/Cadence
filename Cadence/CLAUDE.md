# Cadence — Claude Code Context

## Project
Native iOS scheduling app (Swift / SwiftUI / SwiftData). Solo first release. Uses Claude AI (Haiku) for intelligent event scheduling. Token efficiency is a core design constraint — never send raw data to the API, only structured summaries.

## Developer profile
First-time Xcode user. Paste full error text from Xcode's Issue Navigator (red diamond icon, left panel) when asking for help with build errors.

## What is done (Steps 1–3)

### Data Models — `Cadence/Models/`
All models use SwiftData (`@Model`).

| File | Type | Notes |
|---|---|---|
| `Event.swift` | `@Model` | Has `category` relationship, `status`, `source`, `recurrenceRule`, `notificationIdentifier` |
| `Category.swift` | `@Model` | `deleteRule: .nullify` inverse to Event |
| `Meal.swift` | `@Model` | `name`, `prepTimeMinutes` |
| `UserPreferences.swift` | `@Model` | Single instance; stores working hours, buffer, avoidScheduling blocks, AI aggressiveness, notification prefs, `compactPreferenceString` |
| `SupportingTypes.swift` | Value types | `EventStatus`, `EventSource`, `RecurrenceRule`, `TimeBlock` — all `Codable` |
| `Shared/WidgetModels.swift` | `Codable` structs | `ScheduleWidgetData`, `WidgetEvent` — must be added to widget extension target too |

### Services — `Cadence/Services/`

**`SchedulerService.swift`** — pure local logic, no API calls:
- `conflicts(for:in:bufferMinutes:)` — returns overlapping events, ignores `.missed`
- `freeSlots(duration:in:events:preferences:)` — returns available `DateInterval`s respecting working hours, buffer, and avoid-blocks
- `compactScheduleString(for:in:preferences:)` — token-efficient format sent to Claude (`MON 09:00-10:00[Work] FREE:14:00-18:00`)
- `compactPreferenceString(from:priorityCategories:)` — preference summary string; regenerate only when user saves prefs

**`AIService.swift`** — Claude API wrapper:
- `scheduleEvent(description:events:preferences:categories:)` — builds message, calls API, parses JSON
- Inject `_callAPI: ((String) async throws -> String)?` in tests to avoid real network calls
- Model: `claude-haiku-4-5-20251001`, max 300 tokens
- Returns `SchedulingDecision`: `.add(EventDraft)`, `.conflict(reason:alternatives:)`, `.suggestAlternative([EventDraft])`

**`AIService+SystemPrompt.swift`** — static system prompt. Do not generate dynamically.

### Extensions — `Cadence/Extensions/`
- `Color+Hex.swift` — `Color(hex: "#4A90E2")` init

### App entry point — `Cadence/CadenceApp.swift`
- Seeds 5 default categories + `UserPreferences` on first launch
- `ModelContainer` includes: `Event`, `Category`, `Meal`, `UserPreferences`

### Tests — `CadenceTests/`
- `SchedulerServiceTests.swift` — covers conflict detection, free slot finder, compact string, preference string
- `AIServiceTests.swift` — covers message building, all three decision types, error cases, ISO8601 parsing
- Both use `@testable import Cadence` and in-memory `ModelContainer`

---

## Architecture rules (follow these every session)

1. **Local first.** Conflict detection, free slots, stats, notifications, widget data — all local. Only call Claude API for language/preference reasoning.
2. **Never send raw events to Claude.** Use `compactScheduleString` (next 72h window for add-to-slot intent).
3. **One `UserPreferences` instance.** Fetch with `FetchDescriptor` limited to 1.
4. **`compactPreferenceString` is pre-computed.** Regenerate it in the preferences save path only.
5. **Widget data written via `ScheduleWidgetData.save()`** whenever the schedule changes. Never call the API from a widget.
6. **System prompt is static.** Defined in `AIService+SystemPrompt.swift`. Don't regenerate per-request.

---

## Next step — Step 4: Core UI

Build the main SwiftUI views. No new services or models needed — wire up existing layers.

### Views to build

**`EventListView`** — root screen
- List of today's events sorted by `startTime`
- Swipe to mark complete / missed
- Toolbar: add button (manual), AI input button
- Tab bar or navigation to: Schedule, Missed, Reports, Preferences

**`AddEventView`** — manual entry sheet
- Fields: title, date, start time, end time, category picker
- On save: check `SchedulerService.conflicts(...)`, insert into context

**`AIInputView`** — natural language entry sheet
- Text field for description
- On submit: call `AIService.scheduleEvent(...)`, show result
- If `.add` → confirm and insert `Event` from `EventDraft`
- If `.conflict` → show reason + alternative slots
- If `.suggestAlternative` → show slot options to pick from

**`MissedEventsView`** — list of events where `status == .missed`
- Option to reschedule (manual for now)

**`PreferencesView`**
- Working hours picker (start/end hour)
- Buffer minutes stepper
- Meals per day stepper
- AI aggressiveness slider (1–5)
- On save: call `SchedulerService.compactPreferenceString(from:priorityCategories:)` and store result on `UserPreferences`

### Patterns to use
- `@Query` to fetch from SwiftData
- `@Environment(\.modelContext)` to insert/delete
- Pass `APIService` as a value type (it's a `struct`) — no `@StateObject` needed
- Retrieve API key from `Bundle` info plist or environment (never hardcode)
- `Color(hex: category.colorHex)` from the existing extension for category colours

---

## File structure

```
Cadence/
  CadenceApp.swift
  ContentView.swift          ← placeholder, replace with real root view
  Models/
    Event.swift
    Category.swift
    Meal.swift
    UserPreferences.swift
    SupportingTypes.swift
    Shared/
      WidgetModels.swift
  Services/
    SchedulerService.swift
    AIService.swift
    AIService+SystemPrompt.swift
  Extensions/
    Color+Hex.swift
  Views/                     ← create this folder in Step 4
CadenceTests/
  SchedulerServiceTests.swift
  AIServiceTests.swift
  CadenceTests.swift
CadenceUITests/
  CadenceUITests.swift
  CadenceUITestsLaunchTests.swift
```

---

## Known future work (not in scope until post-v1)
- `SchedulingContextBuilder` — intent-based context shaping for move/reschedule/habit/project intents (README section: AI Request Architecture)
- WidgetKit extension target (needs AppGroup entitlement: `group.com.yourname.smartscheduler` — update `WidgetModels.swift` constant too)
- Push notifications via `UNUserNotificationCenter`
- Habit tracking models and views
- Deep Project Planner
- Conversational intake (multi-turn Claude flow)
