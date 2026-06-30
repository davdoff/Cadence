# Cadence AI Proxy Server

## What this project is

A small local Node/Express server that sits between the Cadence iOS app
(see CADENCE_README.md for the full app spec) and the Anthropic API. The
iOS app never talks to Anthropic directly and never holds an API key —
it sends compact context strings to this proxy, and the proxy forwards
them to Claude and returns the response.

This server is for **dev/device testing only** — running on the
developer's Mac, reached either via local wifi IP or an ngrok tunnel,
and started/stopped via Claude Code (including Remote Control from the
Claude mobile app).

---

## Tech stack

- Node.js + Express
- `@anthropic-ai/sdk` for the Anthropic API call
- `dotenv` for loading `ANTHROPIC_API_KEY` from a local `.env` file
- No database, no auth — this is a single-developer testing proxy, not
  production infrastructure

---

## File structure to build

```
/server.js          # Express app, all routes
/package.json
/.env                # ANTHROPIC_API_KEY=sk-ant-... (never commit this)
/.gitignore          # must include .env and node_modules
```

---

## Endpoints to implement

One POST endpoint per `SchedulingIntent` case from the iOS app. Each
receives a plain-text context payload (already built client-side by
`SchedulingContextBuilder` — never send it raw event objects, never
build prompts server-side beyond wrapping the system prompt).

| Route | Maps to SchedulingIntent | Notes |
|---|---|---|
| `POST /api/schedule/add` | `addToFreeSlot` | free slots + new event description |
| `POST /api/schedule/move` | `moveEvent` | anchor event + neighbours + free slots + reason |
| `POST /api/schedule/reschedule` | `rescheduleMissed` | missed event + missed_count + free slots |
| `POST /api/habit/analysis` | `habitWeeklyAnalysis` | week's habit counts + trends (user-triggered only) |
| `POST /api/meal/suggestion` | mealSuggestion (weekly) | existing meals + free dinner slots |
| `POST /api/project/plan` | `deepProjectPlan` | intake form fields, expects phased JSON back |

Every route follows the same shape:

```js
app.post("/api/<route>", async (req, res) => {
  try {
    const { systemPrompt, userPayload } = req.body;
    const response = await anthropic.messages.create({
      model: "claude-sonnet-4-6",
      max_tokens: 1024,
      system: systemPrompt,
      messages: [{ role: "user", content: userPayload }],
    });
    res.status(200).json(response);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "AI request failed" });
  }
});
```

Add a `GET /health` route that just returns `{ status: "ok" }` — useful
for confirming the server is up from a phone browser without spending
an API call.

---

## Rules

- Never log the contents of `ANTHROPIC_API_KEY`.
- Never commit `.env`.
- Never add request logging that writes full user payloads to disk —
  this is meant to stay as lean as the token-efficiency principles in
  CADENCE_README.md.
- Keep `server.js` as a single file unless it grows past ~150 lines —
  this is a throwaway dev proxy, not the production architecture.

---

## How to start / stop the server (for Claude Code itself)

When asked to **start the server**:
1. Check if something is already listening on port 3000
   (`lsof -i :3000`). If so, report that it's already running instead
   of starting a duplicate.
2. Otherwise run `node server.js &` (or `npm start` if a start script
   exists) and confirm the port is listening before reporting success.

When asked to **stop the server**:
1. Find the process on port 3000 (`lsof -ti :3000`).
2. Kill it (`kill <pid>`).
3. Confirm the port is free.

When asked to **test the server**, use `curl` against `localhost:3000`
(or the active ngrok URL if one is running) with a small sample
payload, and report back the actual response text — don't just report
HTTP status codes.

---

## Out of scope for this proxy

- No production deployment config here (that's a separate decision —
  see CADENCE_README.md notes on Vercel vs Oracle Cloud)
- No streaming responses
- No multi-turn conversation state — each request is stateless,
  matching the app's current SchedulingIntent design
