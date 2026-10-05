# Day Templates

Status: **v1 implemented** (day + week templates, local apply, no AI).
Shipped behaviour is described in `CADENCE_README.md` §2b; this doc keeps the
decisions and what's still open.

## Concept
Reusable day layouts ("Busy work day", "Sporty day", "Focused study day")
stamped onto any date instead of recreating or regenerating the same events.
Applying a template is fully local: no API call, zero cost.

## Decisions (v1)

**Where it lives.**
- Applying happens in the existing **Plan a period…** sheet (Ask AI), behind a
  *Goals (AI) | Templates* switch. Filling a period is the same job either way;
  templates are the free, deterministic way to do it.
- The library is managed in **Settings › Scheduling › Day templates**.
- "Save this day as a template" is **Copy from a day…** inside the template
  editor, so Today and Schedule didn't need new UI.

**Week templates.** A `WeekTemplate` is a weekday → day-template mapping. In
Templates mode the user picks a template per day, can fill the range from a
saved layout, or save the current picks as a new layout. Layouts point at day
templates by id, so deleting a day template leaves that weekday empty instead
of breaking the layout.

**Clashes — David's call: auto-shift, with a per-clash override.**
- By default the user's existing events stay put, and a clashing template
  block slides to the nearest free gap that day. On a tie it takes the later
  gap, so a shifted block never jumps ahead of the block before it.
- Each clash in the preview has a **"Move <event> instead"** toggle. With it
  on, the block keeps its template time and the existing event moves to the
  nearest gap to where it was.
- If the event has nowhere to go, it stays and the preview says so.
- Imported events get `locallyEditedTime` so re-sync keeps the move. Recurring
  events move this occurrence only.
- Meal events are treated like any other event (this answers the old open
  question).

**Gap rules.**
- **Buffer:** applies between template blocks and existing events, but not
  between two template blocks, because back-to-back blocks in a template are
  the user's intent.
- **Search window:** the whole day, not work hours, since templates hold evening
  gym and morning routines. Never before *now*.
- **Avoid-blocks:** ignored, because the template is an explicit layout.
- **Missed/displaced events:** don't block (same rule as
  `SchedulerService.conflicts`).
- **Nothing is dropped silently:** a block with no room is shown as skipped.

**Code shape.**
- `TemplatePlanner` is a pure service: values in, a `DayPlan` out, re-run on
  every toggle.
- `EventApplyService` holds the insert / move / notification / save helpers.
  They were extracted from `AIInputView` so templates and the Ask AI confirm
  cards write events the same way.
- Template events get `EventSource.template`.

## Data model
```swift
DayTemplate   { id, name, symbolName?, blocks: [TemplateBlock], createdAt, lastUsedDate? }
TemplateBlock { id, title, startMinuteOfDay (0–1439), durationMinutes, categoryName }
WeekTemplate  { id, name, assignments: [WeekdayAssignment] }
WeekdayAssignment { weekday (1 = Sun … 7 = Sat), templateID }
```
All properties have inline defaults, so adding the models is a lightweight
migration. Blocks match a category by name on apply; if the category no longer
exists, the event gets no category.

## Not built yet
- **AI template generation.** "Describe the day → blocks" would be one call per
  template, not per use. It would need a server route plus a prompt
  (`POST /v1/template/generate`, payload: description + categories + prefs, no
  schedule), and the result would open in the editor for review, never saved
  blindly.
- Suggesting a template when the user keeps creating the same set of events.
- A mini timeline preview of a template's blocks.
