# Prompt Caching & Call Cost — Cadence AI Calls

Status: **implemented** (server + client). This doc is both the plan and the
description of how the thing works, because the *why* behind each choice is the
part that can't be re-derived from the code.

Goal: cut the cost of repeat AI calls without losing per-user personalisation —
and without quietly making quality worse.

---

## 1. How caching works (the short version)

- Caching is a **prefix match**. Everything *before* a `cache_control`
  breakpoint is stored after the first call; everything *after* it is processed
  fresh every time.
- You still send the full prompt every call. The provider recognises the
  identical prefix and skips reprocessing it, so those tokens bill at roughly a
  tenth of normal input.
- **Opt-in only.** Nothing is cached unless you mark a breakpoint.
- **Lifetime:** 5 minutes by default, and *a cache read refreshes the timer*.
  Continuous traffic keeps an entry alive indefinitely at the 5-minute TTL, which
  is why we don't use the 1-hour TTL (it doubles the write price and buys nothing
  when requests arrive less than 5 minutes apart).
- **Cache writes cost ~1.25×** normal input. Break-even is two calls.
- There is a **minimum cacheable prefix** below which caching silently does not
  happen — no error, just `cache_creation_input_tokens: 0`. It is
  **model-dependent and not monotonic across generations**: 512 tokens on
  Opus 5, 1024 on Sonnet 5. Check it before assuming a prompt caches.
- The prefix must be **byte-for-byte identical**. Whitespace, a reordered
  preference, an interpolated timestamp — any of those is a miss.

---

## 2. Prompt structure

Order matters — most stable first, most volatile last.

```
1. System prompt   (role, intent list, output schema, constraints)  — frozen, identical for ALL users
   ── the one breakpoint ──
2. NOW, SCHEDULE, FREE_SLOTS, STATS, PREFS, USER_REQUEST            — volatile, never cached
```

**One breakpoint, not two.** An earlier draft of this plan put a second
breakpoint after a per-user preference block. That was wrong for Cadence:
`prefsLine()` renders about 30 tokens, and a 30-token span can never form its own
cacheable prefix (the floor is 512–1024). It would have burned one of the four
available breakpoint slots for zero reads, while adding a byte-stability
requirement to prefs for no reason. Prefs stay in the payload with everything
else volatile.

**The cached prefix is shared across all users.** Caches are scoped per
workspace and Cadence's server holds a single API key, so *every* user's
`interpret` call reads the same entry. There is no per-user warm-up, and the
prefix stays hot as long as anyone is using the app. This is the main reason
caching pays here at all, and the reason a per-user breakpoint would have been
strictly worse.

**Events and free slots never go in the cached part.** The schedule changes too
often to ever hit.

---

## 3. What is actually implemented

### `server/lib/claude.js` — the breakpoint

`callClaude({ system, payload })` keeps taking `system` as a plain **string**;
the block-wrapping happens in the one place that talks to the SDK, so no route,
service, or test knows about caching:

```js
system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
messages: [{ role: "user", content: payload }],
```

The marker is applied **unconditionally**, to every route. That's deliberate:
prompts under the model's minimum (everything except `interpret` and
`planSkeleton`) simply don't cache, and because nothing is written there is no
write premium to pay either. So a blanket marker costs nothing and removes a
per-route decision that would rot the moment a prompt grows.

Which prompts actually clear the floor today:

| Prompt | ~tokens | Model | Floor | Caches? |
|---|---:|---|---:|---|
| `interpret` | ~2,250 | Sonnet 5 | 1024 | **yes** |
| `planSkeleton` | ~700 | Opus 5 | 512 | **yes** |
| `planTweak`, `generate`, `mealSuggestion`, `scheduling`, `projectPlan`, `habit` | 110–420 | Sonnet 5 | 1024 | no (below floor) |

`interpret` is the one that matters: it is both the longest prompt and by far the
most-called route.

### Why the system prompt is not split per intent

The tempting optimisation is the opposite of caching: since `interpret` describes
all ten intents, let the user pre-select one and send a smaller prompt. **Don't.**
The arithmetic goes the wrong way, on Sonnet 5 ($2/MTok input, $0.20 cache read,
$2.50 cache write), counting system-prompt tokens only:

| | per call |
|---|---:|
| Full prompt, cache hit (~2,250 tok) | **$0.00045** |
| Full prompt, cold | $0.0045 |
| Trimmed single-intent prompt (~850 tok), uncached | **$0.0017** |

The cached fat prompt is ~4× cheaper than the trimmed thin one. Worse: an
850-token prompt is *below Sonnet 5's 1024-token floor*, so it could never cache
at all — trimming the prompt would destroy the ability to cache it. And ten
per-intent prompts means ten cold prefixes each with its own 5-minute window,
instead of one that every user keeps warm.

Related invariant: **never branch the system prompt on a request field.** Each
flag combination is a distinct prefix. Conditional system sections are a
documented silent cache-killer.

### The intent hint

So the hint exists — but it rides in the **payload**, after the breakpoint, where
it costs ~8 tokens and forks nothing:

```
USER_REQUEST: "how's my week looking"
INTENT_HINT: ask
```

`intentHint` is an optional request field on `POST /v1/schedule/interpret`, with
two coarse values (`server/lib/dto.js`, `parseIntentHint`):

- **`"ask"`** — a read-only question (`query` / `summarize`).
- **`"change"`** — mutate something (add / move / reschedule / reorganize /
  edit / delete / generate).
- **omitted** — classify freely. Unchanged behaviour, and the default.

An unrecognised value is treated as omitted rather than 400ing, like
`parseHistory`.

Two coarse modes rather than all ten intents, for two reasons. First, read-only
vs mutating is the boundary the model *actually* confuses — interpret's long
query-vs-summarize disambiguation rules exist because of it, and a user-supplied
hint settles it for free. Second, it is exactly the boundary that decides which
context blocks a payload needs.

**That gating is where the real saving is.** Payload tokens sit after the
breakpoint and bill at full price on every single call, forever — they are worth
~10× a cached prompt token. Before the hint existed, every interpret payload
carried every block, because classification is one-shot and could land anywhere:

| Block | Needed by | Shipped when hint is… |
|---|---|---|
| `SCHEDULE` (+ id map) | everything | always |
| `FREE_SLOTS` | the mutating intents only — nothing read-only can place anything | absent under `ask` |
| `STATS` | `summarize` (verified numbers) | absent under `change` |
| `RECENT_PAST` | `summarize` (history) | absent under `change` |
| `NEXT_UP` | `query` (beyond-the-week lookups) | absent under `change` |

Under `ask` the server also skips **computing** free slots, so this saves CPU as
well as tokens.

The prompt is told which blocks are missing and instructed that if the request
plainly contradicts the hint it must return **`clarify`** — not guess past the
absent blocks, and not answer the other kind anyway. `clarify` stays available
under either hint. That keeps a mis-set toggle visible instead of silently wrong.

**Callers:**
- `AIInputView` — an Auto / Ask / Change segmented picker above the input field.
  **Auto is the default**, so the common path is byte-identical to the old
  behaviour and the hint is opt-in.
- `AskCadenceIntent` (Siri) — hard-wired to `.ask`. That entry point is read-only
  by construction (it can only ever speak `readOnlyReply`), so the hint makes an
  existing contract explicit rather than adding a new one.

### Models

| Route group | Was | Now | Why |
|---|---|---|---|
| secretary (`MODEL`) | `claude-sonnet-4-6` ($3/$15) | `claude-sonnet-5` ($2/$10) | ~33% cheaper, newer, same 1024 cache floor |
| deep planner (`OPUS`) | `claude-opus-4-8` | `claude-opus-5` | same $5/$25, and **halves** the cache floor 1024 → 512, which is what makes `planSkeleton` cacheable |

This model bump was a larger, simpler win than either caching or the hint — worth
re-checking whenever a new generation ships. `budget_tokens` is removed on both
(a 400); adaptive thinking is on by default on Opus 5 but `plan/skeleton` still
sets it explicitly so the intent reads clearly. The route test asserts
`seen.model === OPUS` rather than a literal id, so a future bump doesn't fail a
test for the wrong reason.

Not adopted: the server-side refusal `fallbacks` parameter. Opus 5's safety
classifiers target research-biology and cybersecurity content; a scheduling app
will not trip them, and the parameter is a beta surface that could 400 on a route
David can't easily debug. A refusal would surface as `AI_UPSTREAM` today, which
is an honest failure.

### `max_tokens` and truncation

`MAX_TOKENS` 2048 → **4096**. A generated week of events runs past 2048, and a
truncated response is pure waste — output bills by actual tokens produced, so a
higher ceiling costs nothing when it isn't used.

Truncation is also no longer silent. `stop_reason: "max_tokens"` means the JSON
was cut mid-object, so the parse is doomed *and so is the identical retry*. It now
throws `AI_TRUNCATED` (502) immediately instead of burning a second call to arrive
at a misleading `AI_UNPARSEABLE`.

### The retry-once rule gets cheaper

`callAndParse` retries the identical call on a `ParseError`. Identical bytes means
the retry reads the entry the first call just wrote — the retry-once rule now
costs roughly a tenth of a fresh call.

---

## 4. Verifying it works

Every call logs one line (`server/lib/claude.js`, `logUsage`):

```
[claude] claude-sonnet-5 stop=end_turn in=812 cache_write=0 cache_read=2254 out=143
```

- `cache_write > 0` → this call created the entry (expect this on the first call
  after a prompt edit, a restart, or a 5-minute idle gap).
- `cache_read > 0` → it hit one. This is the steady state.
- **both 0** → not caching. Either the prefix is under the model's floor, or
  something changed it.
- `stop=max_tokens` → truncated (now also an `AI_TRUNCATED` error).

Note that `in=` is the **uncached remainder only**. Total prompt size is
`in + cache_write + cache_read`.

**Re-check these after any change to prompt assembly.** The expensive failure
mode here is silent: a regression in prompt building keeps every request
*succeeding* and just makes the bill higher. Nothing announces it. The usage log
is the only ground truth, and the realistic shape of this bug is not a bad first
implementation but a later edit — a new dynamic field in a system prompt, a
non-deterministic serialisation — that misses on every call and goes unnoticed.

This can't be asserted in the offline test suite (the fake Claude returns no
`usage`), so it is a log check, not a test.

---

## 5. When caching pays off

| Situation | Worth caching? |
|---|---|
| Any `interpret` call while anyone else is using the app | Yes — the prefix is shared, so it is usually already warm |
| A burst (asking, then refining, then confirming) | Yes — this is the best case |
| A single cold `interpret` with no traffic for 5 min either side | Pays the ~1.25× write premium on ~2,250 tokens for nothing: about +$0.001. Negligible |
| `planSkeleton` | Marginally — deep plans are rare and solitary, but it's free to leave on |
| Everything else | Below the floor; the marker is a no-op |

---

## 6. Cost control beyond caching

Still open, in rough order of value:

- **Monthly AI call allowance per user**, generous enough that normal users never
  notice. Bounds worst-case cost per user. This matters more than any token
  trimming once there is more than one user.
- Everything local (stats, templates, slot finding, notifications, `plan/week`)
  stays free — keep pushing work there rather than to the model.
- Batch API (50%) for anything not time-sensitive.
- Re-check model choice each generation; see the Models table above for why.
