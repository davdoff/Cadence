# Next Version — Planned Changes

Features to build after the current working version is pushed.

---

NOW:
## 1. WIDGETSSSS:
1. Habit Goal Widgets 

Small Home Screen(square with scrolable habbits if possible) and small sqaure Lock Screen accessory widget containing one chosen habbit
Shows progress ring/bar per habit toward its weekly and daily goal 
Reads from shared AppGroup store — same pattern as existing widgets, just extend the shared data struct with habit summaries
Fully local, no new mechanism needed. If possible it should be able to increment the habbit, discuss with me the posibility of this and how to achieve it


2. Quick-Glance Calendar Widget

Lock Screen rectangular accessory showing next event
Complements the existing Medium "Today's Schedule" Home Screen widget
Same ScheduleWidgetData, just a more compact rendering for lock screen. here telle me if its possible to have a button on the widget like a right arrow to see the event after the next one

3. Two-Stage Event Notifications

Reminder notification X minutes before event start (already planned — defaultReminderMinutes)
Second notification exactly at event start time
No new infra — just an additional scheduled UNNotificationRequest per event

**WidgetKit extension** — create `CadenceWidget` target, AppGroup entitlement, 4 home screen widgets (Next 2 Events small, Today's Schedule medium but talk to me about the medium since it a horizontal block, Daily Progress small, Next Meal small), 2 lock screen widgets (circular + rectangular)

4. Live Activity — Timed Task Countdown with Staged Messages
For focus sessions, reading, meals, or any timed task:

Mechanism: ActivityKit Live Activity, appears on Lock Screen + Dynamic Island — separate from regular widgets
Countdown: native ticking timer via Text(timerInterval:) — updates continuously with zero code from you
Encouragement messages: computed live from elapsed time vs. staged thresholds, not pushed or updated — the view just recalculates which message applies every time it's rendered (unlock, tap, screen wake)
Example (1hr reading session):

0 min → "Time to focus"
20 min → "Not yet — keep focused"
40 min → "You're almost done, no time to waste"

Here i want many messages to randomly be printed, kinda like the way you have words like combobulating for example when you work on a task
The messages should be tailored to the category, if user has a different category use the messages that can be applied in most situations, so basic ones, ill go trough the messages after they are generated


Thresholds can scale proportionally (33%/66% of duration) to work for any session length, not just 1hr
Fully local — no backend, no push tokens, no reliability risk since there's nothing to "fail to sync"
Needs one explicit .end() call when the timer completes (user marks done, or a scheduled local check)
Open question for later: how the activity gets started (auto from a scheduled Event, or a manual "start focus session" button) and how it ties back into marking the Event completed/missed
A: for my case i think i would like the Live activity first to appear with the title and 2 buttons, start or skip we need to discuss the posibility of this and also implement the way to start the live activity form the today view by pressing an event

Scope note: items 1–3 fit cleanly into your existing v1 plan. Item 4 (Live Activities) is a distinct framework from WidgetKit and probably deserves its own README section rather than being folded into the existing Widget Integration section — worth drafting separately when you're ready to spec it out for Claude Code.

## 2. Day Browser Tab

A dedicated tab (or promoted section) to scroll/swipe through any day and see all its events — beyond the current 7-day pill picker in ScheduleView.

**Target files:**
- `Cadence/Views/ScheduleView.swift` — currently has a horizontal 7-day pill picker (`weekDates`, `dayPill`) centered on today; extend to support arbitrary date navigation (month picker, swipe-to-next-day, or a full calendar grid)
- `Cadence/ContentView.swift` — may need to adjust tab structure if this becomes its own tab vs. enhancement of the Schedule tab

---

## 3. Settings Tab

The Settings tab exists (`SettingsView.swift`) but likely needs more options as features grow.

**Target files:**
- `Cadence/Views/SettingsView.swift` — main settings screen; already has theme, notification, and category sections
- `Cadence/Views/CategorySettingsView.swift` — per-category notification settings
- `Cadence/Models/UserPreferences.swift` — add new preference keys as needed
- `Cadence/ContentView.swift` — tab already wired (`Label("Settings", systemImage: "slider.horizontal.3")`)

---

## After These Four Items

Once the above is done, the remaining work is:

1. **Deep Project Planner** — `ProjectPlan` + `ProjectPhase` SwiftData models, `ProjectPlannerView` intake form, `ProjectPlanDetailView`, wire to `AIService.deepProjectPlan`
2. 

Full specs for both are in `CADENCE_README.md` sections 9 and 11.

---

## File Map (quick reference)

| Area | Key files |
|---|---|
| Tab structure | `ContentView.swift` |
| Events | `Models/Event.swift`, `Views/EventDetailView.swift`, `Views/AddEventView.swift`, `Views/TodayView.swift`, `Views/ScheduleView.swift` |
| Meals | `Models/Meal.swift`, `Views/WeeklyMealsView.swift`, `Views/AddMealView.swift`, `Views/FoodPreferencesView.swift`, `Services/MealSchedulerService.swift`, `Services/MealPlanningCoordinator.swift` |
| Habits | `Models/Habit.swift`, `Views/HabitsView.swift`, `Views/HabitDetailView.swift`, `Views/AddHabitView.swift` |
| AI layer | `Services/AIService.swift`, `Services/AIService+SystemPrompt.swift`, `Services/SchedulingContextBuilder.swift` |
| Scheduling | `Services/SchedulerService.swift` |
| Notifications | `Services/NotificationService.swift` |
| Settings | `Views/SettingsView.swift`, `Views/CategorySettingsView.swift`, `Models/UserPreferences.swift` |
| Tests | `CadenceTests/` |
