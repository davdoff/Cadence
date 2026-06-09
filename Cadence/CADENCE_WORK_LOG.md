# Cadence — Work Log & Implementation Status

*Last updated: 2026-06-08*

---

## What Has Been Built

### Data Layer
All core SwiftData models are fully defined and match the README spec:
- **Event** — id, title, startTime, endTime, status, source, recurrenceRule, notificationIdentifier, category relationship
- **Meal** — id, name, prepTimeMinutes, isUserDefined (false = AI-suggested), tags
- **UserPreferences** — working hours, buffer, AI aggressiveness, breakfast config, dinner window, knownMealIDs, newMealSuggestionEnabled, lastNewMealSuggestedDate, notification fields, compactPreferenceString
- **Habit** — countLog (String:Int keyed by date), correlatedCategoryName, dailyGoal, weeklyGoal, symbolName, colorHex; full helpers: increment/decrement, streak, weekly totals, history array, weekSummary
- **Category** — id, name, colorHex, events inverse relationship
- **SupportingTypes** — EventStatus, HabitType, EventSource, RecurrenceRule, TimeBlock, HabitDayEntry, HabitWeekSummary
- **ScheduleWidgetData / WidgetEvent** — Codable structs, load/save via AppGroup UserDefaults

Missing: `ProjectPlan` and `ProjectPhase` models have no implementation file.

### Services
- **SchedulerService** — conflict detection (buffer-aware), free slot finder (working hours + avoid-blocks + buffer), compact schedule string for API, preference string builder
- **MealSchedulerService** — breakfast scheduling (skip days with conflicts within 30 min), dinner random-slot + random-meal selection, remaining dinner slot calculator, breakfast missed streak counter, nearest upcoming meal helper
- **MealPlanningCoordinator** — full weekly pass orchestrating: breakfast events → dinner events → optional AI new-meal suggestion → notification scheduling → widget data write + WidgetCenter reload
- **AIService** — three API call paths: `scheduleEvent` (add to free slot), `analyzeHabits` (habit weekly analysis), `suggestNewMeal` (meal suggestion); all use claude-haiku-4-5-20251001 with max_tokens 200–300
- **AIService+SystemPrompt** — three static system prompts: scheduling, habit coach, meal suggestion
- **SchedulingContextBuilder** — `mealSuggestion` intent only (compact plain-text payload matching README spec)
- **NotificationService** — meal approaching notification, breakfast missed streak nudge, cancellation helpers

### UI Views
All primary views are implemented and navigable:
- **TodayView** — time-sectioned event list (morning/afternoon/evening), swipe to complete/miss, status filter pills, greeting with name, missed events badge, AI and manual add FABs
- **ScheduleView** — scrollable week strip, per-day event list with category filter, day stats progress bar, meals entry point
- **OverviewView** — animated completion ring, stats chips (completed/missed/upcoming), stacked bar chart (7d/30d), per-category breakdown, habit highlights card
- **HabitsView** — summary card (daily goal ring, good/bad counters), filter all/good/bad, sort by streak/today/A-Z, compact toggle, habit cards with inline +/- controls
- **HabitDetailView** — today counter with daily goal progress, weekly goal card, 7d/30d bar chart (Swift Charts), hardcoded threshold insights, AI analysis card (user-triggered)
- **WeeklyMealsView** — per-day breakfast + dinner slot cards, AI pick badge, triggers weekly pass on appear
- **FoodPreferencesView** — breakfast toggle + time picker, dinner window start/end pickers, meal list with CRUD, AI suggestion toggle with last-suggested date
- **SettingsView** — personalisation (name, theme picker), working hours sliders, buffer slider, AI level slider, food and category entry points
- **AIInputView** — natural-language event input, shows confirm/conflict/suggest_alternative cards, inserts event on confirm
- **MissedEventsView** — list of missed events, swipe to reschedule (opens AddEventView pre-filled), swipe to delete
- **AddEventView, AddHabitView, AddMealView, CategorySettingsView, EventDetailView, EventRowView** — all present

### Meal Planning (detailed)
The README's full meal planning spec (sections 6.1–6.8) is implemented:
- Breakfast: recurring local events, conflict-skip, 30-min cap, missed streak → notification
- Dinner: random window slot + random meal, skip day if no slot, 7-day rolling pass
- AI suggestion: fires once per week when `newMealSuggestionEnabled` and ≥7 days since last; meal joins rotation only on first `.completed`
- Widget: `nextMeal` field written after each pass, `WidgetCenter.shared.reloadAllTimelines()` called

### Habit Tracking
- Count-based logging (increment/decrement), good and bad types
- Correlated to event category — auto-increments when matching event marked `.completed` in TodayView
- 7d/30d bar chart in detail view
- Hardcoded weekly threshold messages (streak broken, new high, bad habit spike, downward trend)
- AI habit analysis — single API call, user-triggered, per-habit from detail view

---

## What Is Partial

| Component | What's missing |
|---|---|
| `NotificationService` | Only meal notifications. General event reminders (N min before any event), missed-event alerts, and rescheduling nudges not implemented. |
| `SchedulingContextBuilder` | Only `mealSuggestion` exists. The other 5 README intents — `addToFreeSlot`, `moveEvent`, `rescheduleMissed`, `habitWeeklyAnalysis`, `deepProjectPlan` — have no builder methods. |
| `AIService` | `moveEvent` and `rescheduleMissed` intents have no API call path; `deepProjectPlan` missing entirely. |
| Missed-event AI reschedule | Opens plain `AddEventView`; no `rescheduleMissed` context builder or API call is invoked. |
| Notification preferences UI | Model fields exist but no UI in SettingsView to configure `notificationsEnabled`, `defaultReminderMinutes`, or per-category toggles. |
| Habit auto-increment | Only fires in `TodayView.mark()`. Marking an event complete via `EventDetailView` does not trigger the habit counter. |

---

## What Is Not Started

| Area | Item |
|---|---|
| Data Models | `ProjectPlan`, `ProjectPhase` — no file |
| Services | `SchedulingContextBuilder` — addToFreeSlot, moveEvent, rescheduleMissed, habitWeeklyAnalysis, deepProjectPlan |
| Services | `AIService` — moveEvent, rescheduleMissed, deepProjectPlan API calls and parsers |
| Services | `NotificationService` — general event reminders, missed-event alerts, rescheduling nudges |
| Views | Deep Project Planner — intake form, phase breakdown, copy-prompt button, event scheduling from subtasks |
| Views | Notification settings — per-category toggles, global lead-time slider |
| Views | Event import from external links / ICS |
| Widgets | WidgetKit extension target — not created |
| Widgets | Widget views: Next Event (small), Today's Schedule (medium), Daily Progress (small), Next Meal (small) |
| Widgets | Lock screen widgets (circular + rectangular accessory, iOS 16+) |
| Widgets | AppGroup entitlement on both targets |
| CI/CD | GitHub Actions workflow file |
| CI/CD | SwiftLint integration |
| CI/CD | TestFlight CD pipeline |
