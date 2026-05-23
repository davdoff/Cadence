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

---

## Data Architecture (Token Efficiency First)

This is the most critical design concern. The goal is to send the minimum necessary context to Claude while maintaining high-quality outputs.

### Principle: Never send raw data to Claude — send summaries and deltas

#### Local Data (never sent to API unless needed)
- Full event history
- Completed/missed status logs
- Raw meal list
- Performance stats

#### What gets sent to Claude API
Only the **minimum structured context** required for the current task:

| Task | What to send |
|------|-------------|
| Add event from prompt | User message + compressed schedule window (next 48–72h only) + relevant preferences |
| Reschedule missed event | Missed event details + compressed free slots (next 7 days) + preferences |
| Meal planning | Meal list + upcoming schedule gaps + meal frequency preference |
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
AI Service (Claude API calls — only when needed)
    ↓
Preferences Store (UserDefaults or local DB)
    ↓
Notification Service (UNUserNotificationCenter — local only for v1)
    ↓
Widget Extension (WidgetKit — reads from shared AppGroup store)
```

### Key Design Rule
**Do local logic first.** Only escalate to Claude API when the task requires language understanding or preference-based reasoning. Free slot detection, basic conflict checking, stats generation, notification scheduling, and widget data writing — all local.

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

---

## App Release Flow (First Release Checklist)

### Phase 1 — Development
- [ ] Core data model defined (Event, Category, Preference, Meal)
- [ ] Local CRUD working for all event types
- [ ] AI Service wrapper built (with token-efficient formatting)
- [ ] Preferences screen complete
- [ ] Performance report screen (local only)
- [ ] Meal planning flow complete
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

---

## Prompt Engineering Guidelines

### For Claude Code Sessions
Always open with:
1. Which feature you're building
2. The relevant data models involved
3. What already exists (don't let Claude re-invent things)
4. The exact output you want (a SwiftUI view, a service class, a test file)

### For In-App Claude API Calls
- System prompt = role definition + output JSON schema + hard constraints
- User message = only the minimum dynamic data (compact schedule + event description)
- Never ask Claude open-ended questions — always ask for a specific structured decision
- Add a token budget to your system prompt: *"Be concise. Do not explain your reasoning unless asked."*

### Iteration Rule
When a Claude API response is poor quality, fix the system prompt or data format — not the parsing code. Bad outputs are almost always a context or instruction problem.

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

## First Two Steps (Where to Start)

**Step 1 — Define and lock your data models**
Before writing any UI or API code, finalise your core data models (Event, Category, Preferences, Meal) in a single Swift file. Everything else depends on this. Use SwiftData for persistence (modern, less boilerplate than Core Data for a new project). Also define `ScheduleWidgetData` and `WidgetEvent` at this stage — they are lightweight Codable structs and cost nothing to define early.

**Step 2 — Build the local scheduler service**
Write the logic that finds free slots, detects conflicts, and formats the compact schedule string. This is the engine the AI service will depend on. Test it thoroughly with unit tests before touching the Claude API. This step also forces you to think through your data flows before you add AI complexity.

---

## Notes for Claude Code Context

When starting a new Claude Code session, paste the relevant section of this README (data models, the feature you're working on, and the CI/CD setup). You do not need to paste the full file every time — just the sections relevant to the current task. Keep sessions focused and scoped.
