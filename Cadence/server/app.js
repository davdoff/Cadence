/**
 * Express app factory. `callClaude` is injectable so tests run the full
 * request→validate→prompt→parse→respond pipeline against a fake model with
 * zero network; `fetchImpl` is the same trick for /v1/calendar/ics feed
 * fetching (defaults to global fetch). `anthropic` is optional — when
 * present, the legacy /api/* passthrough is mounted for the shipped iOS build.
 */

const express = require("express");
const { errorHandler } = require("./lib/errors");
const { createV1Router } = require("./routes/v1");
const { createLegacyRouter } = require("./routes/legacy");

function createApp({ callClaude, anthropic = null, fetchImpl } = {}) {
  const app = express();
  app.use(express.json({ limit: "1mb" }));

  app.get("/health", (_req, res) => res.json({ status: "ok" })); // old health path, kept
  app.use("/v1", createV1Router({ callClaude, fetchImpl }));
  if (anthropic) app.use("/api", createLegacyRouter({ anthropic }));

  app.use(errorHandler);
  return app;
}

module.exports = { createApp };
