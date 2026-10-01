/**
 * Claude access. Two layers:
 *  - createClaudeCaller(...) → callClaude({ system, payload }) → cleaned text.
 *    This is the ONLY interface the /v1 services see, and it's injectable so
 *    tests never hit the network (same trick as `_callAPI` in the Swift client).
 *  - callAndParse(...) — the retry-once rule (BACKEND_PLAN.md §3): one retry on
 *    unparseable model output before surfacing AI_UNPARSEABLE.
 *
 * `system` stays a plain string across that interface; the cache breakpoint is
 * applied here, in the one place that talks to the SDK (prompt-caching-plan.md).
 */

const Anthropic = require("@anthropic-ai/sdk");
const { ApiError, ParseError } = require("./errors");

const MODEL = "claude-sonnet-5-5"; // default: the fast "secretary box" routes
// max_tokens caps thinking + answer together, and every route thinks now, so the
// ceiling needs room for both. Output bills by tokens actually produced, so a
// high ceiling costs nothing unused; 16k stays inside the SDK's non-streaming
// timeout. A hit is still caught below as AI_TRUNCATED.
const MAX_TOKENS = 16000;

// Secretary routes think, but briefly: adaptive thinking at low effort is the
// smarter-answers-for-a-small-cost setting. Routes that need more pass their own
// effort (generate: "medium"; the Opus deep planner: "high"). Sonnet 5.5 can't
// turn thinking off with {type:"disabled"} anyway (a 400), so it is always on.
const DEFAULT_EFFORT = "low";

// Deep planner (deep-planner-plan.md): quality-over-price. Opus + adaptive thinking
// + high effort is the one place plan quality compounds. budget_tokens is removed
// on the Opus 5 family; adaptive thinking is ON by default on Opus 5, and we set it
// explicitly anyway so the intent is readable.
const OPUS = "claude-opus-5";

/** Strip markdown code fences Claude sometimes wraps JSON responses in. */
const stripFences = (text) =>
  text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();

/** First non-empty text block. With thinking on, content[0] is a thinking block
 *  (empty text under the default display), so we can't assume index 0. */
const firstText = (response) =>
  (response.content ?? []).find((b) => b?.type === "text" && typeof b.text === "string" && b.text.length > 0)?.text;

/**
 * One line per call, so caching can actually be verified instead of assumed
 * (prompt-caching-plan.md §"Verifying it works"). The fields that matter:
 *   cache_write > 0 → this call created the entry, cache_read > 0 → it hit one,
 *   both 0 → the prefix is under the model's minimum, or something changed it.
 * `stop` is here for the other half of that doc: stop=max_tokens is the signature
 * of a truncated generation, which no amount of retrying will fix.
 */
function logUsage(model, response) {
  const u = response.usage ?? {};
  console.log(
    `[claude] ${model} stop=${response.stop_reason}` +
    ` in=${u.input_tokens ?? 0} cache_write=${u.cache_creation_input_tokens ?? 0}` +
    ` cache_read=${u.cache_read_input_tokens ?? 0} out=${u.output_tokens ?? 0}`
  );
}

function createClaudeCaller({ apiKey, model = MODEL, maxTokens = MAX_TOKENS } = {}) {
  const anthropic = new Anthropic({ apiKey });

  // Per-call overrides let one injected caller serve both the cheap secretary
  // routes and the Opus deep-planner routes (deep-planner-plan.md). Tests inject a
  // fake that ignores the extra options — the contract stays { system, payload }.
  return async function callClaude({ system, payload, model: modelOverride, maxTokens: maxTokensOverride, effort = DEFAULT_EFFORT } = {}) {
    const params = {
      model: modelOverride ?? model,
      max_tokens: maxTokensOverride ?? maxTokens,
      // The one cache breakpoint. The system prompt is the longest byte-identical
      // span in the request and it is shared by every user of this server (caches
      // are scoped per workspace and we hold a single API key), so a hot prefix
      // needs no per-user warm-up. Everything volatile — NOW, schedule, free
      // slots, the request itself — is in `payload`, i.e. after the breakpoint.
      // A prompt below the model's minimum cacheable prefix simply doesn't cache:
      // no error, and no write premium either, so marking unconditionally is safe.
      system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
      messages: [{ role: "user", content: payload }],
      thinking: { type: "adaptive" },
      output_config: { effort },
    };

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
    logUsage(params.model, response);
    // Hitting the ceiling truncates the JSON mid-object, so the parse is doomed
    // and so is the identical retry. Fail loudly here instead of burning a second
    // call to arrive at a misleading AI_UNPARSEABLE.
    if (response.stop_reason === "max_tokens") {
      throw new ApiError("AI_TRUNCATED", "The AI response was cut off before it finished.", 502);
    }
    const text = firstText(response);
    if (!text) throw new ApiError("AI_UPSTREAM", "Empty model response.", 502);
    return stripFences(text);
  };
}

/**
 * Call Claude and parse; on ParseError, retry the identical call once.
 * A second ParseError propagates and the error handler maps it to AI_UNPARSEABLE.
 * The retry re-sends byte-identical bytes, so it reads the cache the first call
 * wrote — the retry-once rule costs roughly a tenth of a fresh call.
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

module.exports = { createClaudeCaller, callAndParse, stripFences, MODEL, OPUS, DEFAULT_EFFORT };
