/**
 * Port of CadenceTests/SchedulerServiceTests.swift against services/scheduler.js.
 * Fixed zone + fixed Monday so results are deterministic anywhere.
 */

const test = require("node:test");
const assert = require("node:assert/strict");
const { DateTime } = require("luxon");
const scheduler = require("../services/scheduler");

const ZONE = "Europe/Bucharest";
const MONDAY = DateTime.fromISO("2026-07-06T00:00:00", { zone: ZONE }); // a Monday

const at = (hour, minute = 0, daysFromNow = 0) =>
  MONDAY.plus({ days: daysFromNow }).set({ hour, minute, second: 0, millisecond: 0 });

let nextId = 1;
const makeEvent = (start, end, status = "pending") => ({
  id: `uuid-${nextId++}`, title: "Test", start, end, category: "Work", status,
});

const prefs = {
  workStartHour: 9, workEndHour: 18, bufferMinutes: 15,
  priorityCategories: [], aiLevel: "balanced", avoidScheduling: [],
  dinnerWindow: { start: "19:00", end: "21:30" }, mealGuidance: "",
};

// ── Conflict detection ──────────────────────────────────────────────────────

test("no conflict on empty schedule", () => {
  const proposal = { start: at(10), end: at(11) };
  assert.equal(scheduler.conflicts(proposal, [], 15).length, 0);
});

test("direct overlap detected", () => {
  const event = makeEvent(at(9), at(10));
  const proposal = { start: at(9, 30), end: at(10, 30) };
  assert.equal(scheduler.conflicts(proposal, [event], 15).length, 1);
});

test("buffer overlap detected", () => {
  // Event ends 10:00, proposal starts 10:05, buffer 15 min → conflict
  const event = makeEvent(at(9), at(10));
  const proposal = { start: at(10, 5), end: at(11) };
  assert.equal(scheduler.conflicts(proposal, [event], 15).length, 1);
});

test("buffer gap clear", () => {
  // Event ends 10:00, proposal starts 10:20, buffer 15 min → no conflict
  const event = makeEvent(at(9), at(10));
  const proposal = { start: at(10, 20), end: at(11) };
  assert.equal(scheduler.conflicts(proposal, [event], 15).length, 0);
});

test("missed event ignored", () => {
  const event = makeEvent(at(9), at(10), "missed");
  const proposal = { start: at(9, 30), end: at(10, 30) };
  assert.equal(scheduler.conflicts(proposal, [event], 15).length, 0);
});

// ── Free slot finder ────────────────────────────────────────────────────────

test("free slots on empty day: one 9-hour slot", () => {
  const slots = scheduler.freeSlots({
    durationMinutes: 60, windowStart: MONDAY, windowEnd: MONDAY, events: [], prefs,
  });
  assert.equal(slots.length, 1);
  assert.equal(slots[0].end.diff(slots[0].start).as("hours"), 9);
});

test("free slots around events: 09:00–10:00 | 11:15–13:00 | 14:15–18:00", () => {
  const e1 = makeEvent(at(10), at(11));
  const e2 = makeEvent(at(13), at(14));
  const slots = scheduler.freeSlots({
    durationMinutes: 30, windowStart: MONDAY, windowEnd: MONDAY, events: [e1, e2], prefs,
  });
  assert.equal(slots.length, 3);
  assert.equal(slots[1].start.toFormat("HH:mm"), "11:15"); // buffer after e1
  assert.equal(slots[2].start.toFormat("HH:mm"), "14:15"); // buffer after e2
});

test("no free slots on a fully booked day", () => {
  const event = makeEvent(at(9), at(18));
  const slots = scheduler.freeSlots({
    durationMinutes: 30, windowStart: MONDAY, windowEnd: MONDAY, events: [event], prefs,
  });
  assert.equal(slots.length, 0);
});

test("free slots span multiple days", () => {
  const slots = scheduler.freeSlots({
    durationMinutes: 60, windowStart: MONDAY, windowEnd: MONDAY.plus({ days: 1 }), events: [], prefs,
  });
  assert.equal(slots.length, 2);
});

test("avoid-scheduling block respected on matching ISO weekday", () => {
  // Monday = ISO weekday 1; block Monday lunch
  const withAvoid = { ...prefs, avoidScheduling: [{ weekdays: [1], start: "12:00", end: "13:00" }] };
  const slots = scheduler.freeSlots({
    durationMinutes: 30, windowStart: MONDAY, windowEnd: MONDAY, events: [], prefs: withAvoid,
  });
  // 09:00–12:00 and 13:00–18:00
  assert.equal(slots.length, 2);
  assert.equal(slots[0].end.toFormat("HH:mm"), "12:00");
  assert.equal(slots[1].start.toFormat("HH:mm"), "13:00");
});

// ── Compact schedule with id tokens (interpret feed) ───────────────────────

test("compact schedule shows events with tokens and free tail, maps ids", () => {
  const event = makeEvent(at(10), at(11));
  const { text, idMap } = scheduler.compactScheduleWithIds({
    events: [event], windowStart: MONDAY, windowEnd: MONDAY, prefs,
  });
  assert.match(text, /MON 10:00-11:00\[Work\]\(E1\) FREE:11:00-18:00/);
  assert.equal(idMap.E1, event.id);
});

test("compact schedule: missed event skipped, empty day fully free", () => {
  const missed = makeEvent(at(10), at(11), "missed");
  const { text, idMap } = scheduler.compactScheduleWithIds({
    events: [missed], windowStart: MONDAY, windowEnd: MONDAY, prefs,
  });
  assert.match(text, /MON FREE:09:00-18:00/);
  assert.equal(Object.keys(idMap).length, 0);
});

// ── Dinner slots ────────────────────────────────────────────────────────────

test("dinner slots: full window when free, blocked when dinner-time event exists", () => {
  const now = at(8); // Monday 08:00
  const free = scheduler.dinnerSlots({ now, days: 1, events: [], prefs });
  assert.equal(free.length, 1);
  assert.equal(free[0].start.toFormat("HH:mm"), "19:00");
  assert.equal(free[0].end.toFormat("HH:mm"), "21:30");

  const dinnerEvent = makeEvent(at(19), at(21, 30));
  const blocked = scheduler.dinnerSlots({ now, days: 1, events: [dinnerEvent], prefs });
  assert.equal(blocked.length, 0);
});
