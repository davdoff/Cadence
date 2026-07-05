/**
 * Legacy /api/* passthrough — byte-compatible with the old root server.js so
 * the currently shipped iOS build keeps working during the Phase 2 migration
 * (BACKEND_PLAN.md: "Keep old /api/* routes alive during migration").
 * Delete this file once the client is fully on /v1.
 */

const express = require("express");
const { stripFences, MODEL } = require("../lib/claude");

function createLegacyRouter({ anthropic }) {
  const router = express.Router();

  async function callClaude(req, res) {
    try {
      const { systemPrompt, userPayload } = req.body;
      const response = await anthropic.messages.create({
        model: MODEL,
        max_tokens: 1024,
        system: systemPrompt,
        messages: [{ role: "user", content: userPayload }],
      });
      if (response.content[0]?.text) {
        response.content[0].text = stripFences(response.content[0].text);
      }
      res.status(200).json(response);
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: "AI request failed" });
    }
  }

  router.post("/schedule/add", callClaude);
  router.post("/schedule/move", callClaude);
  router.post("/schedule/reschedule", callClaude);
  router.post("/habit/analysis", callClaude);
  router.post("/meal/suggestion", callClaude);
  router.post("/project/plan", callClaude);

  return router;
}

module.exports = { createLegacyRouter };
