/**
 * Uniform error envelope (BACKEND_PLAN.md §3):
 *   { "error": { "code": "...", "message": "..." } }
 *
 * Codes: BAD_REQUEST (400) | AI_UNPARSEABLE (502) | AI_UPSTREAM (502)
 *      | TIMEOUT (504) | INTERNAL (500)
 */

class ApiError extends Error {
  constructor(code, message, status) {
    super(message);
    this.name = "ApiError";
    this.code = code;
    this.status = status;
  }
}

/** Thrown by parsers when model output doesn't match the contract.
 *  Triggers the retry-once rule; if the retry also fails, it is
 *  surfaced as AI_UNPARSEABLE. */
class ParseError extends Error {
  constructor(message) {
    super(message);
    this.name = "ParseError";
  }
}

const badRequest = (message) => new ApiError("BAD_REQUEST", message, 400);

/** Express error-handling middleware — every error leaves as the envelope. */
// eslint-disable-next-line no-unused-vars
function errorHandler(err, _req, res, _next) {
  if (err instanceof ApiError) {
    return res.status(err.status).json({ error: { code: err.code, message: err.message } });
  }
  if (err instanceof ParseError) {
    return res.status(502).json({
      error: { code: "AI_UNPARSEABLE", message: "The AI returned an unexpected response." },
    });
  }
  if (err?.type === "entity.parse.failed") {
    return res.status(400).json({ error: { code: "BAD_REQUEST", message: "Invalid JSON body." } });
  }
  console.error(err);
  return res.status(500).json({ error: { code: "INTERNAL", message: "Internal server error." } });
}

module.exports = { ApiError, ParseError, badRequest, errorHandler };
