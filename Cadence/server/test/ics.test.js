/**
 * POST /v1/calendar/ics — fixture ICS strings, injected fake fetch, zero
 * network, deterministic window/zone (calendar-import.md §6). Covers: a UTC
 * event, a TZID event, an all-day event, a weekly RRULE with an EXDATE and a
 * RECURRENCE-ID override, a floating event, and a folded long SUMMARY line.
 *
 * The service must be server-zone independent — run the suite under a few
 * different TZ values to check (e.g. TZ=UTC npm test).
 */

const test = require("node:test");
const assert = require("node:assert/strict");
const { createApp } = require("../app");

/** Boot the app with a fake fetch; Claude must never be called on this route. */
function boot(fetchImpl) {
  let claudeCalls = 0;
  const app = createApp({
    callClaude: async () => { claudeCalls++; return "{}"; },
    fetchImpl,
  });
  const server = app.listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  const post = async (body) => {
    const res = await fetch(`${base}/v1/calendar/ics`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    return { status: res.status, body: await res.json() };
  };
  return { post, close: () => server.close(), claudeCalls: () => claudeCalls };
}

const icsResponse = (text) =>
  new Response(text, { status: 200, headers: { "content-type": "text/calendar" } });

// RFC 5545 requires CRLF line endings; the folded SUMMARY continuation line
// (leading space, split mid-word) is part of the fixture.
const FEED = [
  "BEGIN:VCALENDAR",
  "VERSION:2.0",
  "PRODID:-//cadence-test//EN",
  "X-WR-CALNAME:Uni Timetable",
  "BEGIN:VEVENT",
  "UID:utc-1@test",
  "SUMMARY:UTC standup",
  "DTSTART:20260710T170000Z",
  "DTEND:20260710T180000Z",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:lecture@uni.edu",
  "SUMMARY:Algorithms lecture",
  "DTSTART;TZID=Europe/Bucharest:20260708T100000",
  "DTEND;TZID=Europe/Bucharest:20260708T120000",
  "RRULE:FREQ=WEEKLY;BYDAY=WE",
  "EXDATE;TZID=Europe/Bucharest:20260715T100000",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:lecture@uni.edu",
  "RECURRENCE-ID;TZID=Europe/Bucharest:20260722T100000",
  "SUMMARY:Algorithms lecture (moved)",
  "DTSTART;TZID=Europe/Bucharest:20260722T140000",
  "DTEND;TZID=Europe/Bucharest:20260722T160000",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:allday-1@test",
  "SUMMARY:Conference day",
  "DTSTART;VALUE=DATE:20260715",
  "DTEND;VALUE=DATE:20260716",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:fold-1@test",
  "SUMMARY:Extremely long floating dinner title that RFC 5545 folds acro",
  " ss multiple physical lines",
  "DTSTART:20260711T190000",
  "DTEND:20260711T200000",
  "END:VEVENT",
  "END:VCALENDAR",
  "",
].join("\r\n");

const BASE_REQ = {
  url: "https://uni.example.edu/timetable.ics",
  now: "2026-07-07T09:00:00+03:00",
  timezone: "Europe/Bucharest",
  windowStart: "2026-07-07",
  windowEnd: "2026-08-04",
};

test("expands a mixed feed: UTC, TZID RRULE+EXDATE+override, all-day, floating, folded SUMMARY", async () => {
  let fetchedUrl;
  const { post, close, claudeCalls } = boot(async (url) => {
    fetchedUrl = url;
    return icsResponse(FEED);
  });
  try {
    const { status, body } = await post(BASE_REQ);
    assert.equal(status, 200);
    assert.equal(body.feedName, "Uni Timetable");
    assert.equal(fetchedUrl, BASE_REQ.url);
    assert.equal(claudeCalls(), 0); // deterministic endpoint — no AI call

    assert.deepEqual(body.events, [
      { title: "Algorithms lecture",
        start: "2026-07-08T10:00:00+03:00", end: "2026-07-08T12:00:00+03:00",
        allDay: false, externalIdentifier: "lecture@uni.edu#2026-07-08T10:00:00+03:00" },
      { title: "UTC standup",
        start: "2026-07-10T20:00:00+03:00", end: "2026-07-10T21:00:00+03:00",
        allDay: false, externalIdentifier: "utc-1@test" },
      // Floating time = interpreted in the device zone; SUMMARY unfolded.
      { title: "Extremely long floating dinner title that RFC 5545 folds across multiple physical lines",
        start: "2026-07-11T19:00:00+03:00", end: "2026-07-11T20:00:00+03:00",
        allDay: false, externalIdentifier: "fold-1@test" },
      { title: "Conference day",
        start: "2026-07-15T00:00:00+03:00", end: "2026-07-16T00:00:00+03:00",
        allDay: true, externalIdentifier: "allday-1@test" },
      // Jul 15 lecture is EXDATE'd; Jul 22 is overridden — moved to 14:00 but
      // keyed by its ORIGINAL occurrence time so re-syncs update in place.
      { title: "Algorithms lecture (moved)",
        start: "2026-07-22T14:00:00+03:00", end: "2026-07-22T16:00:00+03:00",
        allDay: false, externalIdentifier: "lecture@uni.edu#2026-07-22T10:00:00+03:00" },
      { title: "Algorithms lecture",
        start: "2026-07-29T10:00:00+03:00", end: "2026-07-29T12:00:00+03:00",
        allDay: false, externalIdentifier: "lecture@uni.edu#2026-07-29T10:00:00+03:00" },
    ]);
  } finally { close(); }
});

test("re-importing the same feed yields identical events (stable externalIdentifiers)", async () => {
  const { post, close } = boot(async () => icsResponse(FEED));
  try {
    const first = await post(BASE_REQ);
    const second = await post(BASE_REQ);
    assert.equal(first.status, 200);
    assert.deepEqual(second.body, first.body); // client dedupe relies on this
  } finally { close(); }
});

test("RRULE expansion is bounded by the window — an unbounded DAILY rule doesn't run away", async () => {
  const daily = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "BEGIN:VEVENT",
    "UID:daily-1@test",
    "SUMMARY:Morning run",
    "DTSTART;TZID=Europe/Bucharest:20260101T070000",
    "DTEND;TZID=Europe/Bucharest:20260101T073000",
    "RRULE:FREQ=DAILY", // no UNTIL, no COUNT — infinite
    "END:VEVENT",
    "END:VCALENDAR",
    "",
  ].join("\r\n");
  const { post, close } = boot(async () => icsResponse(daily));
  try {
    const { status, body } = await post({ ...BASE_REQ, windowStart: "2026-07-07", windowEnd: "2026-07-13" });
    assert.equal(status, 200);
    assert.equal(body.events.length, 7); // Jul 7..13 inclusive, nothing more
    assert.equal(body.events[0].start, "2026-07-07T07:00:00+03:00");
    assert.equal(body.events[6].start, "2026-07-13T07:00:00+03:00");
    assert.equal(body.feedName, null); // no X-WR-CALNAME
  } finally { close(); }
});

test("events outside the window are excluded; a webcal:// url is normalised to https", async () => {
  let fetchedUrl;
  const { post, close } = boot(async (url) => {
    fetchedUrl = url;
    return icsResponse(FEED);
  });
  try {
    const { status, body } = await post({
      ...BASE_REQ,
      url: "webcal://uni.example.edu/timetable.ics",
      windowStart: "2026-07-09",
      windowEnd: "2026-07-10",
    });
    assert.equal(status, 200);
    assert.equal(fetchedUrl, "https://uni.example.edu/timetable.ics");
    // Only the UTC standup (Jul 10 20:00 local) overlaps Jul 9–10.
    assert.deepEqual(body.events.map((e) => e.externalIdentifier), ["utc-1@test"]);
  } finally { close(); }
});

test("window longer than 90 days → 400 BAD_REQUEST", async () => {
  const { post, close } = boot(async () => icsResponse(FEED));
  try {
    const { status, body } = await post({ ...BASE_REQ, windowEnd: "2026-11-30" });
    assert.equal(status, 400);
    assert.equal(body.error.code, "BAD_REQUEST");
  } finally { close(); }
});

test("missing/invalid inputs → 400: no url, bad scheme, reversed window", async () => {
  const { post, close } = boot(async () => icsResponse(FEED));
  try {
    const noUrl = await post({ ...BASE_REQ, url: undefined });
    assert.equal(noUrl.status, 400);
    assert.equal(noUrl.body.error.code, "BAD_REQUEST");

    const badScheme = await post({ ...BASE_REQ, url: "ftp://example.com/cal.ics" });
    assert.equal(badScheme.status, 400);

    const reversed = await post({ ...BASE_REQ, windowStart: "2026-08-04", windowEnd: "2026-07-07" });
    assert.equal(reversed.status, 400);
  } finally { close(); }
});

test("unfetchable feed → 400; the secret URL never leaks into the error envelope", async () => {
  const SECRET = "https://calendar.google.com/private-abc123secret/basic.ics";
  const failing = boot(async () => { throw new TypeError("fetch failed"); });
  try {
    const { status, body } = await failing.post({ ...BASE_REQ, url: SECRET });
    assert.equal(status, 400);
    assert.equal(body.error.code, "BAD_REQUEST");
    assert.doesNotMatch(JSON.stringify(body), /abc123secret/);
  } finally { failing.close(); }

  const http500 = boot(async () => new Response("nope", { status: 500 }));
  try {
    const { status, body } = await http500.post({ ...BASE_REQ, url: SECRET });
    assert.equal(status, 400);
    assert.doesNotMatch(JSON.stringify(body), /abc123secret/);
  } finally { http500.close(); }
});

test("body that isn't an iCalendar feed → 400", async () => {
  const { post, close } = boot(async () => icsResponse("<html>calendar moved</html>"));
  try {
    const { status, body } = await post(BASE_REQ);
    assert.equal(status, 400);
    assert.equal(body.error.code, "BAD_REQUEST");
  } finally { close(); }
});

test("fetch timeout → 504 TIMEOUT envelope", async () => {
  const { post, close } = boot(async () => {
    throw new DOMException("The operation timed out.", "TimeoutError");
  });
  try {
    const { status, body } = await post(BASE_REQ);
    assert.equal(status, 504);
    assert.equal(body.error.code, "TIMEOUT");
  } finally { close(); }
});

test("RDATE adds an extra occurrence of a recurring event", async () => {
  const withRdate = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "BEGIN:VEVENT",
    "UID:rdate-1@test",
    "SUMMARY:Rehearsal",
    "DTSTART:20260708T170000Z",
    "DTEND:20260708T180000Z",
    "RRULE:FREQ=WEEKLY;COUNT=2",
    "RDATE:20260711T090000Z",
    "END:VEVENT",
    "END:VCALENDAR",
    "",
  ].join("\r\n");
  const { post, close } = boot(async () => icsResponse(withRdate));
  try {
    const { status, body } = await post(BASE_REQ);
    assert.equal(status, 200);
    assert.deepEqual(body.events.map((e) => e.start), [
      "2026-07-08T20:00:00+03:00", // rule #1
      "2026-07-11T12:00:00+03:00", // RDATE extra (09:00Z)
      "2026-07-15T20:00:00+03:00", // rule #2
    ]);
  } finally { close(); }
});

test("pathologically dense RRULE (FREQ=MINUTELY, unbounded) → 400, not a memory blowup", async () => {
  const dense = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "BEGIN:VEVENT",
    "UID:dense-1@test",
    "SUMMARY:Malicious metronome",
    "DTSTART:20260101T000000Z",
    "DTEND:20260101T000100Z",
    "RRULE:FREQ=MINUTELY", // ~135k occurrences over a 94-day expansion range
    "END:VEVENT",
    "END:VCALENDAR",
    "",
  ].join("\r\n");
  const { post, close } = boot(async () => icsResponse(dense));
  try {
    const { status, body } = await post(BASE_REQ);
    assert.equal(status, 400);
    assert.equal(body.error.code, "BAD_REQUEST");
  } finally { close(); }
});
