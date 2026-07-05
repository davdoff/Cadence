/**
 * Timezone-aware date helpers (luxon).
 *
 * Rule (BACKEND_PLAN.md §5): planning always happens in the DEVICE's timezone,
 * carried on every request as `timezone`. The server never uses its own clock
 * or zone — serverless functions run in arbitrary regions.
 *
 * All ISO output carries the UTC offset (e.g. +03:00), never `Z`, matching the
 * parsing rules the iOS client already uses.
 */

const { DateTime } = require("luxon");
const { badRequest } = require("./errors");

/** Parse a required ISO string in the request zone. Throws BAD_REQUEST if invalid. */
function parseISO(value, zone, field) {
  const dt = DateTime.fromISO(value, { zone });
  if (!dt.isValid) throw badRequest(`Invalid ISO8601 date in "${field}": ${value}`);
  return dt;
}

/** Validate an ISO string coming back FROM the model; normalize to the request zone.
 *  Returns null (not an HTTP error) when invalid — callers decide whether that's fatal. */
function normalizeModelISO(value, zone) {
  if (typeof value !== "string") return null;
  const dt = DateTime.fromISO(value, { setZone: true });
  return dt.isValid ? dt.setZone(zone) : null;
}

/** ISO with offset, no milliseconds: 2026-07-05T14:30:00+03:00 */
const toISO = (dt) => dt.toISO({ suppressMilliseconds: true });

/** "19:30" → { hour: 19, minute: 30 }. Throws BAD_REQUEST on garbage. */
function parseHHMM(value, field) {
  const m = /^(\d{1,2}):(\d{2})$/.exec(value ?? "");
  if (!m) throw badRequest(`Invalid HH:MM in "${field}": ${value}`);
  return { hour: Number(m[1]), minute: Number(m[2]) };
}

// Formatting helpers — en-US locale so day abbreviations match the prompts
// ("MON".."SUN"), independent of server locale.
const dayAbbr = (dt) => dt.setLocale("en-US").toFormat("EEE").toUpperCase();
const hhmm = (dt) => dt.toFormat("HH:mm");
const ymd = (dt) => dt.toFormat("yyyy-MM-dd");

module.exports = { DateTime, parseISO, normalizeModelISO, toISO, parseHHMM, dayAbbr, hhmm, ymd };
