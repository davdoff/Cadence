/**
 * Read-only schedule analytics for the interpret payload's "summarize" intent.
 * Pure aggregates over the events the client already sends — the numbers are
 * computed here (deterministically, OS-blind) so the model narrates VERIFIED
 * figures instead of counting for itself (ai-planner.md; BACKEND_PLAN rule 2).
 *
 * The interpret route appends STATS (a one-line summary) and RECENT_PAST (a
 * short, id-less list of just-finished events) to every interpret payload, so
 * a summarize request has real overview + history to work from. RECENT_PAST is
 * deliberately id-less: past events must never receive E-tokens, or move/delete
 * could target something already over.
 */

const { dayAbbr, hhmm } = require("../lib/time");

const UPCOMING_DAYS = 7;    // forward overview window (matches SCHEDULE)
const STATS_PAST_DAYS = 30; // how far back the aggregate counts reach
const RECENT_PAST_DAYS = 7; // how far back the id-less event listing reaches
const NEXT_UP_MAX = 8;      // how many events NEXT_UP lists beyond the visible week

const hoursOf = (e) => Math.max(0, e.end.diff(e.start, "hours").hours);
const round1 = (n) => Math.round(n * 10) / 10;

/** Events whose start falls in [from, to). Luxon DateTimes compare by valueOf. */
const startsWithin = (events, from, to) => events.filter((e) => e.start >= from && e.start < to);

/** Aggregate a bucket: total, per-category count+hours, busiest weekday. */
function aggregate(events) {
  const byCategory = {};
  const byDay = {};
  for (const e of events) {
    const cat = e.category ?? "Uncategorized";
    const c = (byCategory[cat] ??= { count: 0, hours: 0 });
    c.count += 1;
    c.hours += hoursOf(e);
    const d = dayAbbr(e.start);
    byDay[d] = (byDay[d] ?? 0) + 1;
  }
  let busiest = null;
  for (const [day, count] of Object.entries(byDay)) {
    if (!busiest || count > busiest.count) busiest = { day, count };
  }
  return { total: events.length, byCategory, busiest };
}

/** Counts by lifecycle status among a bucket of events. */
function statusCounts(events) {
  const counts = { pending: 0, completed: 0, missed: 0, displaced: 0 };
  for (const e of events) {
    if (counts[e.status] !== undefined) counts[e.status] += 1;
  }
  return counts;
}

/** Structured stats: forward overview + recent-past status breakdown. */
function computeStats({ events, now }) {
  const upcoming = startsWithin(events, now, now.plus({ days: UPCOMING_DAYS }));
  const past = startsWithin(events, now.minus({ days: STATS_PAST_DAYS }), now);
  return {
    upcoming: aggregate(upcoming),
    past: { total: past.length, status: statusCounts(past) },
  };
}

/** One compact prompt line the model must ground its numbers in. */
function buildStatsLine({ events, now }) {
  const { upcoming, past } = computeStats({ events, now });
  const cats = Object.entries(upcoming.byCategory)
    .map(([name, v]) => `${name}=${v.count}(${round1(v.hours)}h)`)
    .join(" ");
  const busiest = upcoming.busiest ? ` busiest=${upcoming.busiest.day}(${upcoming.busiest.count})` : "";
  const next = `next${UPCOMING_DAYS}d total=${upcoming.total}${cats ? " " + cats : ""}${busiest}`;
  const s = past.status;
  const prev = `past${STATS_PAST_DAYS}d total=${past.total} completed=${s.completed} missed=${s.missed} displaced=${s.displaced}`;
  return `STATS: ${next}; ${prev}`;
}

/** Id-less compact list of recent past events, or "" when there are none. */
function recentPastBlock({ events, now }) {
  const recent = startsWithin(events, now.minus({ days: RECENT_PAST_DAYS }), now)
    .sort((a, b) => a.start - b.start);
  if (recent.length === 0) return "";
  const parts = recent.map((e) => `${dayAbbr(e.start)} '${e.title}'[${e.category ?? "—"}](${e.status})`);
  return `RECENT_PAST: ${parts.join(" ")}`;
}

/**
 * Id-less compact list of the next few events that start AFTER the visible
 * 7-day SCHEDULE window — the answer source for "when's my next X" lookups
 * (the "query" intent) that fall past what SCHEDULE shows. Like RECENT_PAST it
 * carries NO ids, so far-out events can be read but never moved/deleted. Includes
 * a concrete MM-DD date so the model can reason "in 2 weeks" off NOW.
 * Returns "" when nothing lies beyond the week.
 */
function nextUpBlock({ events, now }) {
  const beyond = events
    .filter((e) => e.start >= now.plus({ days: UPCOMING_DAYS }))
    .sort((a, b) => a.start - b.start)
    .slice(0, NEXT_UP_MAX);
  if (beyond.length === 0) return "";
  const parts = beyond.map(
    (e) => `${dayAbbr(e.start)} ${e.start.toFormat("MM-dd")} ${hhmm(e.start)} '${e.title}'[${e.category ?? "—"}]`
  );
  return `NEXT_UP: ${parts.join(" ")}`;
}

module.exports = {
  computeStats, buildStatsLine, recentPastBlock, nextUpBlock, aggregate, statusCounts,
  UPCOMING_DAYS, STATS_PAST_DAYS, RECENT_PAST_DAYS, NEXT_UP_MAX,
};
