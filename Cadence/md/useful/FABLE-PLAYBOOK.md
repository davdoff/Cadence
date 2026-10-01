# How I used Fable on this project — a reusable playbook

> Written after the 2-day construction-dashboard demo sprint. This file documents the
> *pattern*, not the dashboard specifics, so it can be copy-pasted into a new project's
> `CLAUDE.md`/sprint doc and adapted.

## The core idea

**Fable is expensive to run as the standing driver.** If it holds the whole conversation
through a multi-hour build, it re-reads every diff and every file, and credits burn fast.
But Fable is *excellent and cheap* at two specific jobs: **planning** (small context, no
code churn) and **reviewing a bounded diff** (bounded context in, bounded credits out).

So the rule was: **Fable never implements.** It plans at the start, and reviews at
milestones. All the token-heavy work — writing code — runs on Opus or Sonnet.

```
Fable  → plan the work                     (cheap: reads a few small .md files)
Opus   → drive the build, do the hard parts (standing session model)
Sonnet → delegated for simple/parallel bits (spawned as agents, cheaper per-token)
Fable  → review the diff at each milestone  (cheap: bounded diff, no edits)
```

## Why this split, specifically

- **Plan on Fable:** at the start of a sprint you're mostly reading/writing a short plan
  doc, not touching code. Low token volume — a good fit for a pricier model, and you get
  Fable's judgement on scope/sequencing before any code exists to argue about.
- **Build on Opus:** implementation is where tokens actually get spent — reading existing
  code, writing new code, iterating. You want your default/driver model here to be the one
  you're using for everything else in the session, not a model that's also holding
  planning + review context.
- **Delegate mechanical work to Sonnet:** anything simple, well-scoped, and parallelizable
  (seed data, admin registration, styling passes, doc updates) doesn't need Opus-level
  reasoning. Spawning it as a Sonnet subagent keeps it out of the expensive path entirely.
- **Review on Fable:** a milestone diff is small and self-contained — cheap to hand to a
  pricier model for a sharp, bounded pass (correctness, security, simplification) without
  it needing the whole session's history.

## How to set it up in a new project

### 1. Pin the roles as agents, don't rely on convention alone

Convention ("I'll remember to switch models") breaks under time pressure. What actually
holds is pinning the model in an agent's frontmatter — a subagent's `model:` field takes
precedence over whatever session model spawned it, so a delegated task runs on *exactly*
the pinned model regardless of what you're driving from.

Create three agent files in `.claude/agents/`:

**`.claude/agents/builder.md`** — pinned `opus`, for complex/interdependent implementation:
```markdown
---
name: builder
description: Implementation agent for complex or interdependent work. Pinned to Opus.
model: opus
---

You are the implementation agent for <project>. Read `<SPRINT_DOC>.md` and `CLAUDE.md`
at the repo root before starting — they carry the plan, stack, and working agreements.

How to work:
- Follow the stack/architecture in the sprint doc; flag deviations before making them.
- Small, single-purpose modules; thin views/handlers, logic lives in services/models.
- Every behavioral change ships with a test.
- After adding/moving/removing files, update the file map + README.
- Report back concisely: what changed, where, how to verify.
```

**`.claude/agents/quick.md`** — pinned `sonnet`, for mechanical/parallel work:
```markdown
---
name: quick
description: Implementation agent for simple, well-scoped, parallelizable tasks. Pinned to Sonnet.
model: sonnet
---

You are a fast implementation agent for <project>. Read `<SPRINT_DOC>.md` and `CLAUDE.md`
for context before starting.

Use this agent only for tasks that are simple and self-contained: fixtures/seed data,
registration boilerplate, styling passes, small focused tests, docs updates.

How to work:
- Stay in scope — do exactly the task; don't refactor adjacent code.
- Match the existing code's style and structure.
- If the task turns out to be interdependent or ambiguous, stop and say so rather than guessing.
- Behavioral changes ship with a test.
- Report back concisely: files touched and how to verify.
```

**`.claude/agents/fable-reviewer.md`** — pinned `fable`, review-only, restricted tools:
```markdown
---
name: fable-reviewer
description: Review-only agent pinned to Fable. Reviews the current diff, never edits.
model: fable
tools: Bash, Read, Grep, Glob
---

You are a review-only agent for <project>. You do **not** edit files — you review and
report. Read `<SPRINT_DOC>.md` and `CLAUDE.md` for context and working agreements.

Review the current diff (use git to see what changed) for, in priority order:
1. Correctness — does the flow actually work end to end?
2. Access control — permission gates enforced server-side, not just hidden in the UI.
3. Data/security-sensitive areas specific to this project (e.g. file uploads, PII).
4. Data integrity — no silent edits, no accidental hard deletes.
5. Simplification / reuse — flag god-objects and duplication.

Report the findings that matter, most severe first, with `file:line` and a one-line fix
suggestion. Skip nitpicks that don't affect the goal.
```

Note the `tools:` restriction on the reviewer — giving it only `Bash, Read, Grep, Glob`
makes "never edits files" structurally true, not just an instruction it could ignore.

### 2. Write the plan on Fable

Start the session on Fable (`/model fable`), point it at your sprint/requirements doc,
and have it produce or refine the plan — a timeline broken into tasks, each one tagged
with which model should execute it:

```markdown
- [ ] Scaffold project, deps, settings. `[opus]`
- [ ] Register admin, seed fixtures. `[quick/sonnet]`
- [ ] Core data model + migrations (interdependent). `[opus]`
- [ ] Dashboard aggregation + charts. `[opus]`
- [ ] Styling pass, docs updates. `[quick/sonnet]`
- [ ] Tests for aggregation math. `[quick/sonnet]`
```

Tagging each line with `[opus]` or `[quick/sonnet]` up front means you're not deciding
mid-build whether something is "complex enough for Opus" — that judgement call happens
once, cheaply, during planning.

### 3. Switch the driver to Opus and build

`/model opus`. Opus is now the standing session — it does the complex/interdependent work
directly, and for anything tagged `[quick/sonnet]` in the plan, it spawns the `quick`
agent instead of doing it inline. This is the expensive stretch of the sprint; keep Fable
out of it entirely.

### 4. Review on Fable at milestones

At each milestone (end of a feature, end of a day), either:
- switch the session to Fable and run your review workflow on the current diff, or
- spawn the `fable-reviewer` agent and hand it the diff to review in the background.

Either way the cost is bounded by the diff size, not the whole conversation.

### 5. Fix findings on Opus/Sonnet, re-review if the fix was non-trivial

Findings come back from Fable; the fix itself is implementation, so it goes back through
Opus (or `quick` if it's mechanical). Don't let Fable edit files to "save a round trip" —
that's the exact pattern this whole setup is designed to avoid.

## Guardrails that actually held under time pressure

- **State the rule explicitly in your sprint doc**, not just in your head: "never
  Edit/Write from a Fable session." Under deadline pressure it's the first thing you'll
  skip if it isn't written down somewhere you re-read every session.
- **Know the one real gap:** a forked subagent (`subagent_type: "fork"`) always inherits
  the *parent's* model and ignores a `model` override — so forking from a Fable session
  would still run on Fable, silently breaking the "Fable never implements" rule. To keep
  the pin, delegate to a **named** agent (`builder`/`quick`/`fable-reviewer`), never a
  fork, when the model matters.
- **Re-read the sprint doc every session.** Model-of-the-day decisions drift if the
  plan/protocol isn't the first thing loaded each time you resume work.

## What this bought us, concretely

Across the 2-day sprint: one Fable planning pass at the start, three Fable review passes
at milestones (Day-1 backend, dashboard, table+import), everything else on Opus/Sonnet.
All review findings got fixed and re-verified before moving on. The pattern held for the
whole sprint without needing a mid-sprint correction.
