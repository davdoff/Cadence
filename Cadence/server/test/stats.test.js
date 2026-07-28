/**
 * Stats tests — the deterministic analytics that ground the summarize intent.
 * Numbers here are what the model is handed, so windowing and totals must be exact.
 */

const test = require("node:test");
const assert = require("node:assert/strict");
const { DateTime } = require("luxon");
const stats = require("../services/stats");

const ZONE = "Europe/Bucharest";
const NOW = DateTime.fromISO("2026-07-06T08:00:00", { zone: ZONE }); // Monday

// Helper: build an event with luxon start/end like dto.parseEvent produces.
const ev = (offsetDays, startHHMM, hours, category, status = "pending", title = "X") => {
  const [h, m] = startHHMM.split(":").map(Number);
  const start = NOW.startOf("day").plus({ days: offsetDays }).set({ hour: h, minute: m });
  return { id: `id${offsetDays}${startHHMM}`, title, start, end: start.plus({ hours }), category, status };
};

test("stats: upcoming totals, per-category hours, and busiest day", () => {
  const events = [
    ev(0, "10:00", 1.5, "Work"),   // Mon
    ev(0, "14:00", 1, "Work"),     // Mon  -> Mon has 2
    ev(1, "09:00", 1, "Fitness"),  // Tue
    ev(3, "12:00", 2, "Work"),     // Thu
    ev(3, "15:00", 1, "Fitness"),  // Thu  -> Thu has 2 as well; Mon wins on tie (first seen)
  ];
  const { upcoming } = stats.computeStats({ events, now: NOW });
  assert.equal(upcoming.total, 5);
  assert.equal(upcoming.byCategory.Work.count, 3);
  assert.equal(Math.round(upcoming.byCategory.Work.hours * 10) / 10, 4.5);
  assert.equal(upcoming.byCategory.Fitness.count, 2);
  assert.equal(upcoming.busiest.count, 2);

  const line = stats.buildStatsLine({ events, now: NOW });
  assert.match(line, /next7d total=5/);
  assert.match(line, /Work=3\(4\.5h\)/);
  assert.match(line, /busiest=\w{3}\(2\)/);
});

test("stats: past status counts respect the 30d window; 7d excluded from upcoming", () => {
  const events = [
    ev(-2, "10:00", 1, "Work", "completed"),   // in past-30d AND recent-7d
    ev(-10, "10:00", 1, "Fitness", "missed"),  // in past-30d, not recent-7d
    ev(-40, "10:00", 1, "Work", "completed"),  // outside past-30d -> ignored
    ev(2, "10:00", 1, "Work", "pending"),      // upcoming, not past
  ];
  const { upcoming, past } = stats.computeStats({ events, now: NOW });
  assert.equal(upcoming.total, 1);
  assert.equal(past.total, 2);
  assert.equal(past.status.completed, 1);
  assert.equal(past.status.missed, 1);

  const line = stats.buildStatsLine({ events, now: NOW });
  assert.match(line, /past30d total=2 completed=1 missed=1 displaced=0/);
});

test("stats: recentPastBlock lists only the last 7 days, id-less, sorted", () => {
  const events = [
    ev(-1, "18:00", 1, "Fitness", "completed", "Gym"),
    ev(-3, "12:00", 1, "Work", "missed", "Standup"),
    ev(-9, "12:00", 1, "Work", "completed", "OldMeeting"), // outside 7d -> excluded
  ];
  const block = stats.recentPastBlock({ events, now: NOW });
  assert.match(block, /^RECENT_PAST: /);
  assert.ok(!block.includes("OldMeeting"));
  assert.ok(!/\(E\d+\)/.test(block)); // never any E-token ids
  // Sorted ascending: Standup (-3) before Gym (-1).
  assert.ok(block.indexOf("Standup") < block.indexOf("Gym"));
  assert.match(block, /'Gym'\[Fitness\]\(completed\)/);
});

test("stats: no recent past -> empty block", () => {
  const events = [ev(2, "10:00", 1, "Work")];
  assert.equal(stats.recentPastBlock({ events, now: NOW }), "");
});

test("stats: nextUpBlock lists only events past the visible week, id-less and sorted", () => {
  const events = [
    ev(2, "09:00", 1, "Work", "pending", "InsideWeek"),        // < 7d -> excluded (in SCHEDULE)
    ev(20, "14:00", 1, "Health", "pending", "Dentist"),        // beyond week
    ev(10, "09:00", 1, "Work", "pending", "Standup"),          // beyond week, earlier
    ev(-3, "12:00", 1, "Work", "completed", "PastMeeting"),    // past -> excluded
  ];
  const block = stats.nextUpBlock({ events, now: NOW });
  assert.match(block, /^NEXT_UP: /);
  assert.ok(!block.includes("InsideWeek"));
  assert.ok(!block.includes("PastMeeting"));
  assert.ok(!/\(E\d+\)/.test(block)); // never any E-token ids
  // Sorted ascending: Standup (+10) before Dentist (+20).
  assert.ok(block.indexOf("Standup") < block.indexOf("Dentist"));
  // Carries a concrete MM-DD date + HH:mm so the model can reason about "when".
  assert.match(block, /'Dentist'\[Health\]/);
  assert.match(block, /\d{2}-\d{2} \d{2}:\d{2} 'Standup'/);
});

test("stats: nextUpBlock caps at NEXT_UP_MAX and is empty when nothing lies beyond the week", () => {
  assert.equal(stats.nextUpBlock({ events: [ev(2, "10:00", 1, "Work")], now: NOW }), "");

  const many = Array.from({ length: stats.NEXT_UP_MAX + 4 }, (_, i) =>
    ev(8 + i, "09:00", 1, "Work", "pending", `Ev${i}`));
  const block = stats.nextUpBlock({ events: many, now: NOW });
  const count = (block.match(/'Ev\d+'/g) ?? []).length;
  assert.equal(count, stats.NEXT_UP_MAX);
});
