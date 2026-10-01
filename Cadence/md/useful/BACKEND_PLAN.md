# Cadence Backend Plan — Toward a Shared, OS-Agnostic Planning Brain

**Status:** planning doc, written 2026-07-04. Read this at the start of any session
that touches the backend, AIService, or cross-platform work.

---

## 1. Why this exists (context)

David is building Cadence natively for iOS first, with a future native Android
client (Kotlin + Jetpack Compose). Decisions made in conversation:

- **No shared client framework** (no KMP, no Flutter). The iOS app already works
  on SwiftData/SwiftUI; retrofitting would be a risky refactor for little gain.
- **Two native UIs, one backend.** The backend is the only code written once.
  It must be **OS-blind**: same endpoints, same JSON, no platform branching, ever.
- **Stateless backend, device is the source of truth.** No server database, no
  accounts, no sync. Each request carries the context it needs (the app already
  builds compact context strings — this pattern is kept, just relocated).
- **App scope is mostly frozen**: QoL + bug fixes on the client. The active
  investment is **AI planning and the deep planner** — which is exactly the part
  that belongs on the backend.
- Widgets: full WidgetKit on iOS; Android gets a rudimentary Glance widget or
  none. This is fine — widgets are never shared in any architecture.
- Notifications always fire **from the device** (local notifications). The
  server returns plans; the client schedules its own reminders from them.
  No push infra (APNs/FCM) for now.

### The core problem found in the codebase

Today the intelligence lives in the **Swift client**, and `server.js` is a dumb
pass-through (43 lines, all six routes hit the same `callClaude`):

| The "brain" today | Where it lives | Android impact if unchanged |
|---|---|---|
| System prompts (4 of them) | `Services/AIService+SystemPrompt.swift` | duplicate & keep in sync by hand |
| Prompt/context building | `Services/SchedulingContextBuilder.swift` | duplicate ~175 lines |
| Claude response parsing + validation | `Services/AIService.swift` (Raw* Decodables, ISO8601/slot parsing) | duplicate ~200 lines |
| Free-slot computation feeding the AI | `Services/SchedulerService.freeSlots` | duplicate ~100 lines |
| Business post-processing (e.g. clamping meal end to dinner window) | `AIService.parseMealSuggestions` | duplicate |

**The goal of this plan:** move all of that server-side, so each client is a thin
layer that sends structured JSON and receives *typed, validated decisions* — never
raw Claude text, never prompts.

```
BEFORE  iOS app: [SwiftData] → build prompt → parse Claude JSON → apply    server: pipe → Claude
AFTER   iOS app: [SwiftData] → send snapshot JSON ← receive decision JSON  server: slots + prompt + Claude + parse/validate
```

---

## 2. Modularity map — every process, classified

### Tier A — moves to the backend (the shared brain)

| Process | Current client entry | Current route | What moves |
|---|---|---|---|
| Schedule event from natural language | `AIService.scheduleEvent` (called from `AIInputView`) | `POST /api/schedule/add` | prompt build, Claude call, decision parsing |
| Move event | `AIService.moveEvent` | `POST /api/schedule/move` | same |
| Reschedule missed | `AIService.rescheduleMissed` | `POST /api/schedule/reschedule` | same |
| Meal suggestions | `AIService.suggestMealOptions` (from `WeeklyMealsView`) | `POST /api/meal/suggestion` | prompt build, parsing, slot-string→time resolution, dinner-window clamping |
| Habit weekly analysis | `AIService.analyzeHabits` (from `HabitDetailView`) | `POST /api/habit/analysis` | prompt build (trivial), response is plain text already |
| Deep project plan | `AIService.deepProjectPlan` | `POST /api/project/plan` | prompt build, phase parsing. **This is the growth area — new deep-planner features get built here, server-first.** |
| Free-slot computation *for AI flows* | `SchedulerService.freeSlots` (invoked inside AIService before each call) | — | server computes slots from the raw event snapshot the client sends. Client stops precomputing slots for AI requests. |
| All system prompts | `AIService+SystemPrompt.swift` | — | become server files (`prompts/`), deleted from the client |
| Intent classification for the "Ask AI" box | new (spec: `ai-planner.md`) | `POST /v1/schedule/interpret` | server-first — classifier + typed intent union, never existed on the client |
| Goal/phase → concrete events expander | new (spec: `ai-planner.md` §7) | shared by `/v1/schedule/generate` + `/v1/project/plan` | server-first shared building block |

### Tier B — stays native, but must remain *pure/portable* (port-by-hand later)

These run offline or need instant response; each is pure logic that translates
to Kotlin mechanically. Keep them free of SwiftUI/SwiftData internals.

| Process | File | Why it stays on-device |
|---|---|---|
| Instant conflict check when adding events | `SchedulerService.conflicts` (used by `AddEventView`) | synchronous UI validation, must work offline |
| Daily meal pass (breakfast/dinner placement, stale cleanup, missed-streak nudge) | `MealPlanningCoordinator` + `MealSchedulerService` | runs at app launch / day start, offline, wires local notifications |
| Overview statistics (completion ring, category breakdown, perfect days, chart data) | currently **inline in `OverviewView`** (~130 lines of computed properties) | pure aggregation of local data — a backend here would make local stats need network. Fix = extract into a pure `OverviewStatsService`, not a server call. |
| Dinner swap / remaining-dinner-slots | `MealSchedulerService` (used by `WeeklyMealsView`) | offline interaction |

### Tier C — stays native, platform-specific by nature (never shared)

| Process | Files |
|---|---|
| Persistence | SwiftData models / (Android: Room). Planned addition: `EventStatus.displaced` in `SupportingTypes.swift` (shared with the widget target — append raw value, never reorder). `.displaced` means "the planner moved this aside", **not** a failure — exclude it from missed/completion stats (audit `OverviewView`). See `ai-planner.md` §6. |
| Local notifications | `NotificationService` (Android: NotificationManager + AlarmManager) |
| Widgets + app-group sync | `WidgetSync`, `WidgetDataStore`, `CadenceWidget/*` (Android: Glance, optional/rudimentary) |
| All Views, navigation | `Views/` (Android: Compose — design once, implement twice) |

---

## 3. API contract v1 (draft)

Principles: **structured JSON in, typed decision out.** The server owns prompts,
Claude calls, parsing, and validation. Clients never see raw model output.
Version the base path (`/v1/...`) so future changes don't break shipped clients.

### Shared request objects

```jsonc
// EventSnapshot — compact, only what planning needs (mirrors compactScheduleString info)
// "id" is REQUIRED: move/reschedule/reorganize intents point at specific events.
{ "id": "UUID-string", "title": "Gym",
  "start": "2026-07-04T18:00:00+02:00", "end": "2026-07-04T19:00:00+02:00",
  "category": "Health", "status": "pending" }

// PrefsSnapshot — mirrors compactPreferenceString + windows
{ "workStartHour": 9, "workEndHour": 18, "bufferMinutes": 15,
  "priorityCategories": ["Work"], "aiLevel": "balanced",
  "avoidScheduling": [{ "weekdays": [2,4], "start": "12:00", "end": "13:00" }],
  // weekdays use ISO numbering: 1=Mon … 7=Sun. Clients convert from their
  // platform convention when encoding (Swift Calendar uses 1=Sun..7=Sat).
  "dinnerWindow": { "start": "19:00", "end": "21:30" },
  "mealGuidance": "vegetarian" }

// Every request includes:
{ "now": "2026-07-04T14:30:00+02:00", "timezone": "Europe/Bucharest", ... }
```

`now` + `timezone` come from the device — the server must never use its own clock
for planning (serverless runs in arbitrary regions).

### Endpoints

```
POST /v1/schedule/add        { now, timezone, description, events: [EventSnapshot], prefs }
POST /v1/schedule/move       { now, timezone, event, reason, events, prefs }
POST /v1/schedule/reschedule { now, timezone, event, missedCount, events, prefs }
  → all three return SchedulingDecision:
  { "action": "add" | "conflict" | "suggest_alternative",
    "event": { "title", "start", "end", "category" } | null,
    "conflictReason": "string" | null,
    "alternatives": [{ "start", "end" }] }
  (Server computes free slots from `events`+`prefs`; client no longer precomputes.)

POST /v1/schedule/interpret  { now, timezone, text, events: [EventSnapshot], prefs }
  → discriminated union on "intent" (full spec + intent catalog: ai-planner.md §3–§5):
  { "intent": "add" | "move" | "reschedule" | "reorganize" | "generate" | "clarify",
    "interpretation": "human-readable echo shown before commit",
    ...intentPayload }
  The single endpoint behind the "Ask AI" secretary box. Server classifies the
  intent, computes free slots, and returns a typed decision; the prompt prefers
  `clarify` over guessing when the target event or time is ambiguous. Mutating
  intents are always previewed and confirmed client-side.

POST /v1/schedule/generate   { now, timezone, period: {start, end}, goals,
                               events: [EventSnapshot], prefs }
  → { "events": [{ "title", "start", "end", "category" }] }
  Lightweight "fill my period with events for these goals" (ai-planner.md §7).
  Built on the shared goal/phase→events expander that /v1/project/plan will also
  use — the expander is Tier A backend brain, written once.

POST /v1/meal/suggestions    { now, timezone, days: 1..7 (optional, default 1),
                               existingMeals: [{name, prepTimeMinutes}], events, prefs }
  days defaults to 1 (today only) — meals are planned during the day, not a
  week ahead (client design decision).
  → { "suggestions": [{ "name", "prepTimeMinutes", "tags": [],
        "start": "ISO8601", "end": "ISO8601" }] }
  (Server resolves "WED 20:00"-style slots into concrete ISO dates and clamps to
   the dinner window — the logic currently in parseMealSuggestions/parseSlot.)

POST /v1/habits/analysis     { habits: [{ "name", "weekTotal", "priorWeekTotal" }] }
  → { "insight": "string" }

POST /v1/project/plan        { now, timezone, goal, deadline: "YYYY-MM-DD",
                               weeklyHours, constraints, prefs }
  → { "phases": [{ "title", "subtasks": [], "targetDate": "YYYY-MM-DD" | null }] }

POST /v1/plan/skeleton       { now, timezone, goal, goalType: "study"|"project",
                               deadline?: "YYYY-MM-DD", weeklyHours, constraints? }
  → { "plan": { "title", "goalType", "deadline": "YYYY-MM-DD" | null,
        "workUnits": [{ "id": "W1", "title", "objective", "estimatedMinutes",
          "archetype": "milestone"|"repetition",
          "constraints": { "afterUnit"?, "repeatOf"?, "minGapDays"?,
                           "notLastNDaysBeforeDeadline"? } }] },
      "capacity": { "neededMinutes", "availableMinutes", "cushionMinutes" } }
  The deep planner's thin whole-horizon frame (deep-planner-plan.md §3). One-shot
  intake for now; the multiturn clarify conversation replaces the entry point in
  increment 3. Uniquely, this route runs on claude-opus-4-8 + adaptive thinking +
  effort:"high" (quality over cost — deep-planner.md §6); createClaudeCaller now
  takes per-call model/thinking/effort overrides. Cushion is committed capacity
  (weeklyHours × weeks-to-deadline) minus the sum of workUnit estimates; slot-level
  feasibility is checked later at weekly placement, not here.

POST /v1/plan/week           { now, timezone, plan: { goalType, deadline?, workUnits },
                               window: { start, end }, weeklyHours,
                               progress: [{ workUnitId, scheduledMinutes, lastSessionDate? }],
                               events: [EventSnapshot], prefs }
  -> { "events": [{ "title", "start", "end", "category", "workUnitId", "objective" }] }
  **Deterministic - NO Claude call** (like /v1/calendar/ics). The skeleton already
  did the fuzzy->structured translation, so weekly planning is pure constraint
  satisfaction: services/weeklyPlanner.js picks the units due in the window
  (walking afterUnit / minGapDays / notLastNDaysBeforeDeadline against progress),
  caps at the weekly budget, and packs sessions into free slots round-robin across
  days. The client links returned events back to the plan via workUnitId. Instant,
  free, offline-capable, exact linkage.

POST /v1/plan/tweak          { now, timezone,
                               plan: { title, goalType, workUnits: [{ id, title, objective }] },
                               sessions: [{ ref, title, objective, start, end }],
                               instruction }
  -> { "edits": [{ "ref", "title"?, "objective"?, "durationMinutes"?, "done"?, "summary" }] }
  Small, cheap CONTENT-only edit of already-scheduled sessions. Runs on the DEFAULT
  (Sonnet) secretary model, NOT the Opus planner - the plan's work units are shared
  as context so the call stays light. Clarifies a vague objective into concrete
  steps, marks work done, changes a session's duration, or applies a free-form
  instruction across a multi-selection. ref echoes the client event id. Never
  reschedules (no date/time changes, no free-slot math) - placement stays
  deterministic/manual. Only changed fields appear per edit; ref + summary always do.

POST /v1/calendar/ics        { url, now, timezone, windowStart, windowEnd }
  → { "events": [{ "title", "start", "end", "allDay", "externalIdentifier" }],
      "feedName": "string" | null }
  Deterministic ICS feed fetch + RFC 5545 parse + RRULE expansion — NO Claude
  call. Stateless (feed URL re-sent on every sync, never stored, never logged —
  secret URLs carry auth). Full spec: `calendar-import.md` §4. Device-calendar
  import (EventKit / CalendarContract) stays client-side per platform.

GET  /v1/health              → { "status": "ok", "version": "1" }
```

### Error envelope (uniform)

```json
{ "error": { "code": "AI_UNPARSEABLE" | "AI_UPSTREAM" | "BAD_REQUEST" | "TIMEOUT" | "INTERNAL",
             "message": "human readable" } }
```

- Non-2xx always carries this envelope. Clients map `code` → user-facing message.
- Server retries **one** time on unparseable Claude output before returning
  `AI_UNPARSEABLE` (cheap reliability win, impossible to do cleanly client-side today).

### Auth (minimal, do before public hosting)

Single static bearer token in a header (`Authorization: Bearer <token>`), stored
in the app outside source control. Not real security — just keeps a public URL
from being an open Claude proxy on David's API key. Real auth only if the app
ever gets other users.

---

## 4. Roadmap — one phase per session, in order

### Phase 1 — Restructure the server (no client changes yet)
- Split `server.js` into `server/` project: `routes/`, `services/` (slot finder,
  prompt builders, parsers), `prompts/`, `lib/claude.js`.
- Port `SchedulerService.freeSlots` + merge logic to JS (with unit tests — port
  the cases from `CadenceTests`).
- Port `SchedulingContextBuilder` builders and the four system prompts.
- Port response parsing/validation (RawDecision, meal slot resolution + clamping,
  project plan parsing) with the retry-once rule.
- Implement `/v1/*` endpoints per the contract above. Keep old `/api/*` routes
  alive during migration.
- Tests for parsers/slot-finder run without hitting Claude (inject a fake caller,
  same trick as Swift's `_callAPI`).

### Phase 2 — Thin the iOS client, one endpoint at a time
Recommended order (simplest → richest): habits → project plan → schedule/add →
move → reschedule → meal suggestions.
- For each: `AIService.<method>` becomes *encode snapshot DTOs → POST /v1/x →
  decode typed response*. Delete the corresponding prompt/parsing code.
- When done: delete `AIService+SystemPrompt.swift` and most of
  `SchedulingContextBuilder`; `freeSlots` remains only if still used by
  native flows (meal daily pass uses `MealSchedulerService`'s own logic).
- Keep `_callAPI` injection point so unit tests still avoid the network.

### Phase 3 — Host it
- Deploy `server/` to a host. Default choice: **serverless (Vercel)** — the
  workload is pure request→response. Watch function timeout vs. Claude latency;
  if deep-planner calls run long, move to an always-on box (Railway/Fly/Oracle
  free tier). Either way the code is identical — only deployment config differs.
- Env: `ANTHROPIC_API_KEY`, `CADENCE_API_TOKEN` as host secrets.
- Replace the ngrok URL + add the bearer token in the iOS app config.
- Statelessness makes this trivial: nothing to migrate, no DB.

### Phase 4 — Untangle Tier B on iOS (portability hygiene)
- Extract `OverviewView`'s computed stats into a pure `OverviewStatsService`
  (input: events/meals/habits + date window; output: plain stat structs).
  The view keeps only rendering. Same testability win even if Android never happens.
- Audit `MealSchedulerService`/`MealPlanningCoordinator`: coordinator may touch
  SwiftData `Event` objects and `NotificationService`, but the *decisions*
  (which slots, which meals) should be pure functions returning plain values.

### Phase 5 — Deep planner growth (ongoing, server-first)
- All new planning intelligence (multi-step planning, phase→event expansion,
  re-planning) is built as **server endpoints first**, then a thin iOS UI.
  This way Android inherits every feature for free.

### Phase 6 — Android (when ready)
Client-only work, backend already done: Room models mirroring the Swift ones,
thin Retrofit/OkHttp client for `/v1/*`, Compose UI from the existing designs,
hand-port Tier B logic (small, pure), NotificationManager wiring,
optional Glance widget last.

---

## 5. Rules going forward (mirrored in CLAUDE.md)

1. **The backend is OS-blind.** No platform detection, no OS-specific branches.
2. **Clients never build prompts or parse raw model output.** If a new AI feature
   needs a prompt, it goes in `server/prompts/`, not in Swift.
3. **AI-related Swift code returns plain value types** (`EventDraft`,
   `MealSuggestionResult`, `ProjectPhaseData`) — views apply them to SwiftData.
   AIService must never import SwiftUI, touch SwiftData contexts directly,
   schedule notifications, or call WidgetSync.
4. **Server stays stateless.** Device is the source of truth; every request is
   self-contained. Introducing server-side storage is a deliberate decision,
   not a convenience.
5. **Device time rules.** `now` + `timezone` always come from the client request.
6. **Version the contract.** Breaking response changes → `/v2`, never mutate `/v1`.
7. **New planning features are designed contract-first**: define the request/
   response JSON in this file, then implement server, then client.
