# Deep Planner — Execution Direction (v2)

**Status:** direction doc, written 2026-07-30. Companion to and supersedes the
*recommendation* of `deep-planner.md` (the research/options doc — still the
reference for use cases, market scan, and model choices). This file captures
David's refined stance and turns it into a build loop. Nothing here is
implemented yet.

**David's stated bias:** accuracy over cost (use Opus for the planning brain),
focused goal-specific sessions, and a plan that stays alive week to week.

---

## 1. What changed from the research doc

`deep-planner.md` recommended **Option C** (two-stage pipeline + capacity math +
*one* bounded clarify round). David's session refined it in three ways:

1. **Rolling, week-by-week planning — not a full-horizon split.** The long-term
   goal is *never* fully decomposed into a schedule upfront. Instead: plan this
   week's sessions in detail, complete them, give feedback, then the next week is
   planned with that feedback in hand. (Agrees with the doc's "windowed stage 2"
   + "living plan §5", but promotes it from a later increment to the **core loop**.)
2. **Multiturn clarifying intake — not a single round.** The intake is a short
   *conversation*, richer context in exchange for more Opus tokens. Bounded by
   *sufficiency* (ask until there's enough to plan) with a hard cap, not a fixed
   count.
3. **Progress is the gate.** Completing a week's sessions + a feedback note is the
   required input to unlock planning the following week. Progress tracking is not
   a nice-to-have; it's how the loop advances.

The reconciliation that keeps deadline-awareness alive under (1) is in §3.

---

## 2. The core loop (what the product actually does)

```
INTAKE (multiturn, Opus)  ─►  SKELETON (thin, whole-horizon)  ─►  ┐
                                                                  │
   ┌──────────────────────────────────────────────────────────◄──┘
   ▼
WEEK N: plan sessions ─► do sessions ─► weekly review + feedback ─► WEEK N+1: plan
                          (progress tracked per session)              (feedback in context)
                                                            … until deadline / goal met
```

- **Intake** runs once per goal: a bounded multiturn Q&A that gathers scope,
  materials, energy times, constraints.
- **Skeleton** is generated once: milestones + total workload budget + deadline
  anchor + spacing intent. **Cheap, thin, rarely regenerated.** It is *not* a
  schedule — it's the frame that every weekly plan is planned *against*.
- **Weekly planning** is the repeated unit: turn the relevant slice of the
  skeleton into concrete, objective-carrying sessions for the next 7 days,
  placed into real free slots.
- **Weekly review** closes each cycle: completed/skipped sessions + a short
  feedback note become input to the next week's planning call.

---

## 3. Architecture: thin skeleton + rolling weekly detail

The trap in "never split the whole horizon" is losing deadline-awareness
(backward planning, cushion math, cross-week spacing). Solution: **two altitudes.**

**Skeleton (whole-horizon, thin, durable).** Generated once from the intake.
Holds: ordered milestones/topics, an `estimatedMinutes` budget per unit, the
deadline anchor, and spacing intent (e.g. "revisit topic X at growing
intervals", "last 3 days before exam = review only"). This is where **cushion
math** lives — total needed vs. total available across the whole window — so an
infeasible goal is caught in week 1. The skeleton is *lightweight*: it never
assigns clock times. It rarely changes (only on scope change or a big miss).

**Weekly detail (one window, rich, regenerated each week).** Takes the skeleton +
the coming week's real free slots + progress-so-far, and produces concrete
sessions with objectives, placed conflict-free. This is where accuracy matters
and where per-week Opus spend is justified.

Why this satisfies both of David's constraints: the horizon is *never* fully
scheduled upfront (only the thin skeleton exists ahead of time), **and** each
weekly plan is still deadline-aware because it's planned against the skeleton's
budget + spacing + deadline.

**Reuse:** `server/services/expander.js` → `expandGoalsToEvents(...)` already
turns goal/phase text + `freeSlots` + `prefs` into placed events for a period.
The weekly planner feeds it the week's chosen sessions; deterministic
overlap/spacing validation backstops placement (per doc §3.2 / §4-B).

---

## 4. Multiturn intake (sufficiency-gated, stateless)

- **Client holds the conversation, server stays stateless.** Each turn the client
  resends the growing Q&A transcript; the server never stores it (CLAUDE.md
  invariant). "Multiturn" = accumulated transcript in every request, not server
  session state.
- **Sufficiency gate, not fixed count.** The model returns either
  `{ status: "ask", questions: [...] }` or `{ status: "ready" }`. It keeps asking
  until it judges it has enough to build a good skeleton. **Hard cap** (≈4–5
  turns) so it can't loop forever; the user can also tap "just plan it" to force
  `ready` at any point.
- **Tappable options where possible** (reuse the existing `clarify` card UI in
  `AIInputView`) so answering is fast, with free-text fallback.
- Model: **`claude-opus-4-8`** + adaptive thinking for the readiness/question
  generation and the skeleton build (accuracy-over-cost); a cheaper model is fine
  for pure weekly placement (doc §6).

---

## 5. Progress & feedback (the gate)

- Deep-planner events carry `planId` + `workUnitId` links (SwiftData), so
  completion status rolls up to plan progress. Reuses existing `EventStatus`
  (`pending/completed/missed`, + planned `displaced`).
- **Deterministic repair first** (no AI): a single missed session → next valid
  free slot within its constraints. Covers most drift for free, offline.
- **Weekly review card** (Today view): "4/5 sessions done, cushion 3h, next up:
  recall-test ch.5–6." Pure device-side rendering of plan state.
- **Feedback → next week.** The review lets David add a short note ("chapter 4 was
  harder than expected", "no time Tuesdays"). That note + the completion record
  are passed into the next weekly-planning call, and can trigger a skeleton
  adjustment (rebudget remaining units) when cushion goes negative or misses pile
  up.

---

## 6. Contract sketch (fold into `BACKEND_PLAN.md` when execution starts)

Stateless, OS-blind, `now`+`timezone` from device, typed DTOs only.

```jsonc
POST /v1/plan/intake     // multiturn clarify; client resends transcript each turn
  { now, timezone, goal, deadline?, weeklyHours, constraints?, materials?,
    transcript: [{ q, a }] }          // grows each turn; server stores nothing
  → { status: "ask",   questions: [{ q, options: [string] }] }   // keep going
  | { status: "ready", intakeSummary }                            // enough to plan

POST /v1/plan/skeleton   // once; thin whole-horizon frame + cushion
  { now, timezone, intakeSummary, events: [EventSnapshot], prefs }
  → { plan: { title, goalType, deadline?,
              workUnits: [{ id, title, objective, estimatedMinutes,
                            archetype: "milestone"|"repetition",
                            constraints: { afterUnit?, repeatOf?, minGapDays?,
                                           notLastNDaysBeforeDeadline? } }] },
      capacity: { neededMinutes, availableMinutes, cushionMinutes } }

POST /v1/plan/week       // repeated; detail the next window against the skeleton
  { now, timezone, plan, window: {start,end},
    progress: [{ workUnitId, status }], feedback?: string,
    events: [EventSnapshot], prefs }
  → { events: [{ title, start, end, category, planId, workUnitId, objective }],
      capacity }                       // refreshed cushion after this week

POST /v1/plan/rebudget   // only when cushion goes negative / misses pile up
  { now, timezone, plan, progress, reason, events, prefs }
  → { plan (revised remaining workUnits), capacity }
```

`/v1/plan/week` placement is backed by `expander.js`; the skeleton and intake use
Opus + structured outputs so `AI_UNPARSEABLE` is impossible by construction.

---

## 7. Build increments (each independently shippable)

1. **Skeleton + manual weekly detail.** `/v1/plan/skeleton` (Opus, structured
   output, cushion math) + `/v1/plan/week` wired to `expander.js`; SwiftData
   `ProjectPlan`/`WorkUnit` models + a basic intake form (single-shot for now) +
   "plan next week" button. David can study off this immediately. *(Intake is
   still one-shot here — multiturn is increment 3.)*
   - ✅ **Server `/v1/plan/skeleton` done** — Opus 4.8 + adaptive thinking +
     effort:high (per-call overrides added to `lib/claude.js`), the two-archetype
     `planSkeleton` prompt/builder/parser, and weeklyHours-based cushion math,
     with route tests. *(Structured outputs deferred — retry-once parser stands.)*
   - ▢ Next: SwiftData `ProjectPlan`/`WorkUnit` models + `AIService.planSkeleton`
     DTO client, wire `DeepPlanIntakeView.generatePlan()`, then `/v1/plan/week`.
2. **Progress loop.** `planId`/`workUnitId` on events, weekly review card,
   deterministic missed-session repair, feedback note captured and fed into
   `/v1/plan/week`.
   - ✅ **Server `/v1/plan/week` done** — decided to make it **fully deterministic
     (no Claude call)**: since the skeleton already carries objectives + estimates,
     weekly planning is pure constraint satisfaction. `services/weeklyPlanner.js`
     selects due units (afterUnit / minGapDays / notLastNDaysBeforeDeadline / budget)
     and packs them into free slots round-robin; pure-function + route tests pass.
   - ▢ Next (client): `Event.planId`/`workUnitId`/`objective` (shared model,
     append), `AIService.planWeek`, "Plan this week" button that computes progress
     from linked events and inserts the returned events; then the review card.
3. **Multiturn intake + rebudget.** `/v1/plan/intake` (sufficiency-gated,
   transcript-in-request) replaces the one-shot form; `/v1/plan/rebudget` for
   negative-cushion / pile-up replanning. This is what makes it *deep*.

Defer the agentic planner (doc Option D) until plans need external discovery
(e.g. plan from a syllabus URL).

---

## 8. Open questions for David

- **Skeleton visibility:** does David want to *see and edit* the whole-horizon
  skeleton (milestones/budget), or is it an internal frame and he only ever
  interacts with the current week? (Affects how much UI increment 1 needs.)
- **Multiturn cap:** hard cap at 4–5 questions, or let it run with only the
  "just plan it" escape hatch?
- **Rebudget trigger:** automatic (fires a preview when cushion goes negative),
  or always user-initiated ("I lost this week, replan")?
- **File home:** keep this as a separate direction doc, or merge its §7 build
  order into `NEXT_VERSION.md` / the roadmap in `BACKEND_PLAN.md`?
