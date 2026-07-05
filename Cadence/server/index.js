/**
 * Entry point: `npm start`. Wires the real Anthropic client into the app
 * factory. The old single-file proxy remains available as `npm run start:legacy`
 * until Phase 2 (client rewiring) is complete.
 */

require("dotenv").config();
const Anthropic = require("@anthropic-ai/sdk");
const { createApp } = require("./app");
const { createClaudeCaller } = require("./lib/claude");

const apiKey = process.env.ANTHROPIC_API_KEY;
if (!apiKey) {
  console.error("ANTHROPIC_API_KEY is not set — check .env");
  process.exit(1);
}

const app = createApp({
  callClaude: createClaudeCaller({ apiKey }),
  anthropic: new Anthropic({ apiKey }),
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Cadence server (v1 + legacy /api) listening on port ${PORT}`));
