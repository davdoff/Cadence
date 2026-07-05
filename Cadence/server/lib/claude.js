/**
 * Claude access. Two layers:
 *  - createClaudeCaller(...) → callClaude({ system, payload }) → cleaned text.
 *    This is the ONLY interface the /v1 services see, and it's injectable so
 *    tests never hit the network (same trick as `_callAPI` in the Swift client).
 *  - callAndParse(...) — the retry-once rule (BACKEND_PLAN.md §3): one retry on
 *    unparseable model output before surfacing AI_UNPARSEABLE.
 */

const Anthropic = require("@anthropic-ai/sdk");
const { ApiError, ParseError } = require("./errors");

const MODEL = "claude-sonnet-4-6";
const MAX_TOKENS = 2048; // reorganize/generate payloads are larger than the old 1024

/** Strip markdown code fences Claude sometimes wraps JSON responses in. */
const stripFences = (text) =>
  text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();

function createClaudeCaller({ apiKey, model = MODEL, maxTokens = MAX_TOKENS } = {}) {
  const anthropic = new Anthropic({ apiKey });

  return async function callClaude({ system, payload }) {
    let response;
    try {
      response = await anthropic.messages.create({
        model,
        max_tokens: maxTokens,
        system,
        messages: [{ role: "user", content: payload }],
      });
    } catch (err) {
      if (err instanceof Anthropic.APIConnectionTimeoutError) {
        throw new ApiError("TIMEOUT", "The AI request timed out.", 504);
      }
      console.error("Claude upstream error:", err?.status ?? "", err?.message ?? err);
      throw new ApiError("AI_UPSTREAM", "AI request failed.", 502);
    }
    const text = response.content?.[0]?.text;
    if (!text) throw new ApiError("AI_UPSTREAM", "Empty model response.", 502);
    return stripFences(text);
  };
}

/**
 * Call Claude and parse; on ParseError, retry the identical call once.
 * A second ParseError propagates and the error handler maps it to AI_UNPARSEABLE.
 */
async function callAndParse(callClaude, { system, payload }, parse) {
  const first = await callClaude({ system, payload });
  try {
    return parse(first);
  } catch (err) {
    if (!(err instanceof ParseError)) throw err;
  }
  const second = await callClaude({ system, payload });
  return parse(second);
}

module.exports = { createClaudeCaller, callAndParse, stripFences, MODEL };
