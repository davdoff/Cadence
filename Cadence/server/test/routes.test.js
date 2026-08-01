/**
 * Route-level tests: full request→validate→prompt→parse→respond pipeline with
 * an injected fake Claude (zero network), plus the error envelope contract.
 */

const test = require("node:test");
const assert = require("node:assert/strict");
const { createApp } = require("../app");
const { parseHistory, MAX_HISTORY_TURNS } = require("../lib/dto");

/** Boot the app on an ephemeral port; returns a JSON-speaking client. */
function boot(fakeClaude) {
  const app = createApp({ callClaude: fakeClaude });
  const server = app.listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  const post = async (path, body) => {
    const res = await fetch(base + path, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    return { status: res.status, body: await res.json() };
  };
  return { post, base, close: () => server.close() };
}

const BASE_REQ = {
  now: "2026-07-06T08:00:00+03:00",
  timezone: "Europe/Bucharest",
  prefs: { workStartHour: 9, workEndHour: 18, bufferMinutes: 15 },
  events: [{
    id: "uuid-gym", title: "Gym", category: "Health", status: "pending",
    start: "2026-07-06T10:00:00+03:00", end: "2026-07-06T11:00:00+03:00",
  }],
};

test("GET /v1/health", async () => {
  const { base, close } = boot(async () => "{}");
  try {
    const res = await fetch(`${base}/v1/health`);
    assert.deepEqual(await res.json(), { status: "ok", version: "1" });
  } finally { close(); }
});

test("POST /v1/schedule/add returns a typed decision; prompt contains free slots", async () => {
  let seen;
  const fake = async ({ system, payload }) => {
    seen = { system, payload };
    return JSON.stringify({
      action: "add",
      event: { title: "Taxes", start: "2026-07-07T09:00:00+03:00", end: "2026-07-07T11:00:00+03:00", category: "Admin" },
      conflict_reason: null, alternatives: [],
    });
  };
  const { post, close } = boot(fake);
  try {
    const { status, body } = await post("/v1/schedule/add", { ...BASE_REQ, description: "2h for taxes this week" });
    assert.equal(status, 200);
    assert.equal(body.action, "add");
    assert.equal(body.event.title, "Taxes");
    // Server computed slots + built the prompt itself:
    assert.match(seen.payload, /NOW: 2026-07-06T08:00:00\+03:00/);
    assert.match(seen.payload, /FREE_SLOTS:/);
    assert.match(seen.payload, /NEW_EVENT: "2h for taxes this week"/);
    assert.match(seen.system, /scheduling assistant/);
  } finally { close(); }
});

test("POST /v1/schedule/interpret maps token ids back to UUIDs", async () => {
  const fake = async ({ payload }) => {
    // The model sees E-tokens in the schedule, never UUIDs
    assert.match(payload, /\(E1\)/);
    assert.doesNotMatch(payload, /uuid-gym/);
    return JSON.stringify({
      intent: "move",
      interpretation: "Moving 'Gym' to Tue 08:00–09:00",
      payload: { targetEventId: "E1", newStart: "2026-07-07T08:00:00+03:00", newEnd: "2026-07-07T09:00:00+03:00", alternatives: [] },
    });
  };
  const { post, close } = boot(fake);
  try {
    const { status, body } = await post("/v1/schedule/interpret", { ...BASE_REQ, text: "move my gym to tomorrow morning" });
    assert.equal(status, 200);
    assert.equal(body.intent, "move");
    assert.equal(body.targetEventId, "uuid-gym"); // mapped back
    assert.equal(body.interpretation, "Moving 'Gym' to Tue 08:00–09:00");
  } finally { close(); }
});

test("POST /v1/schedule/interpret threads CONVERSATION history; USER_REQUEST is the latest", async () => {
  let seen;
  const fake = async ({ payload }) => {
    seen = payload;
    return JSON.stringify({ intent: "query", interpretation: "Your next swim", payload: { answer: "No swims are scheduled." } });
  };
  const { post, close } = boot(fake);
  try {
    const history = [
      { user: "when's my next gym?", assistant: "Your next gym is Tuesday at 08:00." },
      { user: "", assistant: "dropped — empty user" }, // non-conforming, filtered out
    ];
    const { status, body } = await post("/v1/schedule/interpret", { ...BASE_REQ, text: "what about swimming?", history });
    assert.equal(status, 200);
    assert.equal(body.intent, "query");
    // History rendered oldest-first, as USER/YOU, before the schedule:
    assert.match(seen, /CONVERSATION \(earlier turns/);
    assert.match(seen, /USER: when's my next gym\?/);
    assert.match(seen, /YOU: Your next gym is Tuesday at 08:00\./);
    assert.ok(seen.indexOf("CONVERSATION") < seen.indexOf("SCHEDULE"));
    // The empty-user turn was dropped, and the latest message is USER_REQUEST:
    assert.doesNotMatch(seen, /dropped — empty user/);
    assert.match(seen, /USER_REQUEST: "what about swimming\?"/);
  } finally { close(); }
});

test("POST /v1/schedule/interpret without history renders no CONVERSATION block", async () => {
  let seen;
  const fake = async ({ payload }) => {
    seen = payload;
    return JSON.stringify({ intent: "query", interpretation: "x", payload: { answer: "a" } });
  };
  const { post, close } = boot(fake);
  try {
    await post("/v1/schedule/interpret", { ...BASE_REQ, text: "when's my next gym?" });
    assert.doesNotMatch(seen, /CONVERSATION/);
    // garbage history is ignored, not a 400:
    const { status } = await post("/v1/schedule/interpret", { ...BASE_REQ, text: "hi", history: "not-an-array" });
    assert.equal(status, 200);
    assert.doesNotMatch(seen, /CONVERSATION/);
  } finally { close(); }
});

test("parseHistory: filters non-conforming entries and caps to MAX_HISTORY_TURNS", () => {
  assert.deepEqual(parseHistory("nope"), []);
  assert.deepEqual(parseHistory([{ user: " ", assistant: "x" }, { user: "x", assistant: "" }]), []);
  const many = Array.from({ length: MAX_HISTORY_TURNS + 4 }, (_, i) => ({ user: `u${i}`, assistant: `a${i}` }));
  const out = parseHistory(many);
  assert.equal(out.length, MAX_HISTORY_TURNS);
  assert.equal(out[out.length - 1].user, `u${many.length - 1}`); // keeps the most recent
});

test("POST /v1/schedule/generate returns events; past part of period is clipped", async () => {
  let seen;
  const fake = async ({ system, payload }) => {
    seen = { system, payload };
    return JSON.stringify({
      events: [
        { title: "Workout", start: "2026-07-06T09:00:00+03:00", end: "2026-07-06T10:00:00+03:00", category: "Health" },
        { title: "Workout", start: "2026-07-07T09:00:00+03:00", end: "2026-07-07T10:00:00+03:00", category: "Health" },
      ],
    });
  };
  const { post, close } = boot(fake);
  try {
    const { status, body } = await post("/v1/schedule/generate", {
      ...BASE_REQ,
      // Starts yesterday (Sunday) — the server must not offer past slots.
      period: { start: "2026-07-05T00:00:00+03:00", end: "2026-07-08T23:59:00+03:00" },
      goals: "three workouts",
    });
    assert.equal(status, 200);
    assert.equal(body.events.length, 2);
    assert.equal(body.events[0].title, "Workout");
    assert.match(seen.system, /fills a period/);
    assert.match(seen.payload, /PERIOD: 2026-07-05 to 2026-07-08/);
    assert.match(seen.payload, /GOALS: "three workouts"/);
    assert.match(seen.payload, /AILevel=balanced/);
    assert.doesNotMatch(seen.payload, /SUN/); // no slots from the past Sunday
  } finally { close(); }
});

test("POST /v1/schedule/generate with an entirely past period → 400", async () => {
  const { post, close } = boot(async () => "{}");
  try {
    const { status, body } = await post("/v1/schedule/generate", {
      ...BASE_REQ,
      period: { start: "2026-07-01T00:00:00+03:00", end: "2026-07-02T00:00:00+03:00" },
      goals: "anything",
    });
    assert.equal(status, 400);
    assert.equal(body.error.code, "BAD_REQUEST");
  } finally { close(); }
});

test("missing required field → 400 BAD_REQUEST envelope", async () => {
  const { post, close } = boot(async () => "{}");
  try {
    const { status, body } = await post("/v1/schedule/add", { ...BASE_REQ }); // no description
    assert.equal(status, 400);
    assert.equal(body.error.code, "BAD_REQUEST");

    const noTz = await post("/v1/schedule/interpret", { now: BASE_REQ.now, text: "hi" });
    assert.equal(noTz.status, 400);
    assert.equal(noTz.body.error.code, "BAD_REQUEST");
  } finally { close(); }
});

test("unparseable model output twice → 502 AI_UNPARSEABLE envelope (after retry)", async () => {
  let calls = 0;
  const fake = async () => { calls++; return "I would love to help but here is prose"; };
  const { post, close } = boot(fake);
  try {
    const { status, body } = await post("/v1/schedule/add", { ...BASE_REQ, description: "x" });
    assert.equal(status, 502);
    assert.equal(body.error.code, "AI_UNPARSEABLE");
    assert.equal(calls, 2); // retry-once happened
  } finally { close(); }
});

test("POST /v1/meal/suggestions with no free dinner slots skips the AI call", async () => {
  let called = false;
  const fake = async () => { called = true; return "{}"; };
  const { post, close } = boot(fake);
  try {
    // Block the dinner window on all 7 days the server can look at
    const blockers = Array.from({ length: 7 }, (_, i) => ({
      id: `uuid-shift-${i}`, title: "Late shift", category: "Work", status: "pending",
      start: `2026-07-${String(6 + i).padStart(2, "0")}T18:00:00+03:00`,
      end: `2026-07-${String(6 + i).padStart(2, "0")}T22:00:00+03:00`,
    }));
    const { status, body } = await post("/v1/meal/suggestions", {
      ...BASE_REQ, days: 7, events: blockers, existingMeals: [{ name: "Pasta", prepTimeMinutes: 30 }],
    });
    assert.equal(status, 200);
    assert.deepEqual(body.suggestions, []);
    assert.equal(called, false); // no slots → no Claude call
  } finally { close(); }
});

test("POST /v1/meal/suggestions defaults to today only (days=1)", async () => {
  let called = false;
  const fake = async () => { called = true; return "{}"; };
  const { post, close } = boot(fake);
  try {
    // Only today's dinner window is blocked; tomorrow is free — but with the
    // default days=1 the server must not look past today.
    const todayBlocker = {
      id: "uuid-shift-today", title: "Late shift", category: "Work", status: "pending",
      start: "2026-07-06T18:00:00+03:00", end: "2026-07-06T22:00:00+03:00",
    };
    const { status, body } = await post("/v1/meal/suggestions", {
      ...BASE_REQ, events: [todayBlocker], existingMeals: [{ name: "Pasta", prepTimeMinutes: 30 }],
    });
    assert.equal(status, 200);
    assert.deepEqual(body.suggestions, []);
    assert.equal(called, false);
  } finally { close(); }
});

test("POST /v1/plan/skeleton returns plan + cushion; prompt carries deadline/weeks, call uses Opus+thinking", async () => {
  let seen;
  const fake = async (opts) => {
    seen = opts;
    return JSON.stringify({
      title: "Signals & Systems exam prep",
      workUnits: [
        { id: "W1", title: "Ch.1–3 first pass", objective: "Summarise ch.1–3; solve the worked examples", estimatedMinutes: 240, archetype: "repetition", constraints: { afterUnit: null, repeatOf: null, minGapDays: null, notLastNDaysBeforeDeadline: 3 } },
        { id: "W2", title: "Ch.1–3 recall", objective: "Redo worked examples ch.1–3 without notes; verify", estimatedMinutes: 120, archetype: "repetition", constraints: { afterUnit: null, repeatOf: "W1", minGapDays: 3, notLastNDaysBeforeDeadline: null } },
      ],
    });
  };
  const { post, close } = boot(fake);
  try {
    const { status, body } = await post("/v1/plan/skeleton", {
      now: BASE_REQ.now, timezone: BASE_REQ.timezone,
      goal: "Pass the Signals & Systems exam", goalType: "study",
      deadline: "2026-08-05", weeklyHours: 10,
    });
    assert.equal(status, 200);
    assert.equal(body.plan.title, "Signals & Systems exam prep");
    assert.equal(body.plan.goalType, "study");
    assert.equal(body.plan.deadline, "2026-08-05");
    assert.equal(body.plan.workUnits.length, 2);
    assert.equal(body.plan.workUnits[1].constraints.repeatOf, "W1");
    // Cushion: needed = 240 + 120 = 360; weeks from 2026-07-06 → 2026-08-05 (end
    // of day) is ceil(30.6/7) = 5; available = 10h × 60 × 5 = 3000.
    assert.equal(body.capacity.neededMinutes, 360);
    assert.equal(body.capacity.availableMinutes, 3000);
    assert.equal(body.capacity.cushionMinutes, 2640);
    // The deep planner uses Opus + adaptive thinking + high effort, and the
    // prompt gives the model the deadline and the weeks it must budget across.
    assert.equal(seen.model, "claude-opus-4-8");
    assert.equal(seen.thinking, true);
    assert.equal(seen.effort, "high");
    assert.match(seen.payload, /DEADLINE: 2026-08-05/);
    assert.match(seen.payload, /WEEKLY_HOURS: 10/);
    assert.match(seen.payload, /WEEKS_AVAILABLE: 5/);
    assert.match(seen.system, /deep planning assistant/);
  } finally { close(); }
});

test("POST /v1/plan/skeleton without a deadline uses the default horizon", async () => {
  let seen;
  const fake = async (opts) => {
    seen = opts;
    return JSON.stringify({
      title: "Learn Spanish",
      workUnits: [{ id: "W1", title: "A1 basics", objective: "Hold a 5-line self-intro from memory", estimatedMinutes: 600, archetype: "repetition", constraints: { afterUnit: null, repeatOf: null, minGapDays: null, notLastNDaysBeforeDeadline: null } }],
    });
  };
  const { post, close } = boot(fake);
  try {
    const { status, body } = await post("/v1/plan/skeleton", {
      now: BASE_REQ.now, timezone: BASE_REQ.timezone, goal: "Learn Spanish", goalType: "project", weeklyHours: 3,
    });
    assert.equal(status, 200);
    assert.equal(body.plan.deadline, null);
    assert.match(seen.payload, /DEADLINE: none/);
    assert.match(seen.payload, /WEEKS_AVAILABLE: 8/);      // default horizon
    assert.equal(body.capacity.availableMinutes, 1440);   // 3h × 60 × 8
    assert.equal(body.capacity.cushionMinutes, 840);      // 1440 − 600
  } finally { close(); }
});

test("POST /v1/plan/skeleton rejects a past deadline and missing goal", async () => {
  const { post, close } = boot(async () => "{}");
  try {
    const past = await post("/v1/plan/skeleton", {
      now: BASE_REQ.now, timezone: BASE_REQ.timezone, goal: "x", deadline: "2026-07-01", weeklyHours: 5,
    });
    assert.equal(past.status, 400);
    assert.equal(past.body.error.code, "BAD_REQUEST");

    const noGoal = await post("/v1/plan/skeleton", { now: BASE_REQ.now, timezone: BASE_REQ.timezone, weeklyHours: 5 });
    assert.equal(noGoal.status, 400);
  } finally { close(); }
});

test("POST /v1/plan/skeleton: an invalid archetype twice → 502 AI_UNPARSEABLE", async () => {
  let calls = 0;
  const fake = async () => {
    calls++;
    return JSON.stringify({ title: "x", workUnits: [{ id: "W1", title: "t", objective: "o", estimatedMinutes: 60, archetype: "bogus", constraints: {} }] });
  };
  const { post, close } = boot(fake);
  try {
    const { status, body } = await post("/v1/plan/skeleton", {
      now: BASE_REQ.now, timezone: BASE_REQ.timezone, goal: "x", deadline: "2026-08-05", weeklyHours: 5,
    });
    assert.equal(status, 502);
    assert.equal(body.error.code, "AI_UNPARSEABLE");
    assert.equal(calls, 2); // retry-once fired
  } finally { close(); }
});

test("POST /v1/plan/week places due units into free slots without calling Claude", async () => {
  let called = false;
  const fake = async () => { called = true; return "{}"; };
  const { post, close } = boot(fake);
  try {
    const { status, body } = await post("/v1/plan/week", {
      now: "2026-07-06T08:00:00+03:00", timezone: "Europe/Bucharest",
      prefs: { workStartHour: 9, workEndHour: 18, bufferMinutes: 15 },
      events: [],
      weeklyHours: 10,
      plan: {
        goalType: "study", deadline: "2026-08-05",
        workUnits: [
          { id: "W1", title: "Ch.1–3", objective: "Summarise ch.1–3", estimatedMinutes: 120, archetype: "repetition",
            constraints: { afterUnit: null, repeatOf: null, minGapDays: null, notLastNDaysBeforeDeadline: 3 } },
          { id: "W2", title: "Ch.4–6", objective: "Summarise ch.4–6", estimatedMinutes: 90, archetype: "repetition",
            constraints: { afterUnit: "W1", repeatOf: null, minGapDays: null, notLastNDaysBeforeDeadline: 3 } },
        ],
      },
      window: { start: "2026-07-06T00:00:00+03:00", end: "2026-07-12T23:59:00+03:00" },
      progress: [],
    });
    assert.equal(status, 200);
    assert.equal(called, false); // deterministic — no model
    // W2 is gated behind W1 (not exhausted), so only W1 places this week.
    assert.deepEqual(body.events.map((e) => e.workUnitId), ["W1"]);
    assert.equal(body.events[0].objective, "Summarise ch.1–3");
    assert.equal(body.events[0].category, "Study");
    assert.match(body.events[0].start, /^2026-07-0/);
  } finally { close(); }
});

test("POST /v1/plan/week rejects a missing plan / empty window → 400", async () => {
  const { post, close } = boot(async () => "{}");
  try {
    const noPlan = await post("/v1/plan/week", {
      now: "2026-07-06T08:00:00+03:00", timezone: "Europe/Bucharest",
      prefs: { workStartHour: 9, workEndHour: 18, bufferMinutes: 15 }, events: [],
      window: { start: "2026-07-06T00:00:00+03:00", end: "2026-07-12T23:59:00+03:00" },
    });
    assert.equal(noPlan.status, 400);
    assert.equal(noPlan.body.error.code, "BAD_REQUEST");
  } finally { close(); }
});

test("POST /v1/habits/analysis returns trimmed plain-text insight", async () => {
  const fake = async ({ payload }) => {
    assert.match(payload, /HABITS_WEEK: Reading=5\(↑ from 3\)/);
    return "  Nice work on Reading this week.  ";
  };
  const { post, close } = boot(fake);
  try {
    const { status, body } = await post("/v1/habits/analysis", {
      habits: [{ name: "Reading", weekTotal: 5, priorWeekTotal: 3 }],
    });
    assert.equal(status, 200);
    assert.equal(body.insight, "Nice work on Reading this week.");
  } finally { close(); }
});
