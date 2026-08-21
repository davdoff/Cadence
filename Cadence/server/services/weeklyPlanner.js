/**
 * Deterministic weekly placement (deep-planner-plan.md §3). No Claude call: the
 * skeleton already carries concrete objectives + hour estimates, so planning a
 * week is pure constraint satisfaction — pick the work units due in the window,
 * split them into sessions, and pack them into free slots without overlaps.
 *
 * A pure function over already-parsed inputs (DateTimes carry the request zone),
 * so it ports to Kotlin later and tests without a network or a fake model.
 */

const { toISO } = require("../lib/time");

const MIN_SESSION = 30;   // don't create sessions shorter than this
const MAX_SESSION = 120;  // cap a single block so a unit's week isn't one slab

/**
 * @param plan     { goalType, deadline: DateTime|null, workUnits: [WorkUnit] }
 * @param window   { start: DateTime, end: DateTime }  already clamped to `now`
 * @param progress [{ workUnitId, scheduledMinutes, lastSessionDate: DateTime|null }]
 * @param freeSlots [{ start: DateTime, end: DateTime }]
 * @returns { events: [{ title, start, end, category, workUnitId, objective }] }
 */
function planWeek({ plan, window, progress, weeklyHours, freeSlots, prefs }) {
  const byId = new Map(plan.workUnits.map((u) => [u.id, u]));
  const scheduled = new Map();
  const lastDate = new Map();
  for (const p of progress) {
    scheduled.set(p.workUnitId, p.scheduledMinutes || 0);
    if (p.lastSessionDate) lastDate.set(p.workUnitId, p.lastSessionDate);
  }

  const remainingOf = (u) => u.estimatedMinutes - (scheduled.get(u.id) || 0);
  const exhausted = (u) => remainingOf(u) <= 0;

  // New material is blocked inside the deadline's no-new-material zone. The zone
  // starts `n` days before the deadline; the whole window is blocked only when it
  // begins inside the zone (used for selection), but placement also enforces a
  // per-unit cutoff so a session can't land inside the zone even mid-window.
  const zoneStart = (u) => {
    const n = u.constraints.notLastNDaysBeforeDeadline;
    return n != null && plan.deadline != null ? plan.deadline.minus({ days: n }).startOf("day") : null;
  };
  const inDeadlineZone = (u) => {
    const cutoff = zoneStart(u);
    return cutoff != null && window.start >= cutoff;
  };

  const eligible = (u) => {
    if (remainingOf(u) <= 0) return false;
    const c = u.constraints;
    if (c.afterUnit) {
      const dep = byId.get(c.afterUnit);
      if (dep && !exhausted(dep)) return false;      // dependency not finished
    }
    if (c.repeatOf) {
      const orig = byId.get(c.repeatOf);
      if (!orig || (scheduled.get(orig.id) || 0) <= 0) return false;  // original not started
      const last = lastDate.get(orig.id);
      if (last && window.start < last.plus({ days: c.minGapDays || 0 })) return false; // gap not elapsed
    }
    if (inDeadlineZone(u)) return false;
    return true;
  };

  // Selection: skeleton order, capped by the week's committed budget.
  const sessions = [];
  let budgetLeft = weeklyHours * 60;
  for (const u of plan.workUnits) {
    if (budgetLeft < MIN_SESSION) break;
    if (!eligible(u)) continue;
    let alloc = Math.min(remainingOf(u), budgetLeft);
    while (alloc >= MIN_SESSION && budgetLeft >= MIN_SESSION) {
      const minutes = Math.min(alloc, MAX_SESSION, budgetLeft);
      if (minutes < MIN_SESSION) break;
      // Per-unit cutoff: new-material units must not be placed inside the
      // no-new-material zone even if the window started before it.
      sessions.push({ workUnitId: u.id, title: u.title, objective: u.objective, minutes, cutoff: zoneStart(u) });
      alloc -= minutes;
      budgetLeft -= minutes;
    }
  }

  const categoryName = plan.goalType === "project" ? "Work" : "Study";
  return { events: placeSessions(sessions, freeSlots, prefs.bufferMinutes, categoryName) };
}

/** Pack sessions into free slots, round-robining across days so a week's work
 *  spreads out instead of stacking on the first free day. Sessions that fit
 *  nowhere are dropped (an honest under-fill, not an overflow). */
function placeSessions(sessions, freeSlots, buffer, categoryName) {
  const slots = freeSlots.map((s) => ({ start: s.start, end: s.end, cursor: s.start, day: s.start.toISODate() }));
  const days = [...new Set(slots.map((s) => s.day))].sort();
  const slotsByDay = new Map(days.map((d) => [d, slots.filter((s) => s.day === d)]));

  const events = [];
  let dayPtr = 0;
  for (const session of sessions) {
    let placed = null;
    // Try days starting at the round-robin pointer, wrapping, until one fits.
    for (let i = 0; i < days.length && !placed; i++) {
      const day = days[(dayPtr + i) % days.length];
      for (const slot of slotsByDay.get(day)) {
        if (slot.end.diff(slot.cursor, "minutes").minutes >= session.minutes) {
          const start = slot.cursor;
          // Respect a new-material unit's deadline cutoff — skip slots inside it.
          if (session.cutoff && start >= session.cutoff) continue;
          const end = start.plus({ minutes: session.minutes });
          slot.cursor = end.plus({ minutes: buffer });
          placed = { start, end };
          break;
        }
      }
    }
    if (!placed) continue;
    dayPtr = (dayPtr + 1) % days.length; // advance so the next session prefers the next day
    events.push({
      title: session.title,
      start: toISO(placed.start),
      end: toISO(placed.end),
      category: categoryName,
      workUnitId: session.workUnitId,
      objective: session.objective,
    });
  }

  events.sort((a, b) => (a.start < b.start ? -1 : 1));
  return events;
}

module.exports = { planWeek };
