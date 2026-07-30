/**
 * Port of Cadence/Services/SchedulingContextBuilder.swift — builds the compact,
 * token-efficient user payloads sent to Claude. Every payload starts with a NOW
 * line carrying the device time + offset (the model derives the UTC offset from it).
 */

const { toISO, dayAbbr, hhmm, ymd } = require("../lib/time");
const { slotLabel } = require("./scheduler");

const withNow = (now, body) => `NOW: ${toISO(now)}\n${body}`;
const slotsLine = (slots) => slots.map(slotLabel).join(", ");
const timeRange = (e) => `${hhmm(e.start)}-${hhmm(e.end)}`;

/** Mirror of SchedulerService.compactPreferenceString, built per request. */
function prefsLine(prefs) {
  const parts = [
    `WorkHours=${prefs.workStartHour}-${prefs.workEndHour}`,
    `Buffer=${prefs.bufferMinutes}min`,
  ];
  if (prefs.priorityCategories.length > 0) parts.push(`Priority=[${prefs.priorityCategories.join(",")}]`);
  parts.push(`AILevel=${prefs.aiLevel}`);
  return parts.join(", ");
}

const buildAdd = ({ now, description, freeSlots, prefs }) =>
  withNow(now, `FREE_SLOTS: ${slotsLine(freeSlots)}
NEW_EVENT: "${description}"
PREFS: BufferBetweenEvents=${prefs.bufferMinutes}min`);

const buildMove = ({ now, event, reason, surroundingEvents, freeSlots, prefs }) => {
  const anchor = `${event.title} | ${dayAbbr(event.start)} ${timeRange(event)} | category=${event.category ?? "—"}`;
  const surrounding = surroundingEvents
    .map((e) => `${dayAbbr(e.start)} ${timeRange(e)}[${e.category ?? "—"}]`)
    .join(" ");
  return withNow(now, `ANCHOR_EVENT: ${anchor}
SURROUNDING_EVENTS: ${surrounding || "none"}
FREE_SLOTS: ${slotsLine(freeSlots)}
REASON_FOR_MOVE: "${reason}"
PREFS: BufferBetweenEvents=${prefs.bufferMinutes}min`);
};

const buildReschedule = ({ now, event, missedCount, freeSlots, prefs }) =>
  withNow(now, `MISSED_EVENT: ${event.title} | WAS: ${dayAbbr(event.start)} ${timeRange(event)} | missed_count=${missedCount}
FREE_SLOTS (next 7d): ${slotsLine(freeSlots)}
PREFS: BufferBetweenEvents=${prefs.bufferMinutes}min`);

const buildMealSuggestion = ({ now, meals, slots, prefs }) => {
  const mealsLine = meals.map((m) => `${m.name}(${m.prepTimeMinutes}min)`).join(", ");
  const guidance = (prefs.mealGuidance ?? "").trim();
  const guidanceLine = guidance ? `\nGUIDANCE: "${guidance}"` : "";
  return withNow(now, `INTENT: new_meal_suggestion
EXISTING_MEALS: ${mealsLine}
FREE_DINNER_SLOTS: ${slotsLine(slots)}
PREFS: dinnerWindow=${prefs.dinnerWindow.start}-${prefs.dinnerWindow.end}` + guidanceLine);
};

const buildHabits = (habits) => {
  const line = habits
    .map((h) => {
      const trend = h.weekTotal > h.priorWeekTotal ? "↑" : h.weekTotal < h.priorWeekTotal ? "↓" : "→";
      return `${h.name}=${h.weekTotal}(${trend} from ${h.priorWeekTotal})`;
    })
    .join(", ");
  return `HABITS_WEEK: ${line}`;
};

const buildProjectPlan = ({ now, goal, deadline, weeklyHours, constraints }) =>
  withNow(now, `GOAL: "${goal}"
DEADLINE: ${ymd(deadline)}
WEEKLY_HOURS: ${weeklyHours}
CONSTRAINTS: "${constraints}"`);

const buildInterpret = ({ now, text, scheduleText, freeSlots, prefs, statsLine = "", recentPast = "", nextUp = "", history = [] }) => {
  const categoriesLine =
    prefs.allCategories.length > 0 ? `\nCATEGORIES: [${prefs.allCategories.join(", ")}]` : "";
  // STATS + RECENT_PAST feed the read-only "summarize" intent; NEXT_UP feeds the
  // read-only "query" intent's beyond-the-week lookups (all from stats.js). They
  // ride on every interpret payload because classification is one-shot.
  const statsPart = statsLine ? `\n${statsLine}` : "";
  const recentPart = recentPast ? `\n${recentPast}` : "";
  const nextUpPart = nextUp ? `\n${nextUp}` : "";
  // Follow-up thread for the read-only answer card: earlier turns, oldest first,
  // so the model resolves references against them. USER_REQUEST is still the latest.
  const conversationPart = history.length > 0
    ? `CONVERSATION (earlier turns this session, oldest first):\n${history
        .map((t) => `USER: ${t.user}\nYOU: ${t.assistant}`)
        .join("\n")}\n`
    : "";
  return withNow(now, `${conversationPart}SCHEDULE:
${scheduleText}
FREE_SLOTS: ${slotsLine(freeSlots)}
USER_REQUEST: "${text}"${categoriesLine}
PREFS: ${prefsLine(prefs)}${statsPart}${recentPart}${nextUpPart}`);
};

const buildPlanSkeleton = ({ now, goal, goalType, deadline, weeklyHours, weeksAvailable, constraints }) =>
  withNow(now, `GOAL: "${goal}"
TYPE: ${goalType}
DEADLINE: ${deadline ? ymd(deadline) : "none"}
WEEKLY_HOURS: ${weeklyHours}
WEEKS_AVAILABLE: ${weeksAvailable}
CONSTRAINTS: "${constraints}"`);

const buildGenerate = ({ now, period, goals, freeSlots, prefs }) =>
  withNow(now, `PERIOD: ${ymd(period.start)} to ${ymd(period.end)}
GOALS: "${goals}"
FREE_SLOTS: ${slotsLine(freeSlots)}
PREFS: ${prefsLine(prefs)}`);

module.exports = {
  buildAdd, buildMove, buildReschedule, buildMealSuggestion,
  buildHabits, buildProjectPlan, buildInterpret, buildGenerate, buildPlanSkeleton,
};
