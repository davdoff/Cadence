/**
 * Route-level tests: full request→validate→prompt→parse→respond pipeline with
 * an injected fake Claude (zero network), plus the error envelope contract.
 */

const test = require("node:test");
const assert = require("node:assert/strict");
const { createApp } = require("../app");

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
    // Block the dinner window on all 7 days the server looks at
    const blockers = Array.from({ length: 7 }, (_, i) => ({
      id: `uuid-shift-${i}`, title: "Late shift", category: "Work", status: "pending",
      start: `2026-07-${String(6 + i).padStart(2, "0")}T18:00:00+03:00`,
      end: `2026-07-${String(6 + i).padStart(2, "0")}T22:00:00+03:00`,
    }));
    const { status, body } = await post("/v1/meal/suggestions", {
      ...BASE_REQ, events: blockers, existingMeals: [{ name: "Pasta", prepTimeMinutes: 30 }],
    });
    assert.equal(status, 200);
    assert.deepEqual(body.suggestions, []);
    assert.equal(called, false); // no slots → no Claude call
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
