/**
 * Port of Cadence/Services/SchedulerService.swift (free-slot finding, conflicts)
 * plus the interpret/meal helpers that used to live client-side.
 *
 * Events here are already-parsed snapshots:
 *   { id, title, start: DateTime, end: DateTime, category, status }
 * Slots are { start: DateTime, end: DateTime }. All math happens in the
 * request's timezone (the DateTimes carry it).
 *
 * avoidScheduling weekdays use ISO numbering 1=Mon..7=Sun (contract), which is
 * exactly luxon's `weekday` — no conversion needed here; clients convert.
 */

const { parseHHMM, dayAbbr, hhmm } = require("../lib/time");

// Missed and displaced events no longer occupy time — both are awaiting a new
// slot (displaced = "the planner moved this aside", ai-planner.md §6).
const occupiesTime = (e) => e.status !== "missed" && e.status !== "displaced";
const sameDay = (dt, day) => dt.hasSame(day, "day");

/** Sorted-interval merge — mirror of SchedulerService.merge. */
function mergeIntervals(intervals) {
  if (intervals.length === 0) return [];
  const result = [intervals[0]];
  for (const interval of intervals.slice(1)) {
    const last = result[result.length - 1];
    if (interval.start <= last.end) {
      result[result.length - 1] = { start: last.start, end: interval.end > last.end ? interval.end : last.end };
    } else {
      result.push(interval);
    }
  }
  return result;
}

/** Every event overlapping the proposal, buffer respected on both sides.
 *  Missed/displaced events are ignored — they no longer occupy time. */
function conflicts(proposal, events, bufferMinutes) {
  return events.filter((event) => {
    if (!occupiesTime(event)) return false;
    const start = event.start.minus({ minutes: bufferMinutes });
    const end = event.end.plus({ minutes: bufferMinutes });
    return start < proposal.end && proposal.start < end;
  });
}

/**
 * Free windows of at least `durationMinutes` between windowStart and windowEnd.
 * Respects working hours, buffer after each event, and avoid-scheduling blocks.
 */
function freeSlots({ durationMinutes, windowStart, windowEnd, events, prefs }) {
  const requiredMs = durationMinutes * 60_000;
  const result = [];

  let day = windowStart.startOf("day");
  const lastDay = windowEnd.startOf("day");

  while (day <= lastDay) {
    const workStart = day.set({ hour: prefs.workStartHour, minute: 0, second: 0, millisecond: 0 });
    const workEnd = day.set({ hour: prefs.workEndHour, minute: 0, second: 0, millisecond: 0 });

    const blocked = [];

    // Events block start → end + buffer
    for (const event of events) {
      if (occupiesTime(event) && sameDay(event.start, day)) {
        blocked.push({ start: event.start, end: event.end.plus({ minutes: prefs.bufferMinutes }) });
      }
    }

    // Avoid-scheduling blocks (weekdays: ISO 1=Mon..7=Sun, empty = every day)
    for (const avoid of prefs.avoidScheduling) {
      if (avoid.weekdays.length > 0 && !avoid.weekdays.includes(day.weekday)) continue;
      const s = parseHHMM(avoid.start, "avoidScheduling.start");
      const e = parseHHMM(avoid.end, "avoidScheduling.end");
      blocked.push({
        start: day.set({ hour: s.hour, minute: s.minute, second: 0, millisecond: 0 }),
        end: day.set({ hour: e.hour, minute: e.minute, second: 0, millisecond: 0 }),
      });
    }

    blocked.sort((a, b) => a.start - b.start);
    const merged = mergeIntervals(blocked);

    // Walk the merged blocks and collect gaps within working hours
    let cursor = workStart;
    for (const block of merged) {
      const blockStart = block.start > workStart ? block.start : workStart;
      const blockEnd = block.end < workEnd ? block.end : workEnd;

      if (blockStart > cursor && blockStart.diff(cursor).toMillis() >= requiredMs) {
        result.push({ start: cursor, end: blockStart });
      }
      if (blockEnd > cursor) cursor = blockEnd;
    }
    if (workEnd > cursor && workEnd.diff(cursor).toMillis() >= requiredMs) {
      result.push({ start: cursor, end: workEnd });
    }

    day = day.plus({ days: 1 });
  }

  // Slots before windowStart are gone; a straddling slot starts at
  // windowStart (same rule as dinnerSlots — callers pass `now` or a
  // period start, and the past must never be offered to the model).
  return result
    .map((s) => ({ start: s.start > windowStart ? s.start : windowStart, end: s.end }))
    .filter((s) => s.end.diff(s.start).toMillis() >= requiredMs);
}

/**
 * Free gaps inside the dinner window for the next `days` days.
 * Replaces the client-side MealSchedulerService.remainingDinnerSlots feed for
 * /v1/meal/suggestions. Gaps shorter than 20 min are useless for cooking.
 */
function dinnerSlots({ now, days = 7, events, prefs }) {
  const MIN_GAP_MS = 20 * 60_000;
  const winStart = parseHHMM(prefs.dinnerWindow.start, "dinnerWindow.start");
  const winEnd = parseHHMM(prefs.dinnerWindow.end, "dinnerWindow.end");
  const result = [];

  for (let offset = 0; offset < days; offset++) {
    const day = now.startOf("day").plus({ days: offset });
    const windowStart = day.set({ hour: winStart.hour, minute: winStart.minute, second: 0, millisecond: 0 });
    const windowEnd = day.set({ hour: winEnd.hour, minute: winEnd.minute, second: 0, millisecond: 0 });

    const blocked = events
      .filter((e) => occupiesTime(e) && e.start < windowEnd && windowStart < e.end.plus({ minutes: prefs.bufferMinutes }))
      .map((e) => ({ start: e.start, end: e.end.plus({ minutes: prefs.bufferMinutes }) }))
      .sort((a, b) => a.start - b.start);

    let cursor = windowStart;
    for (const block of mergeIntervals(blocked)) {
      const blockStart = block.start > windowStart ? block.start : windowStart;
      if (blockStart > cursor) result.push({ start: cursor, end: blockStart });
      if (block.end > cursor) cursor = block.end < windowEnd ? block.end : windowEnd;
    }
    if (windowEnd > cursor) result.push({ start: cursor, end: windowEnd });
  }

  // Past slots are gone; a straddling slot starts now.
  return result
    .map((s) => ({ start: s.start > now ? s.start : now, end: s.end }))
    .filter((s) => s.end.diff(s.start).toMillis() >= MIN_GAP_MS);
}

/** "SAT 10:00-11:00" — the token-efficient slot label the prompts use. */
const slotLabel = (slot) => `${dayAbbr(slot.start)} ${hhmm(slot.start)}-${hhmm(slot.end)}`;

/**
 * Compact schedule string for the interpret prompt, with short id tokens:
 *   SAT 10:00-11:00[Work](E1) 13:00-14:00[Meal](E2)
 *   SUN FREE:09:00-18:00
 * UUIDs are long and token-hungry, so the model sees E1..En and we map back.
 * Returns { text, idMap: { E1: "uuid", ... } }.
 */
function compactScheduleWithIds({ events, windowStart, windowEnd, prefs }) {
  const MIN_FREE_MS = 30 * 60_000;
  const lines = [];
  const idMap = {};
  let nextToken = 1;

  let day = windowStart.startOf("day");
  const lastDay = windowEnd.startOf("day");

  while (day <= lastDay) {
    const workStart = day.set({ hour: prefs.workStartHour, minute: 0, second: 0, millisecond: 0 });
    const workEnd = day.set({ hour: prefs.workEndHour, minute: 0, second: 0, millisecond: 0 });
    const abbr = dayAbbr(day);

    const dayEvents = events
      .filter((e) => occupiesTime(e) && sameDay(e.start, day))
      .sort((a, b) => a.start - b.start);

    if (dayEvents.length === 0) {
      lines.push(`${abbr} FREE:${hhmm(workStart)}-${hhmm(workEnd)}`);
    } else {
      const parts = dayEvents.map((e) => {
        const token = `E${nextToken++}`;
        idMap[token] = e.id;
        return `${hhmm(e.start)}-${hhmm(e.end)}[${e.category ?? "—"}](${token})`;
      });
      const last = dayEvents[dayEvents.length - 1];
      if (workEnd.diff(last.end).toMillis() >= MIN_FREE_MS) {
        parts.push(`FREE:${hhmm(last.end)}-${hhmm(workEnd)}`);
      }
      lines.push(`${abbr} ${parts.join(" ")}`);
    }

    day = day.plus({ days: 1 });
  }

  // Missed/displaced events occupy no time but must stay targetable — they're
  // exactly what the "reschedule" intent points at (ai-planner.md §4, §6).
  const needsReschedule = events.filter((e) => e.status === "missed" || e.status === "displaced");
  if (needsReschedule.length > 0) {
    const parts = needsReschedule.map((e) => {
      const token = `E${nextToken++}`;
      idMap[token] = e.id;
      return `'${e.title}'[${e.category ?? "—"}](${token})`;
    });
    lines.push(`NEEDS_RESCHEDULING: ${parts.join(" ")}`);
  }

  return { text: lines.join("\n"), idMap };
}

module.exports = { conflicts, freeSlots, dinnerSlots, slotLabel, compactScheduleWithIds, mergeIntervals };
