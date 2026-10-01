# Day Templates — Feature Idea

## Concept
Reusable day layouts ("Busy work day", "Sporty day", "Focused study day") that the user can stamp onto any date instead of recreating or regenerating the same events.

- **Applying a template is fully local** — no API call, zero cost.
- **AI is only used to create a template** from a description — one call per template, not per use.

## User flows
1. **Save today as a template** — take an existing day's events and store them as a template.
2. **Build a template manually** — add blocks (title, start time, duration, category).
3. **Generate a template with AI** — describe the day in words; Claude returns the blocks; user reviews and saves.
4. **Apply a template** — pick a template + a date (or several dates); events are created on those days.

## Data model
Store blocks as **relative times**, not absolute dates, so the template can land on any day.

```swift
DayTemplate
- id: UUID
- name: String              // "Sporty day"
- symbolName: String?       // optional icon
- blocks: [TemplateBlock]
- createdBy: TemplateSource // .manual, .savedFromDay, .ai
- lastUsedDate: Date?

TemplateBlock
- id: UUID
- title: String
- startMinuteOfDay: Int     // 0–1439, e.g. 7:30 → 450
- durationMinutes: Int
- categoryName: String      // matched to an existing Category by name on apply
```

## Applying a template (local logic)
1. For each block, compute `startTime = date + startMinuteOfDay`, `endTime = startTime + duration`.
2. Run the existing conflict check against that day's events.
3. Conflicts: show the user which blocks clash and let them skip, keep, or shift each — no silent overwrite.
4. Create events with `source: .manual` (or a new `.template` source if you want to track it in reports).
5. Schedule notifications as for any other event, then call `WidgetSync.refresh()`.

Open question: should meal events from the daily pass be treated as movable when a template is applied, or block it like any other event?

## AI endpoint — template generation
New route: `POST /api/template/generate` with its own system prompt.

New intent:
```swift
case createDayTemplate(description: String)
```

Payload (compact, no schedule needed — a template isn't tied to a date):
```
INTENT: create_day_template
DESCRIPTION: "focused study day, gym in the evening, early start"
CATEGORIES: Work, Study, Gym, Meal, Personal
PREFS: BufferBetweenEvents=15min, WorkHours=9-18
```

Expected response (strict JSON):
```json
{
  "name": "Focused Study Day",
  "blocks": [
    { "title": "Deep study", "start": "08:00", "durationMinutes": 120, "category": "Study" },
    { "title": "Review notes", "start": "10:30", "durationMinutes": 60, "category": "Study" },
    { "title": "Gym", "start": "18:00", "durationMinutes": 75, "category": "Gym" }
  ]
}
```

- The result opens in the template editor for review before saving — never saved blindly.
- Unknown categories: map to an existing one or prompt the user to create it.
- Output is small (one day), so `max_tokens` isn't a concern here.

## Why this helps costs
- Common days get reused instead of regenerated — fewer "generate week" calls.
- A week plan could even be assembled from templates locally (Mon = Work day, Sat = Sporty day…) with no AI at all.

## Possible later additions
- **Week templates** — a template per weekday, applied in one tap.
- Suggest a template when the user keeps creating the same set of events.
- Show the template's blocks as a mini timeline preview before applying.
