/**
 * Model-output parsers + validation — the server-side home of what used to be
 * the parsing half of Cadence/Services/AIService.swift. Every parser throws
 * ParseError on contract violations, which triggers the retry-once rule and,
 * if that fails too, surfaces as AI_UNPARSEABLE. Clients only ever see the
 * validated, typed shapes from BACKEND_PLAN.md / ai-planner.md.
 */

const { ParseError } = require("../lib/errors");
const { DateTime, normalizeModelISO, toISO, parseHHMM, dayAbbr } = require("../lib/time");

const fail = (msg) => { throw new ParseError(msg); };

function parseJSON(text) {
  try {
    return JSON.parse(text);
  } catch {
    fail("Model output is not valid JSON");
  }
}

/** ISO from the model → normalized ISO string in the request zone, or throw. */
function isoOrFail(value, zone, field) {
  const dt = normalizeModelISO(value, zone);
  if (!dt) fail(`Invalid or missing ISO date in "${field}"`);
  return toISO(dt);
}

const str = (value, field) => (typeof value === "string" && value.length > 0 ? value : fail(`Missing string "${field}"`));

function parseAlternatives(raw, zone) {
  if (raw == null) return [];
  if (!Array.isArray(raw)) fail("alternatives must be an array");
  return raw.map((a) => ({
    start: isoOrFail(a?.start, zone, "alternatives.start"),
    end: isoOrFail(a?.end, zone, "alternatives.end"),
  }));
}

function parseEventDraft(raw, zone) {
  return {
    title: str(raw?.title, "event.title"),
    start: isoOrFail(raw?.start, zone, "event.start"),
    end: isoOrFail(raw?.end, zone, "event.end"),
    category: str(raw?.category, "event.category"),
  };
}

// MARK: SchedulingDecision — /v1/schedule/add | move | reschedule
// (mirror of AIService.parseResponse; conflict_reason → camelCase)

function parseDecision(text, { zone }) {
  const raw = parseJSON(text);
  switch (raw.action) {
    case "add":
      if (!raw.event) fail("add decision without event");
      return {
        action: "add",
        event: parseEventDraft(raw.event, zone),
        conflictReason: null,
        alternatives: parseAlternatives(raw.alternatives, zone),
      };
    case "conflict":
      return {
        action: "conflict",
        event: raw.event ? parseEventDraft(raw.event, zone) : null,
        conflictReason: raw.conflict_reason ?? "",
        alternatives: parseAlternatives(raw.alternatives, zone),
      };
    case "suggest_alternative":
      return {
        action: "suggest_alternative",
        event: null,
        conflictReason: null,
        alternatives: parseAlternatives(raw.alternatives, zone),
      };
    default:
      fail(`Unknown decision action "${raw.action}"`);
  }
}

// MARK: Interpret union — /v1/schedule/interpret (ai-planner.md §3–§4)
// idMap translates the prompt's short tokens (E1..En) back to real event UUIDs.

function mapEventId(token, idMap) {
  const id = idMap[token];
  if (!id) fail(`Model referenced unknown event id "${token}"`);
  return id;
}

function parseInterpret(text, { zone, idMap }) {
  const raw = parseJSON(text);
  const intent = str(raw.intent, "intent");
  const interpretation = str(raw.interpretation, "interpretation");
  const p = raw.payload ?? {};

  switch (intent) {
    case "add":
      return {
        intent, interpretation,
        event: p.event ? parseEventDraft(p.event, zone) : null,
        conflictReason: p.conflictReason ?? null,
        alternatives: parseAlternatives(p.alternatives, zone),
      };
    case "move":
      return {
        intent, interpretation,
        targetEventId: mapEventId(str(p.targetEventId, "targetEventId"), idMap),
        newStart: isoOrFail(p.newStart, zone, "newStart"),
        newEnd: isoOrFail(p.newEnd, zone, "newEnd"),
        alternatives: parseAlternatives(p.alternatives, zone),
      };
    case "reschedule":
      return {
        intent, interpretation,
        targetEventId: mapEventId(str(p.targetEventId, "targetEventId"), idMap),
        newStart: isoOrFail(p.newStart, zone, "newStart"),
        newEnd: isoOrFail(p.newEnd, zone, "newEnd"),
      };
    case "reorganize": {
      if (!Array.isArray(p.moves) || p.moves.length === 0) fail("reorganize without moves");
      return {
        intent, interpretation,
        moves: p.moves.map((m) => ({
          targetEventId: mapEventId(str(m?.targetEventId, "moves.targetEventId"), idMap),
          newStart: isoOrFail(m?.newStart, zone, "moves.newStart"),
          newEnd: isoOrFail(m?.newEnd, zone, "moves.newEnd"),
        })),
        displaced: (p.displaced ?? []).map((t) => mapEventId(str(t, "displaced[]"), idMap)),
      };
    }
    case "generate": {
      if (!Array.isArray(p.events) || p.events.length === 0) fail("generate without events");
      return { intent, interpretation, events: p.events.map((e) => parseEventDraft(e, zone)) };
    }
    case "clarify":
      return {
        intent, interpretation,
        question: str(p.question, "question"),
        options: Array.isArray(p.options) ? p.options.filter((o) => typeof o === "string") : [],
      };
    default:
      fail(`Unknown intent "${intent}"`);
  }
}

// MARK: Generate — /v1/schedule/generate (also the expander's output shape)

function parseGenerate(text, { zone }) {
  const raw = parseJSON(text);
  if (!Array.isArray(raw.events) || raw.events.length === 0) fail("generate response without events");
  return { events: raw.events.map((e) => parseEventDraft(e, zone)) };
}

// MARK: Meal suggestions — /v1/meal/suggestions
// (mirror of AIService.parseMealSuggestions + parseSlot: resolve "WED 20:00"
// within the 7 days starting at `now`, clamp the end to the dinner window.)

function resolveSlot(slot, now, zone) {
  const parts = (slot ?? "").split(" ");
  if (parts.length !== 2) return null;
  const [dayToken, timeToken] = parts;
  let hm;
  try {
    hm = parseHHMM(timeToken, "scheduledSlot");
  } catch {
    return null;
  }
  for (let offset = 0; offset < 7; offset++) {
    const day = now.startOf("day").plus({ days: offset });
    if (dayAbbr(day) === dayToken.toUpperCase()) {
      return day.set({ hour: hm.hour, minute: hm.minute, second: 0, millisecond: 0 });
    }
  }
  return null;
}

function parseMealSuggestions(text, { zone, now, prefs }) {
  const raw = parseJSON(text);
  if (!Array.isArray(raw.meals)) fail("meal response without meals array");
  const winEnd = parseHHMM(prefs.dinnerWindow.end, "dinnerWindow.end");

  // Entries with an unparseable slot are dropped rather than failing the batch.
  const suggestions = raw.meals.flatMap((entry) => {
    const start = resolveSlot(entry?.scheduledSlot, now, zone);
    if (!start || typeof entry?.name !== "string") return [];
    const prep = Number.isInteger(entry.prepTimeMinutes) && entry.prepTimeMinutes > 0 ? entry.prepTimeMinutes : 45;
    const windowEnd = start.set({ hour: winEnd.hour, minute: winEnd.minute, second: 0, millisecond: 0 });
    const end = DateTime.min(start.plus({ minutes: prep }), windowEnd);
    return [{
      name: entry.name,
      prepTimeMinutes: prep,
      tags: Array.isArray(entry.tags) ? entry.tags.filter((t) => typeof t === "string") : [],
      start: toISO(start),
      end: toISO(end),
    }];
  });

  if (suggestions.length === 0) fail("no parseable meal suggestions");
  return { suggestions };
}

// MARK: Project plan — /v1/project/plan (mirror of AIService.parseProjectPlan)

function parseProjectPlan(text) {
  const raw = parseJSON(text);
  if (!Array.isArray(raw.phases) || raw.phases.length === 0) fail("plan response without phases");
  return {
    phases: raw.phases.map((phase) => ({
      title: str(phase?.title, "phase.title"),
      subtasks: Array.isArray(phase?.subtasks) ? phase.subtasks.filter((s) => typeof s === "string") : [],
      targetDate: /^\d{4}-\d{2}-\d{2}$/.test(phase?.targetDate ?? "") ? phase.targetDate : null,
    })),
  };
}

module.exports = { parseDecision, parseInterpret, parseGenerate, parseMealSuggestions, parseProjectPlan };
