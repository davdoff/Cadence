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

### 2. Event Management
Each event supports:
- Delete single occurrence
- Delete all occurrences (recurring events)
- Edit duration, start time, end time (drag gesture or manual input)
- Mark as **Completed** or **Missed**
- Assign to a **Category**

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

### 6. Meal Planning
- User maintains a list of meals they can prepare (stored in Food Preferences)
- App suggests or schedules meals as events to ensure the user remembers to eat
- Meals are treated as a special event category

### 7. User Preferences
- Schedule preferences (working hours, buffer time, priority windows)
- Food preferences (list of meals the user can prepare)
- AI behaviour preferences (how aggressive/passive scheduling suggestions are)

### 8. Push Notifications
- **Event reminders** — notify the user ahead of upcoming events (configurable lead time, e.g. 10 / 30 / 60 minutes before)
- **Missed event alerts** — notify when an event's end time passes without being marked complete
- **Meal reminders** — prompt the user when a scheduled meal time is approaching
- **Rescheduling nudges** — notify the user if they have unresolved missed events older than a configurable threshold
- Notification preferences stored in `UserPreferences` (per-category toggles + global lead time)
- Use `UserNotifications` framework (UNUserNotificationCenter) — all notifications scheduled locally, no server push required for v1
- Request notification permission at first meaningful moment (e.g. after the user adds their first event), not at app launch
- On event edit or deletion, always cancel and reschedule the associated notification to keep them in sync

### 9. Lock Screen & Home Screen Widgets
- Built with **WidgetKit** as a separate app extension target in the same Xcode project
- Widgets read from a shared `AppGroup` container (UserDefaults or SwiftData store shared between app and extension)
- **Never call the Claude API from a widget** — widgets must be fully local and fast

#### Widget Types (planned)

| Widget | Size | Content |
|--------|------|---------|
| Next Event | Small | Title, time, category colour |
| Today's Schedule | Medium | List of remaining events for today |
| Daily Progress | Small | Completed vs total events (ring or bar) |
| Next Meal | Small | Upcoming meal name and time |

#### Lock Screen Widgets (iOS 16+)
- Circular and rectangular accessory sizes
- Show: next event title + time, or daily completion count
- Keep data refresh lightweight — use `TimelineProvider` with sensible reload policy (e.g. reload at the start of each event or at midnight)

#### Home Screen Widgets
- Small, medium, and (optionally) large sizes
- Tapping a widget deep-links into the relevant section of the app using URL schemes or `widgetURL(_:)`

#### Implementation Notes
- Create an `AppGroup` entitlement (`group.com.yourname.smartscheduler`) and enable it on both the main app target and the widget extension target
- Use a shared `ScheduleWidgetData` struct (Codable) written by the main app and read by the widget — keep it minimal (next 3–5 events max)
- Refresh widget timelines from the main app whenever the schedule changes using `WidgetCenter.shared.reloadAllTimelines()`
- Do not attempt to display live AI-generated content in widgets — show only cached, locally stored data

### 10. Habit Tracking
- User defines habits, each tagged as either a **good habit** (something to do more of) or a **bad habit** (something to reduce)
- Both types are tracked by **count**, not boolean — e.g. "went to gym 4 times", "smoked 3 times"
- A habit can be **correlated to an event category by name** — when a matching event is marked as Completed, the habit count auto-increments; otherwise the user increments manually
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

## AI Request Architecture — Scheduling Intent Model

Different scheduling intents require structurally different context sent to Claude. The app uses a `SchedulingContextBuilder` service that selects the right data shape per intent before making any API call.

### Intent Types and Their Context Shape

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

### SchedulingContextBuilder (Swift)

```swift
enum SchedulingIntent {
    case addToFreeSlot(description: String)
    case moveEvent(event: Event, reason: String)
    case rescheduleMissed(event: Event)
    case habitWeeklyAnalysis(habits: [HabitWeekSummary])
    case deepProjectPlan(form: ProjectPlanForm)
}
```

Each case calls a dedicated builder method that runs entirely locally before the API call. Claude receives exactly the context it needs — nothing more.

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
- Keep one well-crafted system prompt stored locally
- It defines Claude's role, output format (always structured JSON), and constraints
- Never regenerate it dynamically — it's static until you deliberately update it

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
SchedulingContextBuilder (intent → structured API payload)
    ↓
AI Service (Claude API calls — only when needed)
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
- [ ] AppGroup entitlement configured on app + widget targets
- [ ] WidgetKit extension created with at least Small and Medium home screen widgets
- [ ] Lock screen widgets implemented (iOS 16+)
- [ ] Widget timeline refresh wired to schedule changes

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
- workingHours: ClosedRange<Date>
- bufferMinutes: Int
- priorityCategories: [Category]
- avoidScheduling: [TimeBlock]
- mealsPerDay: Int
- compactPreferenceString: String // pre-formatted for API
- notificationsEnabled: Bool
- defaultReminderMinutes: Int // e.g. 15 — lead time before event
- perCategoryNotifications: [UUID: Bool] // category id → enabled

Meal
- id: UUID
- name: String
- prepTimeMinutes: Int

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

// Shared with Widget Extension (written to AppGroup UserDefaults)
ScheduleWidgetData (Codable)
- lastUpdated: Date
- upcomingEvents: [WidgetEvent] // max 5, lightweight struct
- todayCompleted: Int
- todayTotal: Int
- nextMeal: WidgetEvent?

WidgetEvent (Codable)
- title: String
- startTime: Date
- categoryColorHex: String
```

---

