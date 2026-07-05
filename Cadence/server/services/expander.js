/**
 * Shared goal/phase → concrete-events expander (ai-planner.md §7).
 * The building block BOTH /v1/schedule/generate and (later) the deep planner
 * use to turn goals or phases into scheduled events against free slots + prefs.
 * Written once so "generate" can exist in multiple surfaces without duplication.
 */

const prompts = require("../prompts");
const { callAndParse } = require("../lib/claude");
const { buildGenerate } = require("./contextBuilder");
const { parseGenerate } = require("./parsers");

/**
 * @param goals string — raw goals text, or pre-formatted phase lines from the
 *   deep planner (e.g. "Phase 1: Research (by 2026-08-01): subtask; subtask").
 * @returns { events: [{ title, start, end, category }] }
 */
async function expandGoalsToEvents(callClaude, { now, zone, period, goals, freeSlots, prefs }) {
  const payload = buildGenerate({ now, period, goals, freeSlots, prefs });
  return callAndParse(
    callClaude,
    { system: prompts.generate, payload },
    (text) => parseGenerate(text, { zone })
  );
}

module.exports = { expandGoalsToEvents };
