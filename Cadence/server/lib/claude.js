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

const MODEL = "claude-sonnet-4-6"; // default: the fast "secretary box" routes
const MAX_TOKENS = 2048; // reorganize/generate payloads are larger than the old 1024

// Deep planner (deep-planner-plan.md): quality-over-price. Opus + adaptive thinking
// + high effort is the one place plan quality compounds. budget_tokens is removed
// on Opus 4.8 (400s); adaptive thinking is OFF unless set explicitly.
const OPUS = "claude-opus-4-8";

/** Strip markdown code fences Claude sometimes wraps JSON responses in. */
const stripFences = (text) =>
  text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();

/** First non-empty text block. With thinking on, content[0] is a thinking block
 *  (empty text under the default display), so we can't assume index 0. */
const firstText = (response) =>
  (response.content ?? []).find((b) => b?.type === "text" && typeof b.text === "string" && b.text.length > 0)?.text;

function createClaudeCaller({ apiKey, model = MODEL, maxTokens = MAX_TOKENS } = {}) {
  const anthropic = new Anthropic({ apiKey });

  // Per-call overrides let one injected caller serve both the cheap secretary
  // routes and the Opus deep-planner routes (deep-planner-plan.md). Tests inject a
  // fake that ignores the extra options — the contract stays { system, payload }.
  return async function callClaude({ system, payload, model: modelOverride, maxTokens: maxTokensOverride, thinking = false, effort } = {}) {
    const params = {
      model: modelOverride ?? model,
      max_tokens: maxTokensOverride ?? maxTokens,
      system,
      messages: [{ role: "user", content: payload }],
    };
    if (thinking) params.thinking = { type: "adaptive" };
    if (effort) params.output_config = { effort };

    let response;
    try {
      response = await anthropic.messages.create(params);
    } catch (err) {
      if (err instanceof Anthropic.APIConnectionTimeoutError) {
        throw new ApiError("TIMEOUT", "The AI request timed out.", 504);
      }
      console.error("Claude upstream error:", err?.status ?? "", err?.message ?? err);
      throw new ApiError("AI_UPSTREAM", "AI request failed.", 502);
    }
    const text = firstText(response);
    if (!text) throw new ApiError("AI_UPSTREAM", "Empty model response.", 502);
    return stripFences(text);
  };
}

/**
 * Call Claude and parse; on ParseError, retry the identical call once.
 * A second ParseError propagates and the error handler maps it to AI_UNPARSEABLE.
 */
async function callAndParse(callClaude, opts, parse) {
  const first = await callClaude(opts);
  try {
    return parse(first);
  } catch (err) {
    if (!(err instanceof ParseError)) throw err;
  }
  const second = await callClaude(opts);
  return parse(second);
}

module.exports = { createClaudeCaller, callAndParse, stripFences, MODEL, OPUS };
