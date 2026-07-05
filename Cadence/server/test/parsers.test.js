/**
 * Parser tests — model output → typed contract shapes, mirroring the parsing
 * rules that used to live in AIService.swift, plus the new interpret union.
 */

const test = require("node:test");
const assert = require("node:assert/strict");
const { DateTime } = require("luxon");
const parsers = require("../services/parsers");
const { ParseError } = require("../lib/errors");
const { callAndParse } = require("../lib/claude");

const ZONE = "Europe/Bucharest";
const NOW = DateTime.fromISO("2026-07-06T08:00:00", { zone: ZONE }); // Monday
const prefs = { dinnerWindow: { start: "19:00", end: "21:30" } };

// ── SchedulingDecision ──────────────────────────────────────────────────────

test("decision: add parses and normalizes", () => {
  const out = parsers.parseDecision(JSON.stringify({
    action: "add",
    event: { title: "Taxes", start: "2026-07-07T10:00:00+03:00", end: "2026-07-07T11:00:00+03:00", category: "Admin" },
    conflict_reason: null,
    alternatives: [],
  }), { zone: ZONE });
  assert.equal(out.action, "add");
  assert.equal(out.event.title, "Taxes");
  assert.equal(out.event.start, "2026-07-07T10:00:00+03:00");
  assert.equal(out.conflictReason, null);
});

test("decision: conflict carries reason and alternatives", () => {
  const out = parsers.parseDecision(JSON.stringify({
    action: "conflict", event: null, conflict_reason: "Gym at that time",
    alternatives: [{ start: "2026-07-07T12:00:00+03:00", end: "2026-07-07T13:00:00+03:00" }],
  }), { zone: ZONE });
  assert.equal(out.action, "conflict");
  assert.equal(out.conflictReason, "Gym at that time");
  assert.equal(out.alternatives.length, 1);
});

test("decision: unknown action / bad date / non-JSON all throw ParseError", () => {
  assert.throws(() => parsers.parseDecision('{"action":"explode"}', { zone: ZONE }), ParseError);
  assert.throws(() => parsers.parseDecision(JSON.stringify({
    action: "add", event: { title: "X", start: "not-a-date", end: "also-no", category: "Y" },
  }), { zone: ZONE }), ParseError);
  assert.throws(() => parsers.parseDecision("I think you should…", { zone: ZONE }), ParseError);
});

// ── Interpret union ─────────────────────────────────────────────────────────

const idMap = { E1: "uuid-gym", E2: "uuid-dentist" };

test("interpret: move maps E-token to real UUID", () => {
  const out = parsers.parseInterpret(JSON.stringify({
    intent: "move",
    interpretation: "Moving 'Gym' to Tue 08:00–09:00",
    payload: { targetEventId: "E1", newStart: "2026-07-07T08:00:00+03:00", newEnd: "2026-07-07T09:00:00+03:00", alternatives: [] },
  }), { zone: ZONE, idMap });
  assert.equal(out.intent, "move");
  assert.equal(out.targetEventId, "uuid-gym");
  assert.equal(out.newStart, "2026-07-07T08:00:00+03:00");
});

test("interpret: unknown E-token throws ParseError (never invent ids)", () => {
  assert.throws(() => parsers.parseInterpret(JSON.stringify({
    intent: "move", interpretation: "Moving something",
    payload: { targetEventId: "E9", newStart: "2026-07-07T08:00:00+03:00", newEnd: "2026-07-07T09:00:00+03:00" },
  }), { zone: ZONE, idMap }), ParseError);
});

test("interpret: clarify passes question and options through", () => {
  const out = parsers.parseInterpret(JSON.stringify({
    intent: "clarify", interpretation: "Which dentist appointment?",
    payload: { question: "You have two 'dentist' events — which one?", options: ["Tue 10:00", "Fri 14:00"] },
  }), { zone: ZONE, idMap });
  assert.equal(out.intent, "clarify");
  assert.equal(out.options.length, 2);
});

test("interpret: reorganize maps moves and displaced; missing interpretation throws", () => {
  const out = parsers.parseInterpret(JSON.stringify({
    intent: "reorganize", interpretation: "Freeing up your afternoon",
    payload: {
      moves: [{ targetEventId: "E2", newStart: "2026-07-07T15:00:00+03:00", newEnd: "2026-07-07T16:00:00+03:00" }],
      displaced: ["E1"],
    },
  }), { zone: ZONE, idMap });
  assert.equal(out.moves[0].targetEventId, "uuid-dentist");
  assert.deepEqual(out.displaced, ["uuid-gym"]);

  assert.throws(() => parsers.parseInterpret(JSON.stringify({
    intent: "add", payload: { event: null, alternatives: [] },
  }), { zone: ZONE, idMap }), ParseError);
});

// ── Meal suggestions ────────────────────────────────────────────────────────

test("meals: resolves DAY HH:MM within the week and clamps to dinner window end", () => {
  const out = parsers.parseMealSuggestions(JSON.stringify({
    meals: [
      // 90 min prep starting 20:30 would end 22:00 → clamped to 21:30
      { name: "Paella", prepTimeMinutes: 90, tags: ["spanish"], scheduledSlot: "WED 20:30" },
      { name: "Ramen", prepTimeMinutes: 45, tags: ["quick"], scheduledSlot: "TUE 19:00" },
      { name: "Broken", prepTimeMinutes: 30, tags: [], scheduledSlot: "someday" }, // dropped, not fatal
    ],
  }), { zone: ZONE, now: NOW, prefs });
  assert.equal(out.suggestions.length, 2);
  const paella = out.suggestions[0];
  assert.match(paella.start, /2026-07-08T20:30:00/); // Wednesday of NOW's week
  assert.match(paella.end, /21:30:00/);              // clamped
});

test("meals: all-unparseable batch throws ParseError", () => {
  assert.throws(() => parsers.parseMealSuggestions(JSON.stringify({
    meals: [{ name: "X", prepTimeMinutes: 30, tags: [], scheduledSlot: "??" }],
  }), { zone: ZONE, now: NOW, prefs }), ParseError);
});

// ── Project plan ────────────────────────────────────────────────────────────

test("project plan: valid phases parse, bad targetDate becomes null", () => {
  const out = parsers.parseProjectPlan(JSON.stringify({
    phases: [
      { title: "Research", subtasks: ["read docs", "compare options"], targetDate: "2026-08-01" },
      { title: "Build", subtasks: ["mvp"], targetDate: "soon" },
    ],
  }));
  assert.equal(out.phases.length, 2);
  assert.equal(out.phases[0].targetDate, "2026-08-01");
  assert.equal(out.phases[1].targetDate, null);
});

// ── Retry-once rule ─────────────────────────────────────────────────────────

test("callAndParse: retries once on ParseError, succeeds on second output", async () => {
  let calls = 0;
  const flaky = async () => (++calls === 1 ? "garbage" : '{"action":"suggest_alternative","alternatives":[]}');
  const out = await callAndParse(flaky, { system: "s", payload: "p" },
    (text) => parsers.parseDecision(text, { zone: ZONE }));
  assert.equal(calls, 2);
  assert.equal(out.action, "suggest_alternative");
});

test("callAndParse: two bad outputs propagate ParseError", async () => {
  const alwaysBad = async () => "garbage";
  await assert.rejects(
    callAndParse(alwaysBad, { system: "s", payload: "p" },
      (text) => parsers.parseDecision(text, { zone: ZONE })),
    ParseError
  );
});
