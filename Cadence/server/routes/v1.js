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
const { callAndParse } = require("../lib/claude");
const { parseBase, parsePrefs, parseEvent, parseEventList, requireString } = require("../lib/dto");
const { badRequest } = require("../lib/errors");
const { parseISO } = require("../lib/time");
const scheduler = require("../services/scheduler");
const build = require("../services/contextBuilder");
const parsers = require("../services/parsers");
const { expandGoalsToEvents } = require("../services/expander");
const prompts = require("../prompts");

function createV1Router({ callClaude }) {
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
    const payload = build.buildInterpret({ now: c.now, text, scheduleText, freeSlots, prefs: c.prefs });
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
    const freeSlots = scheduler.freeSlots({
      durationMinutes: 30,
      windowStart: period.start,
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
    const dinnerSlots = scheduler.dinnerSlots({ now: c.now, events: c.events, prefs: c.prefs });
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

  return router;
}

module.exports = { createV1Router };
