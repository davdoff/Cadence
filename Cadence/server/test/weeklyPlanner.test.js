/**
 * Pure weeklyPlanner tests — deterministic selection (constraint walking) and
 * spread placement, no network, no model.
 */

const test = require("node:test");
const assert = require("node:assert/strict");
const { DateTime } = require("../lib/time");
const { planWeek } = require("../services/weeklyPlanner");

const zone = "Europe/Bucharest";
const dt = (iso) => DateTime.fromISO(iso, { zone });
const prefs = { bufferMinutes: 15 };
const window = { start: dt("2026-07-06T00:00:00"), end: dt("2026-07-12T23:59:00") };
// Mon–Wed, 09:00–18:00 each — plenty of room so the budget is the only limit.
const weekSlots = ["2026-07-06", "2026-07-07", "2026-07-08"].map((d) => ({
  start: dt(`${d}T09:00:00`), end: dt(`${d}T18:00:00`),
}));

const unit = (id, estimatedMinutes, archetype = "milestone", constraints = {}) => ({
  id, title: `T${id}`, objective: `objective ${id}`, estimatedMinutes, archetype,
  constraints: { afterUnit: null, repeatOf: null, minGapDays: null, notLastNDaysBeforeDeadline: null, ...constraints },
});

const minutesBetween = (a, b) => DateTime.fromISO(b).diff(DateTime.fromISO(a), "minutes").minutes;

test("planWeek places eligible units, spread across days, tagged with workUnitId + objective", () => {
  const plan = { goalType: "study", deadline: null, workUnits: [unit("W1", 120), unit("W2", 90)] };
  const { events } = planWeek({ plan, window, progress: [], weeklyHours: 10, freeSlots: weekSlots, prefs });
  assert.equal(events.length, 2);
  assert.deepEqual(events.map((e) => e.workUnitId).sort(), ["W1", "W2"]);
  assert.equal(events[0].category, "Study");
  assert.equal(events[0].objective, events[0].workUnitId === "W1" ? "objective W1" : "objective W2");
  // Round-robin spread → the two sessions land on different days.
  assert.notEqual(events[0].start.slice(0, 10), events[1].start.slice(0, 10));
});

test("planWeek caps the week at the committed budget", () => {
  const plan = { goalType: "study", deadline: null, workUnits: [unit("W1", 300), unit("W2", 300)] };
  const { events } = planWeek({ plan, window, progress: [], weeklyHours: 3, freeSlots: weekSlots, prefs });
  const total = events.reduce((acc, e) => acc + minutesBetween(e.start, e.end), 0);
  assert.equal(total, 180); // 3h budget, not the 600 of needed work
  assert.ok(events.every((e) => e.workUnitId === "W1")); // filled in skeleton order
});

test("planWeek gates a unit behind afterUnit until the dependency is exhausted", () => {
  const plan = { goalType: "project", deadline: null,
    workUnits: [unit("W1", 120), unit("W2", 60, "milestone", { afterUnit: "W1" })] };

  const before = planWeek({ plan, window, progress: [], weeklyHours: 10, freeSlots: weekSlots, prefs });
  assert.deepEqual(before.events.map((e) => e.workUnitId), ["W1"]); // W2 blocked
  assert.equal(before.events[0].category, "Work"); // project → Work

  const after = planWeek({ plan, window, weeklyHours: 10, freeSlots: weekSlots, prefs,
    progress: [{ workUnitId: "W1", scheduledMinutes: 120 }] });
  assert.deepEqual(after.events.map((e) => e.workUnitId), ["W2"]); // W1 done → W2 runs
});

test("planWeek blocks new material in the deadline zone but still runs recall passes", () => {
  const deadline = dt("2026-07-20T23:59:00");
  const zoneWindow = { start: dt("2026-07-18T00:00:00"), end: dt("2026-07-20T23:59:00") };
  const zoneSlots = ["2026-07-18", "2026-07-19"].map((d) => ({ start: dt(`${d}T09:00:00`), end: dt(`${d}T18:00:00`) }));
  const plan = { goalType: "study", deadline, workUnits: [
    unit("W1", 120, "milestone", { notLastNDaysBeforeDeadline: 3 }),      // new material
    unit("W2", 60, "repetition", { repeatOf: "W1", minGapDays: 3 }),       // recall pass
  ] };
  // W1 half-done and last touched 8 days ago, so the recall gap has elapsed.
  const progress = [{ workUnitId: "W1", scheduledMinutes: 60, lastSessionDate: dt("2026-07-10T09:00:00") }];
  const { events } = planWeek({ plan, window: zoneWindow, progress, weeklyHours: 10, freeSlots: zoneSlots, prefs });
  assert.deepEqual(events.map((e) => e.workUnitId), ["W2"]); // W1 (new material) blocked, W2 (recall) runs
});

test("planWeek withholds a recall pass until minGapDays has elapsed", () => {
  const plan = { goalType: "study", deadline: null, workUnits: [
    unit("W1", 120), unit("W2", 60, "repetition", { repeatOf: "W1", minGapDays: 5 }),
  ] };
  // W1 scheduled just 1 day before the window — the 5-day recall gap hasn't passed.
  const progress = [{ workUnitId: "W1", scheduledMinutes: 120, lastSessionDate: dt("2026-07-05T09:00:00") }];
  const { events } = planWeek({ plan, window, progress, weeklyHours: 10, freeSlots: weekSlots, prefs });
  assert.equal(events.length, 0); // W1 exhausted, W2 not yet due
});
