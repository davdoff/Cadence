/**
 * ICS feed import — deterministic fetch + RFC 5545 expansion for
 * POST /v1/calendar/ics (CADENCE_README §1.1a). No Claude call anywhere.
 *
 * Privacy rule: feed URLs routinely carry auth secrets in the URL itself
 * (Google's "secret address in iCal format"), so nothing in this file may
 * log a URL or embed one in an error message.
 *
 * Parsing is delegated to node-ical (container format, folding, VTIMEZONE)
 * and rrule (recurrence expansion). Three library quirks are compensated here:
 *   - Zoned/UTC times come back as real instants (with a `.tz` tag), but
 *     floating and all-day (VALUE=DATE) times are materialized at the
 *     SERVER's wall clock — those are rebuilt as the same wall time in the
 *     device zone, so results are server-zone independent (BACKEND_PLAN.md §5).
 *   - RDATE is left as a raw value string, parsed minimally below.
 *   - node-ical's TEXT unescape is a chain of replaceAll calls, which turns
 *     an escaped backslash followed by "n" (`a\\nb`) into a newline. LOCATION
 *     and DESCRIPTION are therefore kept raw and unescaped by `unescapeText`.
 */

const ical = require("node-ical");
const { ApiError, badRequest } = require("../lib/errors");
const { DateTime, toISO } = require("../lib/time");

const FETCH_TIMEOUT_MS = 15_000;
const MAX_FEED_BYTES = 10 * 1024 * 1024;

/** webcal:// → https://, and only http(s) beyond that. */
function normalizeFeedURL(raw) {
  let url;
  try {
    url = new URL(raw.replace(/^webcal:\/\//i, "https://"));
  } catch {
    throw badRequest('"url" is not a valid URL');
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw badRequest('"url" must be an http(s) or webcal link');
  }
  return url.toString();
}

/** GET the feed body. Follows redirects; tolerates mislabelled Content-Type. */
async function fetchFeed(rawUrl, fetchImpl = globalThis.fetch) {
  const url = normalizeFeedURL(rawUrl);
  let res;
  try {
    res = await fetchImpl(url, {
      redirect: "follow",
      headers: { accept: "text/calendar, text/plain;q=0.9, */*;q=0.8" },
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
  } catch (err) {
    if (err?.name === "TimeoutError" || err?.name === "AbortError") {
      throw new ApiError("TIMEOUT", "Fetching the calendar feed timed out.", 504);
    }
    throw badRequest("Could not fetch the calendar feed.");
  }
  if (!res.ok) throw badRequest(`Could not fetch the calendar feed (HTTP ${res.status}).`);
  const text = await res.text();
  if (text.length > MAX_FEED_BYTES) throw badRequest("The calendar feed is too large.");
  if (!/BEGIN:VCALENDAR/i.test(text)) throw badRequest("The URL did not return an iCalendar feed.");
  return text;
}

/**
 * RFC 5545 §3.3.11 TEXT unescape in ONE left-to-right scan: `\n`/`\N` →
 * newline, `\,` → `,`, `\;` → `;`, `\\` → `\`. Chained replaces break on
 * `a\\nb`, which must come out as a literal backslash then "n". A lone or
 * unknown escape keeps its backslash rather than silently dropping it.
 */
function unescapeText(raw) {
  let out = "";
  for (let i = 0; i < raw.length; i++) {
    const c = raw[i];
    if (c !== "\\" || i === raw.length - 1) {
      out += c;
      continue;
    }
    const next = raw[i + 1];
    if (next === "n" || next === "N") out += "\n";
    else if (next === "," || next === ";" || next === "\\") out += next;
    else {
      out += c;
      continue;
    }
    i++;
  }
  return out;
}

/** Unescaped + trimmed; null when nothing is left (blank fields carry no info). */
function sourceText(raw) {
  if (typeof raw !== "string") return null;
  const s = unescapeText(raw).trim();
  return s.length > 0 ? s : null;
}

/**
 * node-ical with LOCATION/DESCRIPTION stored raw (still escaped) under their
 * own keys, so `sourceText` does the unescape correctly. node-ical has
 * already unfolded the line and split off the parameters by then (quoted
 * params like ALTREP="cid:..." included), so `value` is just the text. First
 * occurrence wins. X-ALT-DESC (the HTML description) is a different
 * property and never lands here. The override is a private handler table
 * on a parser object of our own — the library's shared table is untouched.
 */
const keepRaw = (key) => (value, _params, curr) => {
  if (curr[key] === undefined) curr[key] = value;
  return curr;
};
const icsParser = {
  ...ical,
  objectHandlers: {
    ...ical.objectHandlers,
    LOCATION: keepRaw("locationRaw"),
    DESCRIPTION: keepRaw("descriptionRaw"),
  },
};

/** node-ical text values are sometimes `{ params, val }` objects. */
function textValue(v, fallback) {
  const s = typeof v === "object" && v !== null ? v.val : v;
  return typeof s === "string" && s.trim().length > 0 ? s.trim() : fallback;
}

/**
 * node-ical Date → zone-aware DateTime in the device zone.
 * `isInstant` = the Date is a real point in time (zoned/UTC input); otherwise
 * it holds server-local wall time (floating/all-day) and the same wall time
 * is rebuilt in the device zone.
 */
function toZoned(date, zone, isInstant = Boolean(date.tz)) {
  if (isInstant) return DateTime.fromJSDate(date).setZone(zone);
  return DateTime.fromObject(
    {
      year: date.getFullYear(),
      month: date.getMonth() + 1,
      day: date.getDate(),
      hour: date.getHours(),
      minute: date.getMinutes(),
      second: date.getSeconds(),
    },
    { zone }
  );
}

/**
 * RDATE support (node-ical keeps only the raw value string): the common
 * datetime forms — Z-suffixed UTC, or wall time in the event's zone
 * (falling back to the device zone for floating values). Unparseable
 * tokens are skipped rather than failing the whole feed.
 */
function parseRDates(ev, zone) {
  const raws = ev.rdate == null ? [] : Array.isArray(ev.rdate) ? ev.rdate : [ev.rdate];
  const out = [];
  for (const raw of raws) {
    if (typeof raw !== "string") continue;
    for (const tok of raw.split(",")) {
      const m = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$/.exec(tok.trim());
      if (!m) continue;
      const parts = { year: +m[1], month: +m[2], day: +m[3], hour: +m[4], minute: +m[5], second: +m[6] };
      const dt = DateTime.fromObject(parts, { zone: m[7] ? "utc" : ev.start.tz ?? zone });
      if (dt.isValid) out.push(dt.setZone(zone));
    }
  }
  return out;
}

/** Expand one VEVENT (single or recurring) into concrete instances overlapping the window. */
function expandEvent(ev, { windowStart, windowEnd, zone }) {
  if (!(ev.start instanceof Date)) return [];
  if (ev.status === "CANCELLED") return [];

  const uid = textValue(ev.uid, null);
  const title = textValue(ev.summary, "Untitled");
  // Source-owned display details (CADENCE_README §1.1b), local-only on the
  // device. An override without its own value falls back to the master's,
  // the same way the title does.
  const location = sourceText(ev.locationRaw);
  const notes = sourceText(ev.descriptionRaw);
  const allDay = ev.datetype === "date";
  const start = toZoned(ev.start, zone);
  let end = ev.end instanceof Date ? toZoned(ev.end, zone) : start;
  if (allDay && end <= start) end = start.plus({ days: 1 });
  const externalId = uid ?? `${title}#${toISO(start)}`;
  const overlaps = (s, e) => e > windowStart && s < windowEnd;

  if (!ev.rrule) {
    return overlaps(start, end)
      ? [{ title, location, notes, start, end, allDay, externalIdentifier: externalId, seriesIdentifier: null }]
      : [];
  }

  // Every expanded occurrence of this VEVENT shares the unsuffixed base id,
  // so the client can group them as one recurring series.
  const seriesIdentifier = externalId;

  // Recurring. Expansion is bounded by the window only — a FREQ=DAILY rule
  // with no UNTIL/COUNT is infinite. rrule returns real instants when the
  // rule is zoned, and server-local wall times when it is floating — same
  // split as toZoned, keyed off the master DTSTART's tz.
  const durationMs = end.toMillis() - start.toMillis();
  const isInstant = Boolean(ev.start.tz);
  // ±2-day slack absorbs the wall-time-vs-instant mismatch for floating
  // rules; the precise overlap filter below trims it back.
  // rrule-temporal hard-caps expansion at 10k iterations and throws a plain
  // Error past it — hourly over ~94 days is only ~2.3k, so hitting the cap
  // means a pathological rule (FREQ=SECONDLY/MINUTELY): answer 400, not 500.
  let raw;
  try {
    raw = ev.rrule.between(
      windowStart.minus({ days: 2 }).toJSDate(),
      windowEnd.plus({ days: 2 }).toJSDate(),
      true
    );
  } catch {
    throw badRequest("A recurring event in this feed repeats too densely to import.");
  }

  // EXDATE values and RECURRENCE-ID keys share the occurrences' representation,
  // so cancellation/override matching happens on raw epoch ms, pre-conversion.
  const exdates = new Set(Object.values(ev.exdate ?? {}).map((d) => d.getTime()));
  const overrides = new Map();
  for (const ov of Object.values(ev.recurrences ?? {})) {
    if (ov?.recurrenceid instanceof Date) overrides.set(ov.recurrenceid.getTime(), ov);
  }

  const instances = [];
  const pushOverride = (ov, occStart) => {
    if (ov.status === "CANCELLED" || !(ov.start instanceof Date)) return;
    const s = toZoned(ov.start, zone);
    const e = ov.end instanceof Date ? toZoned(ov.end, zone) : s;
    if (!overlaps(s, e)) return;
    instances.push({
      title: textValue(ov.summary, title),
      location: sourceText(ov.locationRaw) ?? location,
      notes: sourceText(ov.descriptionRaw) ?? notes,
      start: s,
      end: e,
      allDay: ov.datetype === "date",
      // Keyed by the ORIGINAL occurrence time (the RECURRENCE-ID), so the
      // identifier stays stable across syncs even when the instance moves.
      externalIdentifier: `${externalId}#${toISO(occStart)}`,
      seriesIdentifier,
    });
  };

  const seen = new Set();
  for (const occ of raw) {
    const t = occ.getTime();
    if (seen.has(t)) continue;
    seen.add(t);
    if (exdates.has(t)) continue;
    const occStart = toZoned(occ, zone, isInstant);
    const override = overrides.get(t);
    if (override) {
      pushOverride(override, occStart);
      continue;
    }
    const occEnd = occStart.plus(durationMs);
    if (overlaps(occStart, occEnd)) {
      instances.push({
        title,
        location,
        notes,
        start: occStart,
        end: occEnd,
        allDay,
        externalIdentifier: `${externalId}#${toISO(occStart)}`,
        seriesIdentifier,
      });
    }
  }

  // Overrides whose original occurrence fell outside the expanded range but
  // whose NEW time lands inside the window (an instance moved into view).
  for (const [t, ov] of overrides) {
    if (seen.has(t)) continue;
    const origStart = toZoned(ov.recurrenceid, zone, Boolean(ov.recurrenceid.tz) || isInstant);
    pushOverride(ov, origStart);
  }

  // RDATE extras — plain additional occurrences of the master.
  const have = new Set(instances.map((i) => i.start.toMillis()));
  for (const dt of parseRDates(ev, zone)) {
    if (have.has(dt.toMillis())) continue;
    const e = dt.plus(durationMs);
    if (overlaps(dt, e)) {
      instances.push({
        title,
        location,
        notes,
        start: dt,
        end: e,
        allDay,
        externalIdentifier: `${externalId}#${toISO(dt)}`,
        seriesIdentifier,
      });
    }
  }

  return instances;
}

/** Whole feed → { events: [DTO], feedName } within [windowStart, windowEnd]. */
function expandFeed(icsText, { windowStart, windowEnd, zone }) {
  let data;
  try {
    data = icsParser.parseLines(icsText.split(/\r?\n/));
  } catch {
    throw badRequest("The feed could not be parsed as iCalendar.");
  }

  const instances = [];
  for (const item of Object.values(data)) {
    // Standalone RECURRENCE-ID entries are reachable via the master's
    // `recurrences`; skip them at the top level.
    if (item?.type !== "VEVENT" || item.recurrenceid) continue;
    instances.push(...expandEvent(item, { windowStart, windowEnd, zone }));
  }
  instances.sort(
    (a, b) =>
      a.start.toMillis() - b.start.toMillis() ||
      a.externalIdentifier.localeCompare(b.externalIdentifier)
  );

  const calName = textValue(data.vcalendar?.["WR-CALNAME"], null);
  return {
    events: instances.map((e) => ({
      title: e.title,
      location: e.location,
      notes: e.notes,
      start: toISO(e.start),
      end: toISO(e.end),
      allDay: e.allDay,
      externalIdentifier: e.externalIdentifier,
      seriesIdentifier: e.seriesIdentifier,
    })),
    feedName: calName,
  };
}

module.exports = { fetchFeed, expandFeed, normalizeFeedURL, unescapeText };
