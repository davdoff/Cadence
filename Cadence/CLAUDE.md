# Cadence — Next Steps (Priority Order)

Work from top to bottom. Each item is a discrete, buildable unit.

---

## 1. NotificationService — general event notifications (PARTIAL → DONE)
Add to `NotificationService`:
- `scheduleEventReminder(for event: Event, reminderMinutes: Int) -> String` — fires N min before any event
- `scheduleMissedEventAlert(for event: Event)` — fires when event end time passes with status still `.pending`
- `scheduleReschedulingNudge(for event: Event, after days: Int)` — fires if missed event is older than threshold
Wire these up in the app wherever events are created, edited, or deleted (cancel + reschedule).

## 2. Notification preferences UI
`SettingsView` currently exposes none of the notification fields that already exist on `UserPreferences`:
- `notificationsEnabled` (global toggle)
- `defaultReminderMinutes` (lead time slider, e.g. 0–60 min)
- `perCategoryNotificationsData` (per-category toggles — decode/encode via existing helpers)
Add a "Notifications" section to `SettingsView` exposing all three.

## 3. Habit auto-increment in EventDetailView
`TodayView.mark()` increments correlated habits on `.completed`. The same logic needs to run in `EventDetailView` when the user marks an event complete from the detail screen. Extract the increment logic to a shared function or add it directly to EventDetailView.

## 4. SchedulingContextBuilder — remaining intents
Add cases to the `SchedulingIntent` enum and builder methods for:
- `addToFreeSlot(description: String)` — already called from AIInputView via `AIService.buildUserMessage`, but bypasses the builder; consolidate
- `moveEvent(event: Event, reason: String)`
- `rescheduleMissed(event: Event)`
- `habitWeeklyAnalysis(habits: [HabitWeekSummary])`
- `deepProjectPlan(goal: String, deadline: Date, weeklyHours: Int, constraints: String)`
Match the compact plain-text format shown in the README for each.

## 5. AIService — missing intent paths
Once the builder cases above exist, add API call paths for:
- `moveEvent` — returns `SchedulingDecision`
- `rescheduleMissed` — returns `SchedulingDecision`
- `deepProjectPlan` — returns structured JSON parsed into `[ProjectPhase]`

## 6. ProjectPlan and ProjectPhase models
Create `Models/ProjectPlan.swift`:
```swift
@Model final class ProjectPlan { id, title, deadline, weeklyHoursAvailable, constraints, phases }
@Model final class ProjectPhase { id, title, subtasks: [String], targetDate, linkedEventIDs: [UUID] }
```

## 7. Deep Project Planner UI
New views:
- `ProjectPlannerView` — intake form (goal, deadline, weekly hours, constraints), submit button that calls `AIService.deepProjectPlan`
- `ProjectPlanDetailView` — shows phases + subtasks, "Schedule as Event" button per subtask, "Copy Prompt" button
Wire into the main navigation (add tab or Settings entry).

## 8. AI-assisted reschedule in MissedEventsView
Currently swipe-reschedule just opens `AddEventView` with a pre-filled title. Replace with an AI call using `SchedulingContextBuilder.rescheduleMissed` → show slot suggestions → confirm inserts event and deletes the missed one.

## 9. WidgetKit extension
- Create widget extension target in Xcode (`CadenceWidget`)
- Enable AppGroup entitlement (`group.com.yourname.smartscheduler`) on both targets
- Add `WidgetModels.swift` to both targets (already marked for dual-target in its comment)
- Implement four widget views: Next Event (small), Today's Schedule (medium), Daily Progress (small), Next Meal (small)
- Implement lock screen widgets (circular + rectangular accessory) for next event and daily count
- Use `TimelineProvider` with reload at event start or midnight

## 10. CI/CD
- Create `.github/workflows/ci.yml` — SwiftLint, `xcodebuild test`, `xcodebuild build` for both app and widget targets
- Add SwiftLint config (`.swiftlint.yml`) with sensible rules for this project

## 11. Event import from external links / ICS
- Parse ICS / calendar URL input
- Map to `Event` model
- Show preview before inserting

---

## Reference
- Full spec: `CADENCE_README.md`
- Implementation status: `CADENCE_WORK_LOG.md`
- API key is injected via `Info.plist` key `ANTHROPIC_API_KEY`
- Model: `claude-haiku-4-5-20251001`, max_tokens 200–300 per call
- AppGroup ID placeholder: `group.com.yourname.smartscheduler` (update before TestFlight)
