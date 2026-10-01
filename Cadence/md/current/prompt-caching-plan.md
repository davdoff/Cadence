# Prompt Caching Plan — Cadence AI Calls

## Goal
Cut the cost of repeat AI calls (especially bursts like refining a week plan) without losing per-user personalisation.

## How caching works (the short version)
- Caching works on **prefixes**. Everything *before* a `cache_control` breakpoint is stored after the first call; everything *after* it is processed fresh every time.
- You still send the full prompt every call. The provider recognises the identical prefix and skips reprocessing it, so those tokens are billed at a much lower rate (cache reads are roughly a tenth of normal input).
- **Opt-in only.** Nothing is cached unless you mark a breakpoint.
- **Lifetime:** about 5 minutes by default, refreshed every time the cache is hit.
- **Cache writes cost a bit more** than normal input. A lone call that never gets a follow-up within the window pays slightly extra for nothing.
- There is a **minimum prefix length** below which caching doesn't kick in — check the current limit for the model in the docs.
- The cache only matches if the prefix is **byte-for-byte identical**. Any change (even whitespace, or a reordered preference) is a miss.

## Prompt structure
Order matters — most stable first, most volatile last.

```
1. Static system prompt     (role, output schema, constraints)  — identical for ALL users
   ── breakpoint 1 ──
2. User preference block    (buffer, work hours, avoid times…)  — stable per user
   ── breakpoint 2 ──
3. Free slots / schedule    — changes every call, NOT cached
4. The user's request       — changes every call, NOT cached
```

- Breakpoint 1 lets the shared system prompt be reused across users.
- Breakpoint 2 gives each user their own cached prefix while they're actively using the app.
- **Events and free slots never go in the cached part** — the schedule changes too often to ever hit.

## Proxy implementation (Node/Express)
The system prompt becomes an array of blocks, each breakpoint marked with `cache_control`:

```js
const body = {
  model: MODEL,
  max_tokens: maxTokensForIntent,
  system: [
    { type: "text", text: systemPrompt,
      cache_control: { type: "ephemeral" } },        // breakpoint 1
    { type: "text", text: compactPreferenceString,
      cache_control: { type: "ephemeral" } }         // breakpoint 2
  ],
  messages: [
    { role: "user", content: userPayload }           // slots + request, uncached
  ]
};
```

App side: send `compactPreferenceString` as its own field instead of concatenating it into `userPayload`, so the proxy can place it before the breakpoint.

**Keep `compactPreferenceString` deterministic** — same field order, same formatting every time. It's already regenerated only when preferences change, which is exactly what caching needs.

## Verifying it works
Log the `usage` object from each response:
- `cache_creation_input_tokens` > 0 → this call wrote the cache
- `cache_read_input_tokens` > 0 → this call hit the cache
- both 0 → no caching (prefix too short, or prefix changed)

## When it pays off
| Situation | Worth caching? |
|---|---|
| Generating / refining a week plan (several calls in a few minutes) | Yes — big payloads, repeated |
| Quick one-off add/move | Marginal — breakpoint 1 may still hit if other users are active |
| Weekly habit analysis (once a week) | No real benefit |

## Related: the "generate week" failures
Before tuning caching, fix the silent failures:
- Raise `max_tokens` for the generate intent — a week of events is easily a couple of thousand output tokens.
- Log `stop_reason`. `max_tokens` means the JSON got cut off; `end_turn` means it finished.
- Check the Express/Node socket timeout for long generations.
- Prompt: ask for terse events — slot data only, no explanation fields.

## Cost control (beyond caching)
- Monthly AI call allowance per user, generous enough that normal users never notice. Bounds worst-case cost per user.
- Everything local (stats, templates, slot finding, notifications) stays free.
- Batch API for anything not time-sensitive.
