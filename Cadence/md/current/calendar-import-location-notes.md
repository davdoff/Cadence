## Location & Notes on Imported Events

### Problem
Events imported from Apple Calendar (EventKit) and ICS feeds lose their **location** and **notes**. Uni classes arrive without room and building, so the user has to open Apple Calendar to find out where to go.

### Why it happens
The source data is there. `Event` has no fields for it, so the importers have nowhere to put it and silently drop it.

---

### 1. Data model

Add two optional properties to `Event`:

```swift
var location: String?   // room / building / address — shown as-is
var notes: String?      // free text from the source calendar
```

- Both are optional with a `nil` default, so SwiftData handles this as a lightweight migration. Existing events load with `nil`.
- If the project already uses `VersionedSchema` + `SchemaMigrationPlan`, add a new schema version with a lightweight stage instead of editing the current one.
- `Event` lives in the shared App Group store, so the change must compile in **both** the app and `CadenceWidget` targets.
- Update the `Event` entry in the Data Models section of `CADENCE_README.md`.

---

### 2. Mapping

| Source | `location` | `notes` |
|---|---|---|
| EventKit (`EKEvent`) | `location` | `notes` |
| ICS feed | `LOCATION` | `DESCRIPTION` |

Rules for both paths:
- **EventKit:** use `EKEvent.location`, not `structuredLocation?.title`. The plain string is the full text Apple Calendar displays; the structured title can be shorter or missing the room.
- Trim whitespace and newlines, and store `nil` when the result is empty.
- No length cap in storage. Long notes are truncated only in the UI.

ICS-specific rules:
- **Unfold lines first.** A line that starts with a space or tab continues the previous line. Check whether the parser already does this; if not, fix it before reading values.
- **Ignore property parameters.** Read the value after the first colon that isn't inside quotes. For example, `LOCATION;LANGUAGE=en:Room 1` gives `Room 1`, and `DESCRIPTION;ALTREP="cid:...":Text` gives `Text`.
- **Unescape TEXT values** (RFC 5545):
  - `\n` or `\N` becomes a newline
  - `\,` becomes `,`
  - `\;` becomes `;`
  - `\\` becomes `\`
- **Do the unescaping in a single left-to-right scan.** Chained `replacingOccurrences` calls break on an escaped backslash followed by `n`: input `a\\nb` must become `a\nb` (a literal backslash, then `n`), not a newline.
- **Ignore `X-ALT-DESC`** (the HTML version of the description) and use `DESCRIPTION` only.

---

### 3. Re-sync behaviour

- On re-sync, when an event matches by `externalIdentifier` + `importSourceID`, **always refresh `location` and `notes` from the source**. These two fields are source-owned.
- Write only when a value actually changed, to avoid pointless saves and widget reloads.
- When something did change, save and then call `WidgetSync.refresh()`.
- This backfills events that were imported before this change. The next sync fills in their location and notes, so no separate migration step is needed.
- **Don't change the existing re-sync behaviour for any other field** (title, times, status, category). That's a separate decision (see Open question).

---

### 4. Event detail view

**Location row**
- Use the `mappin.and.ellipse` SF Symbol and the location text, with text selection enabled.
- Tapping opens Apple Maps via `https://maps.apple.com/?q=<percent-encoded location>`.
- Hide the row when `location` is `nil`.

**Notes section**
- Place it below the existing details.
- Show 6 lines by default with a "Show more" toggle.
- Enable text selection.
- Optional: detect URLs (e.g. Canvas/Zoom links) with `NSDataDetector` and make them tappable.
- Hide the section when `notes` is `nil`.

For imported events, location and notes are **read-only** in this change: they are displayed but not editable. This keeps re-sync from overwriting user edits.

---

### 5. Widget (recommended)

- Add `location: String?` to `EventSnapshot` and populate it in `CadenceWidget/WidgetDataStore.swift`.
- **Next Events, rectangular lock-screen accessory:** show the second line as `HH:mm · location`, with `.lineLimit(1)` and truncation.
- **Next Events, small:** show the location under each event's time, if it fits.
- Leave the other widgets unchanged.
- **Notes never go into widget snapshots.**

---

### 6. AI payloads

There are no changes. `location` and `notes` are local-only and are never added to `SchedulingContextBuilder` output or the compressed schedule format. Notes can contain personal details such as lecturer names and private links.

---

### 7. Tests (XCTest)

**ICS unescape**
- `Room 2A-04\, Main Building` gives `Room 2A-04, Main Building`.
- `Line1\nLine2` gives two lines.
- `a\\nb` gives a literal backslash followed by `n`, with no newline.

**ICS parsing**
- A folded `DESCRIPTION` spanning 3 physical lines parses into one value.
- `LOCATION;LANGUAGE=en:Room 1` gives `Room 1`.
- An empty or whitespace-only `LOCATION` gives `nil`.

**EventKit mapping**
- A blank `notes` string gives `nil`.

**Re-sync**
- An imported event with `location == nil` gets its location after sync.
- `status` and `category` stay unchanged.
- No duplicate event is created.
- A sync with no source changes performs no save.

---

### Acceptance criteria
- [ ] A uni class imported from Apple Calendar shows room and building in the event detail view.
- [ ] Events imported before this change gain location and notes on the next sync, without duplicates.
- [ ] The lock-screen Next Events widget shows the location for the next event.
- [ ] Notes and location never appear in any proxy request payload.
- [ ] CI is green: SwiftLint, unit tests, and builds for both the app and widget targets.

### Out of scope
- Editing location or notes in the Add/Edit form (including adding a location to manual events)
- Geocoding, travel time, or "leave now" alerts
- Structured location coordinates, attendees, or the event URL field

### Open question
Should re-sync also overwrite the **title or times** of an imported event that the user has edited in-app?
- If the source wins, the user loses their edits.
- If the user wins, the user misses timetable changes.

Decide this before touching those fields. This spec deliberately leaves them as they are.
