/**
 * /v1 planning API — contract: BACKEND_PLAN.md §3 + ai-planner.md §3–§7.
 *
 * Shape of every handler: validate DTOs → compute free slots server-side →
 * build prompt → call Claude (retry-once on unparseable) → return typed JSON.
 * Clients never see prompts or raw model output.
 *
 * Design note on interpret: one Claude call returns the full intent union
 * (classifier and decision in a single prompt), rather than a classify call
 * followed by a per-intent call. DRY with the other routes lives at the
 * parser/builder level (shared EventDraft/alternatives parsing, shared slot
 * labels) — not by doubling latency and cost with two round trips.
 */

const express = require("express");
const { callAndParse, OPUS } = require("../lib/claude");
const { parseBase, parsePrefs, parseEvent, parseEventList, requireString, parseHistory } = require("../lib/dto");
const { badRequest } = require("../lib/errors");
const { parseISO, ymd } = require("../lib/time");
const scheduler = require("../services/scheduler");
const build = require("../services/contextBuilder");
const parsers = require("../services/parsers");
const stats = require("../services/stats");
const { expandGoalsToEvents } = require("../services/expander");
const { planWeek } = require("../services/weeklyPlanner");
const ics = require("../services/ics");
const prompts = require("../prompts");

function createV1Router({ callClaude, fetchImpl = globalThis.fetch }) {
  const router = express.Router();

  // Async handlers → error middleware
  const wrap = (fn) => (req, res, next) => fn(req, res).catch(next);

  /** Common preamble: base fields, prefs, event list. */
  const ctx = (body) => {
    const { now, zone } = parseBase(body);
    return { now, zone, prefs: parsePrefs(body.prefs), events: parseEventList(body.events, zone) };
  };

  const slots = ({ now, events, prefs }, hours, durationMinutes = 30) =>
    scheduler.freeSlots({
      durationMinutes,
      windowStart: now,
      windowEnd: now.plus({ hours }),
      events,
      prefs,
    });

  router.get("/health", (_req, res) => res.json({ status: "ok", version: "1" }));

  // ── Scheduling decisions ────────────────────────────────────────────────

  router.post("/schedule/add", wrap(async (req, res) => {
    const c = ctx(req.body);
    const description = requireString(req.body, "description");
    const freeSlots = slots(c, 72); // same 72h window the client used
    const payload = build.buildAdd({ now: c.now, description, freeSlots, prefs: c.prefs });
    const decision = await callAndParse(callClaude, { system: prompts.scheduling, payload },
      (text) => parsers.parseDecision(text, { zone: c.zone }));
    res.json(decision);
  }));

  router.post("/schedule/move", wrap(async (req, res) => {
    const c = ctx(req.body);
    const event = parseEvent(req.body.event, c.zone);
    const reason = requireString(req.body, "reason");
    const freeSlots = slots(c, 7 * 24);
    const surrounding = c.events.filter(
      (e) => e.id !== event.id && e.status !== "missed" && e.start.hasSame(event.start, "day")
    );
    const payload = build.buildMove({ now: c.now, event, reason, surroundingEvents: surrounding, freeSlots, prefs: c.prefs });
    const decision = await callAndParse(callClaude, { system: prompts.scheduling, payload },
      (text) => parsers.parseDecision(text, { zone: c.zone }));
    res.json(decision);
  }));

  router.post("/schedule/reschedule", wrap(async (req, res) => {
    const c = ctx(req.body);
    const event = parseEvent(req.body.event, c.zone);
    const missedCount = Number.isInteger(req.body.missedCount) ? req.body.missedCount : 1;
    const freeSlots = slots(c, 7 * 24);
    const payload = build.buildReschedule({ now: c.now, event, missedCount, freeSlots, prefs: c.prefs });
    const decision = await callAndParse(callClaude, { system: prompts.scheduling, payload },
      (text) => parsers.parseDecision(text, { zone: c.zone }));
    res.json(decision);
  }));

  // ── Interpret — the "Ask AI" secretary box ──────────────────────────────

  router.post("/schedule/interpret", wrap(async (req, res) => {
    const c = ctx(req.body);
    const text = requireString(req.body, "text");
    const freeSlots = slots(c, 7 * 24);
    const { text: scheduleText, idMap } = scheduler.compactScheduleWithIds({
      events: c.events,
      windowStart: c.now,
      windowEnd: c.now.plus({ days: 7 }),
      prefs: c.prefs,
    });
    // Read-only overview + history for the "summarize" intent (numbers computed
    // here, never by the model). Past events reach c.events because interpret
    // ships a wider window than the other routes.
    const statsLine = stats.buildStatsLine({ events: c.events, now: c.now });
    const recentPast = stats.recentPastBlock({ events: c.events, now: c.now });
    // Id-less list of events past the visible week — the "query" intent's source
    // for "when's my next X" lookups that fall beyond the 7-day SCHEDULE window.
    const nextUp = stats.nextUpBlock({ events: c.events, now: c.now });
    // Follow-up context for the read-only answer card — the device replays recent
    // turns so "what about swimming?" resolves against the prior answer (stateless).
    const history = parseHistory(req.body.history);
    const payload = build.buildInterpret({ now: c.now, text, scheduleText, freeSlots, prefs: c.prefs, statsLine, recentPast, nextUp, history });
    const decision = await callAndParse(callClaude, { system: prompts.interpret, payload },
      (raw) => parsers.parseInterpret(raw, { zone: c.zone, idMap }));
    res.json(decision);
  }));

  // ── Generate — fill a period with events for goals ──────────────────────

  router.post("/schedule/generate", wrap(async (req, res) => {
    const c = ctx(req.body);
    const goals = requireString(req.body, "goals");
    if (typeof req.body.period !== "object" || req.body.period === null) throw badRequest('Missing "period"');
    const period = {
      start: parseISO(req.body.period.start, c.zone, "period.start"),
      end: parseISO(req.body.period.end, c.zone, "period.end"),
    };
    if (period.end <= period.start) throw badRequest('"period.end" must be after "period.start"');
    // A period starting earlier today must not offer already-past slots.
    const windowStart = period.start < c.now ? c.now : period.start;
    if (period.end <= windowStart) throw badRequest('"period" is entirely in the past');
    const freeSlots = scheduler.freeSlots({
      durationMinutes: 30,
      windowStart,
      windowEnd: period.end,
      events: c.events,
      prefs: c.prefs,
    });
    const result = await expandGoalsToEvents(callClaude, {
      now: c.now, zone: c.zone, period, goals, freeSlots, prefs: c.prefs,
    });
    res.json(result);
  }));

  // ── Meals ────────────────────────────────────────────────────────────────

  router.post("/meal/suggestions", wrap(async (req, res) => {
    const c = ctx(req.body);
    if (!Array.isArray(req.body.existingMeals)) throw badRequest('Missing "existingMeals"');
    const meals = req.body.existingMeals.map((m, i) => {
      if (typeof m?.name !== "string") throw badRequest(`"existingMeals[${i}].name" is required`);
      return { name: m.name, prepTimeMinutes: Number.isInteger(m.prepTimeMinutes) ? m.prepTimeMinutes : 30 };
    });
    // Meals are planned during the day, not a week ahead (client design decision)
    // — default to today only; clients may widen up to 7 days.
    const days = Number.isInteger(req.body.days) ? Math.min(Math.max(req.body.days, 1), 7) : 1;
    const dinnerSlots = scheduler.dinnerSlots({ now: c.now, days, events: c.events, prefs: c.prefs });
    if (dinnerSlots.length === 0) return res.json({ suggestions: [] }); // nothing to schedule into — no AI call
    const payload = build.buildMealSuggestion({ now: c.now, meals, slots: dinnerSlots, prefs: c.prefs });
    const result = await callAndParse(callClaude, { system: prompts.mealSuggestion, payload },
      (text) => parsers.parseMealSuggestions(text, { zone: c.zone, now: c.now, prefs: c.prefs }));
    res.json(result);
  }));

  // ── Habits ───────────────────────────────────────────────────────────────

  router.post("/habits/analysis", wrap(async (req, res) => {
    const habits = req.body?.habits;
    if (!Array.isArray(habits) || habits.length === 0) throw badRequest('Missing "habits"');
    for (const [i, h] of habits.entries()) {
      if (typeof h?.name !== "string" || !Number.isInteger(h?.weekTotal) || !Number.isInteger(h?.priorWeekTotal)) {
        throw badRequest(`"habits[${i}]" needs name, weekTotal, priorWeekTotal`);
      }
    }
    const insight = await callClaude({ system: prompts.habit, payload: build.buildHabits(habits) });
    res.json({ insight: insight.trim() }); // plain text — no JSON parse, no retry needed
  }));

  // ── Calendar import — deterministic ICS expansion, NO Claude call ───────
  // calendar-import.md §4. Stateless: the feed URL is re-sent on every sync,
  // never stored — and never logged, since secret feed URLs carry auth.

  router.post("/calendar/ics", wrap(async (req, res) => {
    const { zone } = parseBase(req.body); // `now` is required by contract; expansion itself is window-driven
    const url = requireString(req.body, "url");
    const windowStartRaw = requireString(req.body, "windowStart");
    const windowEndRaw = requireString(req.body, "windowEnd");
    const windowStart = parseISO(windowStartRaw, zone, "windowStart");
    let windowEnd = parseISO(windowEndRaw, zone, "windowEnd");
    if (/^\d{4}-\d{2}-\d{2}$/.test(windowEndRaw)) windowEnd = windowEnd.endOf("day"); // date-only end is inclusive
    if (windowEnd <= windowStart) throw badRequest('"windowEnd" must be after "windowStart"');
    if (windowEnd.diff(windowStart, "days").days > 91) {
      throw badRequest('"windowStart"–"windowEnd" must span 90 days or fewer');
    }
    const icsText = await ics.fetchFeed(url, fetchImpl);
    res.json(ics.expandFeed(icsText, { windowStart, windowEnd, zone }));
  }));

  // ── Deep project plan ────────────────────────────────────────────────────

  router.post("/project/plan", wrap(async (req, res) => {
    const { now, zone } = parseBase(req.body);
    const goal = requireString(req.body, "goal");
    const deadline = parseISO(req.body.deadline, zone, "deadline");
    const weeklyHours = Number.isInteger(req.body.weeklyHours) ? req.body.weeklyHours : 5;
    const constraints = typeof req.body.constraints === "string" ? req.body.constraints : "";
    const payload = build.buildProjectPlan({ now, goal, deadline, weeklyHours, constraints });
    const result = await callAndParse(callClaude, { system: prompts.projectPlan, payload },
      (text) => parsers.parseProjectPlan(text));
    res.json(result);
  }));

  // ── Deep planner — thin whole-horizon skeleton + cushion ─────────────────
  // deep-planner-plan.md §3, §6. Opus + adaptive thinking + high effort: the one
  // place plan quality compounds (accuracy over cost). One-shot intake for now;
  // the multiturn clarify conversation replaces this entry point in increment 3.

  router.post("/plan/skeleton", wrap(async (req, res) => {
    const { now, zone } = parseBase(req.body);
    const goal = requireString(req.body, "goal");
    const goalType = req.body.goalType === "project" ? "project" : "study";
    const weeklyHours = Number.isInteger(req.body.weeklyHours) && req.body.weeklyHours > 0 ? req.body.weeklyHours : 6;
    const constraints = typeof req.body.constraints === "string" ? req.body.constraints : "";
    const hasDeadline = typeof req.body.deadline === "string" && req.body.deadline.length > 0;
    const deadline = hasDeadline ? parseISO(req.body.deadline, zone, "deadline") : null;
    if (deadline && deadline.endOf("day") <= now) throw badRequest('"deadline" is in the past');

    // Committed capacity = weeklyHours × weeks until the deadline (or a default
    // horizon when the goal is open-ended). This is the honest "time you HAVE"
    // for cushion math; whether those hours physically fit the calendar is the
    // weekly-placement route's job, not the skeleton's.
    const DEFAULT_HORIZON_WEEKS = 8;
    const weeksAvailable = deadline
      ? Math.max(1, Math.ceil(deadline.endOf("day").diff(now, "days").days / 7))
      : DEFAULT_HORIZON_WEEKS;

    const payload = build.buildPlanSkeleton({ now, goal, goalType, deadline, weeklyHours, weeksAvailable, constraints });
    const skeleton = await callAndParse(
      callClaude,
      { system: prompts.planSkeleton, payload, model: OPUS, maxTokens: 8000, thinking: true, effort: "high" },
      (text) => parsers.parsePlanSkeleton(text)
    );

    const neededMinutes = skeleton.workUnits.reduce((acc, u) => acc + u.estimatedMinutes, 0);
    const availableMinutes = weeklyHours * 60 * weeksAvailable;

    res.json({
      plan: {
        title: skeleton.title,
        goalType,
        deadline: deadline ? ymd(deadline) : null,
        workUnits: skeleton.workUnits,
      },
      capacity: { neededMinutes, availableMinutes, cushionMinutes: availableMinutes - neededMinutes },
    });
  }));

  // ── Deep planner — deterministic weekly placement (NO Claude call) ────────
  // deep-planner-plan.md §3. Picks the work units due in the window (walking
  // afterUnit / minGapDays / notLastNDaysBeforeDeadline) and packs them into
  // free slots. Pure constraint satisfaction — the skeleton already did the
  // fuzzy→structured translation, so no model is needed here.

  router.post("/plan/week", wrap(async (req, res) => {
    const c = ctx(req.body); // { now, zone, prefs, events }
    const weeklyHours = Number.isInteger(req.body.weeklyHours) && req.body.weeklyHours > 0 ? req.body.weeklyHours : 6;

    const planBody = req.body.plan;
    if (typeof planBody !== "object" || planBody === null) throw badRequest('Missing "plan"');
    const goalType = planBody.goalType === "project" ? "project" : "study";
    const deadline = typeof planBody.deadline === "string" && planBody.deadline
      ? parseISO(planBody.deadline, c.zone, "plan.deadline") : null;
    if (!Array.isArray(planBody.workUnits) || planBody.workUnits.length === 0) throw badRequest('"plan.workUnits" is required');
    const workUnits = planBody.workUnits.map((u, i) => {
      if (typeof u?.id !== "string" || typeof u?.title !== "string" || typeof u?.objective !== "string") {
        throw badRequest(`"plan.workUnits[${i}]" needs id, title, objective`);
      }
      if (!Number.isInteger(u.estimatedMinutes) || u.estimatedMinutes <= 0) {
        throw badRequest(`"plan.workUnits[${i}].estimatedMinutes" must be a positive integer`);
      }
      const cs = u.constraints ?? {};
      return {
        id: u.id, title: u.title, objective: u.objective,
        estimatedMinutes: u.estimatedMinutes,
        archetype: u.archetype === "repetition" ? "repetition" : "milestone",
        constraints: {
          afterUnit: typeof cs.afterUnit === "string" ? cs.afterUnit : null,
          repeatOf: typeof cs.repeatOf === "string" ? cs.repeatOf : null,
          minGapDays: Number.isInteger(cs.minGapDays) ? cs.minGapDays : null,
          notLastNDaysBeforeDeadline: Number.isInteger(cs.notLastNDaysBeforeDeadline) ? cs.notLastNDaysBeforeDeadline : null,
        },
      };
    });

    if (typeof req.body.window !== "object" || req.body.window === null) throw badRequest('Missing "window"');
    const windowEnd = parseISO(req.body.window.end, c.zone, "window.end");
    let windowStart = parseISO(req.body.window.start, c.zone, "window.start");
    if (windowStart < c.now) windowStart = c.now;           // never place in the past
    if (windowEnd <= windowStart) throw badRequest('"window" is empty or entirely in the past');

    const progress = Array.isArray(req.body.progress)
      ? req.body.progress.flatMap((p, i) => {
          if (typeof p?.workUnitId !== "string") throw badRequest(`"progress[${i}].workUnitId" is required`);
          return [{
            workUnitId: p.workUnitId,
            scheduledMinutes: Number.isInteger(p.scheduledMinutes) ? p.scheduledMinutes : 0,
            lastSessionDate: typeof p.lastSessionDate === "string" && p.lastSessionDate
              ? parseISO(p.lastSessionDate, c.zone, `progress[${i}].lastSessionDate`) : null,
          }];
        })
      : [];

    const freeSlots = scheduler.freeSlots({
      durationMinutes: 30, windowStart, windowEnd, events: c.events, prefs: c.prefs,
    });

    res.json(planWeek({
      plan: { goalType, deadline, workUnits },
      window: { start: windowStart, end: windowEnd },
      progress, weeklyHours, freeSlots, prefs: c.prefs,
    }));
  }));

  // ── Deep planner — content tweak of selected sessions ─────────────────────
  // A small, cheap call: the plan's work units are shared as context, so this
  // runs on the default (Sonnet) secretary model, NOT the Opus planner. Edits
  // are content-only (title / objective / duration / done) — placement stays
  // deterministic/manual, so no free-slot computation is needed here.

  router.post("/plan/tweak", wrap(async (req, res) => {
    const { now, zone } = parseBase(req.body);

    const planBody = req.body.plan;
    if (typeof planBody !== "object" || planBody === null) throw badRequest('Missing "plan"');
    const plan = {
      title: typeof planBody.title === "string" ? planBody.title : "",
      goalType: planBody.goalType === "project" ? "project" : "study",
      workUnits: Array.isArray(planBody.workUnits)
        ? planBody.workUnits
            .filter((u) => u && typeof u.id === "string")
            .map((u) => ({
              id: u.id,
              title: typeof u.title === "string" ? u.title : "",
              objective: typeof u.objective === "string" ? u.objective : "",
            }))
        : [],
    };

    if (!Array.isArray(req.body.sessions) || req.body.sessions.length === 0) throw badRequest('"sessions" is required');
    const sessions = req.body.sessions.map((s, i) => {
      if (typeof s?.ref !== "string") throw badRequest(`"sessions[${i}].ref" is required`);
      return {
        ref: s.ref,
        title: typeof s.title === "string" ? s.title : "",
        objective: typeof s.objective === "string" ? s.objective : "",
        start: parseISO(s.start, zone, `sessions[${i}].start`),
        end: parseISO(s.end, zone, `sessions[${i}].end`),
      };
    });

    const instruction = requireString(req.body, "instruction");

    const payload = build.buildPlanTweak({ now, plan, sessions, instruction });
    const result = await callAndParse(callClaude, { system: prompts.planTweak, payload },
      (raw) => parsers.parsePlanTweak(raw));
    res.json(result);
  }));

  return router;
}

module.exports = { createV1Router };
