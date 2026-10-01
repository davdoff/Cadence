# Cadence AI Planner — Design & Contract

**Status:** design doc, written 2026-07-05. Read this together with
`BACKEND_PLAN.md` before touching the AI planner, `AIService`, or the server.
This spec is **contract-first**: the JSON contract is defined here first, then the
server implements it, then the iOS client is thinned to a typed DTO exchange.

Scope: the **default AI planner** — the "Ask AI" natural-language box. Not a
rewrite of the deep project planner (though generate shares logic with it, §7).

---

## 1. Vision & interaction model

The AI planner is a **secretary you talk to**. Design bias:

- **Talk-first.** The primary surface is one natural-language box. You type what
  you want in plain language; the assistant figures out the intent.
- **Lazy-friendly.** The user should not have to think about their schedule or
  pick a "mode" before typing. No mode chips, no forms for the common case.
- **Nothing happens behind your back.** Every schedule change is preceded by a
  visible **interpretation** ("Adding 'Dentist', Fri 2–3pm") and a **confirm**.
- **Direct manipulation is the secondary path.** Tap-an-event → move, drag, etc.
  are the offline/precise complement for when you already know exactly what you
  want — not the main route. (Not built here; noted so the box stays primary.)

---

## 2. Root cause of "unexpected responses" (do not re-diagnose)

Today `AIInputView` is hard-wired to `AIService.scheduleEvent` → `/api/schedule/add`.
**There is no intent detection.** Every request runs the add-a-new-event pipeline,
so "move my gym to tomorrow" creates a *new event titled that*. The other flows
(`moveEvent`, `rescheduleMissed`, `deepProjectPlan`) exist but are wired to **zero
UI**. The system prompt's `add | conflict | suggest_alternative` are *sub-states of
add*, not intents.

**Conclusion:** better wording / instruction text cannot fix this. The fix is the
intent refactor below. Tab guidance (§8) is expectation-setting *on top of* it.

---

## 3. New contract: `POST /v1/schedule/interpret`

The single endpoint behind the secretary box. Server owns the classification
prompt, free-slot computation, response parsing, and the retry-once rule
(per `BACKEND_PLAN.md`). Client sends a snapshot + raw text, receives a typed
decision — never raw model output, never a prompt.

**Request**
```jsonc
{
  "now": "2026-07-05T14:30:00+03:00",   // device clock — server never uses its own
  "timezone": "Europe/Bucharest",
  "text": "move my gym to tomorrow morning",   // what the user typed, verbatim
  "events": [EventSnapshot],                    // EventSnapshot now REQUIRES "id"
  "prefs": PrefsSnapshot
}
```

**Response — discriminated union on `intent`, always with a human echo**
```jsonc
{
  "intent": "add" | "move" | "reschedule" | "reorganize" | "generate" | "clarify",
  "interpretation": "Moving 'Gym' to Sat 08:00–09:00",  // shown before commit
  ...intentPayload   // see §4
}
```

Notes:
- The server **computes free slots** from `events` + `prefs`; the client stops
  precomputing slots for AI requests (matches `BACKEND_PLAN.md`).
- Internally the server **dispatches to the existing per-intent building blocks**
  (add / move / reschedule prompt + parse). Interpret is a classifier + router in
  front of them, not a second brain — keep it DRY.
- `EventSnapshot` **must carry a stable `id`** so `move` / `reschedule` /
  `reorganize` can point at a specific event. (Contract addition, §10.)

---

## 4. Intent catalog (payload per intent)

| intent | payload | applied by client as |
|---|---|---|
| `add` | `{ event:{title,start,end,category}, conflictReason?:string\|null, alternatives:[{start,end}] }` | insert new `Event(source:.ai)` (keeps today's add/conflict/suggest_alternative as add sub-states) |
| `move` | `{ targetEventId, newStart, newEnd, alternatives:[{start,end}] }` | reschedule an existing event by id |
| `reschedule` | `{ targetEventId, newStart, newEnd }` | move a missed/displaced event to a free slot |
| `reorganize` | `{ moves:[{targetEventId,newStart,newEnd}], displaced:[eventId] }` | apply the moves; set `displaced` events to `.displaced` (§6) |
| `generate` | `{ events:[{title,start,end,category}] }` | insert a batch of generated events (§7) |
| `clarify` | `{ question:string, options:[string] }` | show a question, feed the answer back into a new interpret call |

All time fields are ISO8601 with the device UTC offset (never `Z`), matching the
current parsing rules in `AIService`.

---

## 5. `clarify` + always-confirm (the fix)

Two mechanisms, both required:

1. **`clarify` intent.** The prompt is hardened to **prefer `clarify` over
   guessing** whenever the target event or the time is ambiguous (e.g. two events
   match "dentist", or no time was given for a move). Instead of a wrong mutation,
   the assistant asks. The client shows the question + options and sends the answer
   back through `/v1/schedule/interpret` as a follow-up `text`.
2. **Always-confirm preview.** Every *mutating* intent returns a preview the user
   confirms before anything is written. `AIInputView` already has the add
   confirm-card pattern — **generalize it** to render move / reschedule /
   reorganize / generate previews. `clarify` renders as a question card.

Together these kill "unexpected responses": nothing mutates silently, the
interpretation is always visible, and ambiguity becomes a question, not a guess.

---

## 6. Reorganize + `displaced` status

Reorganize ("clean up my afternoon") is the riskiest intent. v1 keeps it available
but **conservative and reversible**:

- Add **`EventStatus.displaced`** in `Cadence/Models/SupportingTypes.swift`
  (`EventStatus` currently: `pending, completed, missed`). This is a **shared
  model** used by app *and* widget — add it migration-safely (raw value append,
  no reordering).
- When reorganize proposes `moves` + `displaced`, the client shows the whole plan
  for confirmation. On confirm: apply the moves; set each `displaced` event to
  `.displaced`.
- Displaced events surface in a new **"Needs rescheduling" tray** (a small view).
  Each can be sent through the existing `rescheduleMissed`-style flow (now the
  `reschedule` intent) to find it a new slot.
- **`.displaced` is kept out of missed/completion stats** — it means "the planner
  moved this aside", not "you failed it". Audit any stat that filters on
  `.missed` (e.g. `OverviewView`) so `.displaced` is excluded from failure counts.
- Reorganize **never silently rearranges the day** — no moves without the
  confirm step.

---

## 7. Generate — layered config + shared expansion

Resolves David's open question ("Settings or AI tab?") and "could be in both".

**Config layering** (the answer to Settings-vs-AItab — it's *both*, layered):
- **Standing truths → Settings**, carried in `PrefsSnapshot`: work hours, buffers,
  `avoidScheduling`, priority categories, `aiAggressiveness`. Set once, rarely
  touched. A lazy user should never re-type these.
- **Momentary intent → the request**: period + goal/factors + per-request
  overrides ("plan my exam prep for the next 2 weeks, evenings only").
- **Server merges both.** Principle: *standing truths live in Settings, momentary
  intent lives in the box, the AI always sees both.*

**New endpoint** `POST /v1/schedule/generate`
```jsonc
{ "now", "timezone", "period": {"start","end"}, "goals": "…/factors…",
  "events": [EventSnapshot], "prefs": PrefsSnapshot }
→ { "events": [{ "title","start","end","category" }] }
```
Lightweight "fill my week" — distinct from the phase-based deep planner.

**Shared building block** — a server-side **phase/goal → concrete events expander**
that BOTH `/v1/schedule/generate` and the deep planner (`/v1/project/plan`) call.
This is why generate can live in both without duplicated logic: the deep planner
produces phases; the same expander turns phases (or raw goals) into scheduled
events against free slots + prefs.

**Factors are left open/extensible** (deferred, §11). Starting menu to grow by
testing: upcoming deadlines, habit goals (from `Habit`), free capacity in the
window, time-of-day energy preferences, priority categories.

---

## 8. Tab guidance (expectation-setting)

In `AIInputView`, on top of the refactor:
- A one-line helper describing the box's range (not just "add").
- A few tappable **example chips** that fill the field:
  "move my gym to tomorrow morning", "find me 2h for taxes this week",
  "clean up my afternoon", "plan my week's workouts".

This teaches the box's capabilities without a manual and reduces mis-worded
requests — but it is *secondary* to the intent refactor, not a substitute.

---

## 9. Client-side shape (thin, per CLAUDE.md rules)

- New plain value type **`AssistantDecision`** enum (cases: `add`, `move`,
  `reschedule`, `reorganize`, `generate`, `clarify`) returned by a new
  `AIService.interpret(text:events:preferences:) async throws -> AssistantDecision`.
  Reuse existing `EventDraft` / `SchedulingDecision` sub-shapes where they fit
  (e.g. the add case).
- `AIService` **stays detached**: no SwiftUI import, no SwiftData context access,
  no notification scheduling, no `WidgetSync`. It decodes typed DTOs and returns
  plain values; **views** apply them to SwiftData and schedule notifications
  (CLAUDE.md rule 3).
- `EventSnapshot` gains `id`; add request DTO encoders for interpret + generate.
- Keep the `_callAPI` injection point so unit tests avoid the network.

---

## 10. Contract additions to fold into `BACKEND_PLAN.md`

When execution starts, update `BACKEND_PLAN.md` so it stays the source of truth:
- Add `id` to the `EventSnapshot` shared request object.
- Add `POST /v1/schedule/interpret` and `POST /v1/schedule/generate` to the
  endpoint list, with the request/response shapes above.
- Note the shared **event-expansion service** under Tier A (backend brain).
- Note **`EventStatus.displaced`** as a Tier C (native persistence) addition,
  and that `.displaced` is excluded from missed/completion stats.

---

## 11. Deferred / incremental (do not invent these later — they're intentional)

- **Auto-commit vs always-confirm.** v1 = always-confirm. The future dial is the
  existing `UserPreferences.aiAggressiveness` (1–5): low = confirm everything,
  high = auto-commit low-stakes single adds, prompt only on conflicts / multi-event
  changes. Tune by testing.
- **Generate factor set.** Start with the menu in §7; grow it from real usage.

---

## 12. Build order (contract-first)

1. **Contract.** Fold §3–§7 + §10 into `BACKEND_PLAN.md`.
2. **Server** (BACKEND_PLAN Phase 1 style, injectable fake Claude caller for tests):
   - intent-classification prompt + `/v1/schedule/interpret` route + parsers,
     with retry-once on unparseable output;
   - `/v1/schedule/generate` route + the shared phase/goal→events expander.
3. **Client:**
   - `EventStatus.displaced` (shared model) + "Needs rescheduling" tray;
     exclude `.displaced` from missed/completion stats.
   - `AssistantDecision` + `AIService.interpret` (thin DTO exchange).
   - Rewire `AIInputView` to call interpret; generalize the confirm card to all
     intents; add guidance line + example chips.

---

## Reuse (don't reinvent)

- `UserPreferences.aiAggressiveness` — future auto-commit dial.
- `EventStatus.missed` + the `rescheduleMissed` flow — model for the displaced
  review/reschedule path.
- The add confirm-card in `AIInputView` — generalize, don't rebuild.
- `SchedulerService.freeSlots` + `SchedulingContextBuilder` builders — reused
  server-side (their port is already scoped by `BACKEND_PLAN.md`).
