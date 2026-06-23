# Cadence — Next Steps (Priority Order)

Work from top to bottom. Each item is a discrete, buildable unit.

---

## ✅ DONE — Notifications (items 1–3)
- `NotificationService` has all three event notification methods: `scheduleEventReminder`, `scheduleMissedEventAlert`, `scheduleReschedulingNudge`, `cancelEventNotifications`
- `SettingsView` exposes the notifications section: global toggle, reminder-minutes slider, per-category nav link (`CategoryNotificationsView`)
- `TodayView.mark()`, `EventDetailView.mark()`, `AddEventView.forceInsert()`, `AIInputView.insertDraft()` all cancel/schedule notifications correctly
- Habit auto-increment runs in both `TodayView.mark()` and `EventDetailView.mark()`

## ✅ DONE — SchedulingContextBuilder + AIService intent layer (items 4–5)
- `SchedulingIntent` has all 6 cases: `mealSuggestion`, `addToFreeSlot`, `moveEvent`, `rescheduleMissed`, `habitWeeklyAnalysis`, `deepProjectPlan`
- `SchedulingContextBuilder.build(_:preferences:)` produces compact plain-text payloads for every intent
- `AIService.scheduleEvent` now goes through the builder (sends free slots, not full schedule)
- `AIService.moveEvent` and `AIService.rescheduleMissed` added — both return `SchedulingDecision`
- `AIService.deepProjectPlan` added — returns `[ProjectPhaseData]` parsed from structured JSON
- `projectPlanSystemPrompt` added to `AIService+SystemPrompt`
- `ProjectPhaseData` value type defined in `AIService.swift` (temporary — superseded by item 1 below)

---

## 1. ProjectPlan and ProjectPhase models
Create `Models/ProjectPlan.swift` with SwiftData models:
```swift
@Model final class ProjectPlan {
    var id: UUID; var title: String; var deadline: Date
    var weeklyHoursAvailable: Int; var constraints: String
    @Relationship(deleteRule: .cascade) var phases: [ProjectPhase]
}
@Model final class ProjectPhase {
    var id: UUID; var title: String; var subtasks: [String]
    var targetDate: Date?; var linkedEventIDs: [UUID]
}
```
Register both in `CadenceApp` schema. Remove `ProjectPhaseData` from `AIService.swift` and update `deepProjectPlan` to return `[ProjectPhase]`.

## 2. Deep Project Planner UI
New views:
- `ProjectPlannerView` — intake form (goal TextField, deadline DatePicker, weekly hours Stepper, constraints TextField), submit calls `AIService.deepProjectPlan`, shows loading then navigates to detail
- `ProjectPlanDetailView` — lists phases + subtasks; "Schedule as Event" button per subtask opens `AddEventView` pre-filled; "Copy Prompt" button copies the builder output to clipboard
Wire into `ContentView` navigation (Settings entry or dedicated tab).

## 3. AI-assisted reschedule in MissedEventsView
`AIService.rescheduleMissed` now exists. Replace the swipe-reschedule action in `MissedEventsView` (currently opens plain `AddEventView`) with:
1. Call `AIService.rescheduleMissed(event:missedCount:allEvents:preferences:)`
2. Show slot suggestions (same card UI as `AIInputView`)
3. On confirm: insert new event with notifications, delete the missed one

## 4. WidgetKit extension
- Create widget extension target in Xcode (`CadenceWidget`)
- Enable AppGroup entitlement (`group.com.yourname.smartscheduler`) on both targets
- Add `WidgetModels.swift` to both targets (already marked for dual-target in its comment)
- Implement four widget views: Next Event (small), Today's Schedule (medium), Daily Progress (small), Next Meal (small)
- Implement lock screen widgets (circular + rectangular accessory) for next event and daily count
- Use `TimelineProvider` with reload at event start or midnight

## 5. CI/CD
- Create `.github/workflows/ci.yml` — SwiftLint, `xcodebuild test`, `xcodebuild build` for both app and widget targets
- Add SwiftLint config (`.swiftlint.yml`) with sensible rules for this project

## 6. Event import from external links / ICS
- Parse ICS / calendar URL input
- Map to `Event` model
- Show preview before inserting

---

## Reference
- Full spec: `CADENCE_README.md`
- Implementation status: `CADENCE_WORK_LOG.md`
- API key is injected via `Info.plist` key `ANTHROPIC_API_KEY`
- Model: `claude-haiku-4-5-20251001`, max_tokens 200–600 per call (600 for deepProjectPlan)
- AppGroup ID placeholder: `group.com.yourname.smartscheduler` (update before TestFlight)
