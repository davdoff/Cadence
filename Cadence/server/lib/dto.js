/**
 * Request DTO validation — the BAD_REQUEST layer. Parses/normalizes the shared
 * request objects from BACKEND_PLAN.md §3 (base fields, EventSnapshot,
 * PrefsSnapshot) into zone-aware internal shapes before any planning runs.
 */

const { badRequest } = require("./errors");
const { DateTime, parseISO } = require("./time");

/** now + timezone — required on every planning request; device-provided. */
function parseBase(body) {
  if (typeof body?.timezone !== "string") throw badRequest('Missing "timezone"');
  const zone = body.timezone;
  if (!DateTime.local().setZone(zone).isValid) throw badRequest(`Unknown timezone "${zone}"`);
  if (typeof body?.now !== "string") throw badRequest('Missing "now"');
  const now = parseISO(body.now, zone, "now");
  return { now, zone };
}

/** PrefsSnapshot with defaults matching UserPreferences' Swift defaults. */
function parsePrefs(raw = {}) {
  const p = typeof raw === "object" && raw !== null ? raw : {};
  return {
    workStartHour: p.workStartHour ?? 9,
    workEndHour: p.workEndHour ?? 18,
    bufferMinutes: p.bufferMinutes ?? 15,
    priorityCategories: Array.isArray(p.priorityCategories) ? p.priorityCategories : [],
    aiLevel: p.aiLevel ?? "balanced",
    avoidScheduling: Array.isArray(p.avoidScheduling)
      ? p.avoidScheduling.map((a) => ({
          weekdays: Array.isArray(a?.weekdays) ? a.weekdays : [], // ISO 1=Mon..7=Sun
          start: a?.start ?? "00:00",
          end: a?.end ?? "00:00",
        }))
      : [],
    dinnerWindow: {
      start: p.dinnerWindow?.start ?? "19:00",
      end: p.dinnerWindow?.end ?? "21:30",
    },
    mealGuidance: typeof p.mealGuidance === "string" ? p.mealGuidance : "",
  };
}

/** One EventSnapshot → internal event. `id` is required by contract. */
function parseEvent(raw, zone, field = "event") {
  if (typeof raw !== "object" || raw === null) throw badRequest(`"${field}" must be an object`);
  if (typeof raw.id !== "string" || raw.id.length === 0) throw badRequest(`"${field}.id" is required`);
  if (typeof raw.title !== "string") throw badRequest(`"${field}.title" is required`);
  return {
    id: raw.id,
    title: raw.title,
    start: parseISO(raw.start, zone, `${field}.start`),
    end: parseISO(raw.end, zone, `${field}.end`),
    category: typeof raw.category === "string" ? raw.category : null,
    status: typeof raw.status === "string" ? raw.status : "pending",
  };
}

function parseEventList(raw, zone, field = "events") {
  if (raw == null) return [];
  if (!Array.isArray(raw)) throw badRequest(`"${field}" must be an array`);
  return raw.map((e, i) => parseEvent(e, zone, `${field}[${i}]`));
}

function requireString(body, field) {
  const v = body?.[field];
  if (typeof v !== "string" || v.trim().length === 0) throw badRequest(`Missing "${field}"`);
  return v;
}

module.exports = { parseBase, parsePrefs, parseEvent, parseEventList, requireString };
