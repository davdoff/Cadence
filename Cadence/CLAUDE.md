# CLAUDE.md — Meal Planning UI

## Context
The meal planning logic layer is fully implemented. This session is UI only.
Do not modify any of the files listed under "Do not touch" below.

---

## What Already Exists (do not reimplement)

### Models — read-only references for binding
```swift
Meal
- id: UUID
- name: String
- prepTimeMinutes: Int
- isUserDefined: Bool      // false = AI-suggested
- tags: [String]           // populated for AI-suggested meals only

UserPreferences (meal-relevant fields)
- breakfastEnabled: Bool
- breakfastTime: (hour: Int, minute: Int)
- breakfastDuration: Int          // max 30
- dinnerWindowStart: DateComponents
- dinnerWindowEnd: DateComponents
- knownMealIDs: [UUID]
- newMealSuggestionEnabled: Bool
- lastNewMealSuggestedDate: Date?
```

### Services — call these, do not rewrite them
```swift
MealSchedulerService
- scheduleBreakfastIfNeeded(existingEvents:preferences:targetDates:) -> [Event]
- scheduleDinnerSlots(existingEvents:meals:preferences:targetDates:) -> [Event]
- nearestUpcomingMeal(from events: [Event]) -> Event?

MealPlanningCoordinator          // @MainActor
- runWeeklyPass()                // call this after any preference change
```

---

## Screens to Build

### Screen 1 — Food Preferences (settings screen)

Entry point: existing Preferences flow, new "Food" section.

**Breakfast section**
- Toggle: "Schedule breakfast" → `breakfastEnabled`
- Time picker (hour/minute wheels or inline DatePicker, .hourAndMinute): `breakfastTime`
- Show a short explainer below the toggle when enabled:
  *"A 30-min breakfast block will be added to your schedule each morning. Days with a conflict nearby are skipped automatically."*
- Hide time picker when toggle is off

**Dinner section**
- Header: "Dinner window"
- Two time pickers side by side: Start (`dinnerWindowStart`) and End (`dinnerWindowEnd`)
- Inline constraint: end must be after start — show a validation message if not

**My Meals list**
- List of `Meal` objects from `knownMealIDs`, showing `name` and `prepTimeMinutes`
- Each row: meal name left, "X min" right, swipe-to-delete
- "Add meal" button → sheet with two fields: Name (text), Prep time (stepper or number field, minutes)
- New meals are always `isUserDefined = true`
- AI-suggested meals (`isUserDefined == false`) show a small "✦ AI pick" badge — they appear in the list once the user has cooked them (event marked `.completed`)

**New meal discovery**
- Toggle: "Suggest a new meal to try each week" → `newMealSuggestionEnabled`
- Below toggle when enabled, show `lastNewMealSuggestedDate` as: "Last suggestion: [relative date]" or "Not suggested yet" if nil

**Save / apply**
- On any change, call `MealPlanningCoordinator.runWeeklyPass()` after saving preferences
- No separate save button needed if preferences auto-save on change (match existing preferences UX pattern)

---

### Screen 2 — This Week's Meals (read-only overview)

Entry point: a "Meals this week" card or row in the main schedule view, or a tab if the app has one.

**Content**
- 7-row list, one per day (Mon–Sun), each row shows:
  - Day label
  - Breakfast slot time (if scheduled) or "Skipped" in muted text
  - Dinner slot: meal name + time, or "No slot" in muted text
  - AI-suggested meal rows show the "✦ AI pick" badge
- Rows for past days are dimmed
- Tapping a dinner row deep-links to that event in the main schedule (use existing event detail navigation)

**Empty state**
- If no meals are scheduled yet (first launch, preferences not set): show a prompt — "Set up your meal preferences to get started" with a button that navigates to Food Preferences

---

## UI Rules for This Session
- Match the existing app's component style — do not introduce new design patterns
- Use the existing colour/category system for the Meal category colour on event rows
- No loading spinners for local operations — they are instant
- `runWeeklyPass()` may involve an async API call (new meal suggestion) — show a subtle activity indicator only on the "Meals this week" screen while it runs, not in preferences
- Do not add any navigation that bypasses the existing nav stack

## Do Not Touch
- `MealSchedulerService.swift`
- `MealPlanningCoordinator.swift`
- `AIService.swift` and `AIService+SystemPrompt.swift`
- `SchedulingContextBuilder.swift`
- `NotificationService.swift`
- `MealSchedulerServiceTests.swift`
- Any existing event, habit, or preferences UI
