# UI Review — 2026-07-10

Scope: all 18 files in `Cadence/Views/`, `ContentView.swift`, and
`Extensions/Color+Hex.swift`. This is the first dedicated pass over the view
layer (previous reviews only covered the calendar-import hunks). Server,
services, and the widget target were **not** reviewed here — widgets are the
natural follow-up since they share the color system.

Ranked by severity within each section. `⚠` = will crash or lose data.

> **Implementation status (2026-07-10, same-day session):**
> **Done** — §1.1, §1.2, §1.3, §1.4, §1.5, §1.8; §3.1 (Theme env +
> `Extensions/Theme.swift`), §3.5 (`.cardStyle()`), unused color statics
> deleted; §5 gradient rollout (buttons, selected pills, page backgrounds,
> progress bars/rings, card wash); §2: tap-through to EventDetailView
> (Today + Schedule), Schedule-tab `+` with selected day, EventDetailView
> edit button, habit-delete confirmation, ScheduleView "Today" hidden when
> redundant, TodayView FAB via `safeAreaInset`; §4 week-strip LazyHStack +
> precomputed event-day Set.
> **Still open** — §1.6, §1.7; §2: habit editing, undo Done/Missed,
> EventDetailView delete, notifications OS-denial state, AI keyboard focus;
> §3.2–3.4, §3.6–3.10 (dedup + service extractions + tests); rest of §4;
> §6 accessibility batch; widget gradient pass.

---

## 1. Bugs

### ⚠ 1.1 AddEventView crashes when end time is before start time
`AddEventView.swift:108` builds `DateInterval(start: combinedStart, end: combinedEnd)`
with no validation. `DateInterval` **traps** ("duration cannot be negative")
when end < start, so picking an end time earlier than the start time and
tapping Save crashes the app. Nothing in the form prevents this — the two
time pickers are independent.

**Fix:** disable Save (or clamp/show inline error) while `combinedEnd <= combinedStart`,
like FoodPreferencesView already does for the dinner window
(`FoodPreferencesView.swift:100`). Side effect of the current design: events
crossing midnight can't be created at all — decide if that's intended.

### ⚠ 1.2 MissedEventsView "Reschedule" deletes the event before the user commits
`MissedEventsView.swift:113-122`: `reschedule()` tombstones and **deletes the
event immediately**, then opens `AddEventView` prefilled with only the title.
Two problems:
- If the user cancels the sheet, the event is permanently gone (and, for
  imported events, tombstoned so sync won't bring it back).
- Category and duration are silently dropped — only the title survives.

**Fix:** pass the whole event (or a draft with title/category/duration) into
the sheet and delete the original only in the sheet's save path.

### 1.3 Meal-suggestion quota is burned even when the request fails
`WeeklyMealsView.swift:421`: `p.recordMealSuggestionFetch()` runs **before**
the `await AIService().suggestMealOptions(...)` call. A network error still
consumes one of the two daily attempts. Record the fetch after success
(the server round-trip is the thing being rationed, but a failed call gave
the user nothing).

### 1.4 AI slot buttons title events with the raw prompt text
`AIInputView.swift:199` and `:213` build `EventDraft(title: description, …)` —
the **entire typed request** ("find me 2h for taxes this week") becomes the
event title on the schedule. The server already returns `draft.title`; use it
and fall back to `description` only when empty (like `insertDrafts` does).

### 1.5 The linear progress bar in WeeklyMealsView can never appear
`WeeklyMealsView.swift:489-492`: `runDailyPass()` is synchronous; `isRunningPass`
flips to `true` and back to `false` inside one call, so the top overlay
(`WeeklyMealsView.swift:49`) never renders. Either drop the state + overlay,
or make the pass genuinely async.

### 1.6 Missed-tray badge and "Missed" filter disagree
`TodayView.swift:59` counts **all-time** missed + displaced events for the
badge, but the Missed filter pill (`TodayView.swift:48`) shows only **today's**
missed. Badge says 5, tapping the filter shows nothing — confusing. Decide on
one scope; the badge's tray (MissedEventsView) is all-time, so the badge is
arguably right and the filter pill could just navigate there instead.

### 1.7 Deleting a category has no confirmation and can break "Meal"
`CategorySettingsView.swift:24-28`: swipe-delete removes a category instantly.
Events keep a `nil` category (fine), but deleting or renaming **Meal** silently
breaks meal scheduling, and renaming any category breaks habit auto-tracking —
both are joined **by name string** (`WeeklyMealsView.swift:385`,
`TodayView.swift:281`, `ContentView.swift:74`). Minimum: confirmation dialog +
protect/lock the built-in Meal category. Longer term: join by `Category.id`.

### 1.8 Settings sliders silently discard changes
`SettingsView.swift:160-172`: scheduling prefs only persist via the explicit
"Save scheduling settings" button; switching tabs discards silently. Every
other prefs screen autosaves `onChange` (FoodPreferences, per-category
alerts). Make Settings autosave too and delete the button — one less thing
to explain.

---

## 2. UX gaps (todo list)

- [x] **Event rows aren't tappable.** `EventDetailView` is only reachable from
  the dinner slot in WeeklyMealsView (`WeeklyMealsView.swift:268` is its sole
  call site). On Today and Schedule you can swipe and edit-pencil, but you
  can't open an event. Wrap `EventRowView` usages in a NavigationLink.
- [x] **No way to add an event from the Schedule tab** — the FAB only exists on
  Today, and `AddEventView` always defaults to `.now` rather than the selected
  day. Add a toolbar `+` that passes `selectedDate` in.
- [ ] **Habits can't be edited** — `AddHabitView` has no editing mode and
  `HabitDetailView` has no edit/delete. Renaming, changing goals, or fixing
  the linked category requires delete + recreate (losing all history).
- [x] **Habit delete has no confirmation** (`HabitsView.swift:206`) — one tap in
  a context menu destroys the full history.
- [ ] **No undo for Done/Missed.** Marking an event completed/missed
  (`TodayView.swift:194-203`, EventDetailView buttons) is one-way; a mis-swipe
  can't be reverted anywhere in the UI. Add a "Mark as pending" action on
  EventDetailView, or swipe actions on completed rows.
- [ ] **EventDetailView has no edit or delete** — it's read-only + status
  buttons. At minimum add the edit sheet already used by ScheduleView.
  *(Partially done: edit pencil → AddEventView sheet added; delete still missing.)*
- [ ] **Notifications toggle doesn't reflect OS-level denial**
  (`SettingsView.swift:102-106`): if the user declined the system prompt, the
  toggle stays on and everything looks enabled. Check
  `UNUserNotificationCenter` status and show the "open Settings" path like
  CalendarImportView does for calendars.
- [ ] **AI input keyboard friction** (`AIInputView.swift`): no `@FocusState` —
  the field isn't focused when the sheet opens, and tapping an example chip
  fills the text but doesn't focus/submit. Small, but it's the flagship
  interaction.
- [x] **ScheduleView "Today" button** shows even when today is selected — hide
  or disable it then.
- [x] **TodayView FAB overlap** is handled with a hard-coded
  `.padding(.bottom, 90)` (`TodayView.swift:183`); use
  `.safeAreaInset(edge: .bottom)` so the list scrolls clear of the buttons on
  all devices.

---

## 3. Structure & duplication (the "solid codebase before the planner" list)

These are the ones that pay off before deep-planner work starts, since the
planner UI will re-use all of these patterns.

1. **Theme plumbing is the biggest smell — and it blocks the gradient goal.**
   Every view re-declares `@AppStorage("accentColorHex")` (19 times) and calls
   `Color.appAccent(accentColorHex)` etc. (~100 call sites). Introduce a small
   `Theme` value injected via `.environment(\.theme, …)` from ContentView:
   `theme.accent`, `theme.background`, `theme.deep`, `theme.accentGradient`,
   `theme.cardSurface`. One definition point is also exactly what the gradient
   migration needs (§5). The five `cadenceOrange`/`cadenceCream` statics in
   `Color+Hex.swift:49-53` are now unused — delete them.

2. **`mark(_ event:, _ status:)` is duplicated** in `TodayView.swift:276` and
   `EventDetailView.swift:131` — habit auto-increment + nudge scheduling is
   decision logic living in two views (CLAUDE.md says: extract). Pull into a
   service (e.g. `EventStatusService.mark(event:status:habits:)`) — this is
   also code that gets hand-ported to Kotlin later.

3. **The notification-scheduling ritual is copy-pasted 4×**
   (`AddEventView.swift:131-137` and `:158-164`, `AIInputView.swift:531-538`,
   plus the meal variant). One `NotificationService.scheduleAll(for:prefs:)`
   entry point.

4. **The daily meal pass ritual is copy-pasted 3×** (`ContentView.swift:69`,
   `WeeklyMealsView.swift:489`, `FoodPreferencesView.swift:251`) — each site
   repeats delete/insert/save/WidgetSync with slightly different guards. Give
   `MealPlanningCoordinator` an `apply(to context:)` entry point and keep the
   once-per-day guard in one place. (Same shape as the tombstone-delete
   finding already logged in REVIEW_LOG.md — that one is still open too.)

5. **Card styling is repeated ~30×** with drifting values: white background,
   corner radius 12/14/16/18/22, shadow opacity 0.03/0.04/0.05/0.08. Extract
   `.cardStyle()` (and maybe `.cardStyle(.prominent)`) as a ViewModifier.
   This is also the single hook you'll want for gradient card surfaces.

6. **Pill/chip buttons re-implemented 5×** (TodayView filter pills,
   ScheduleView category chips, HabitsView filter, GeneratePlanSheet quick
   ranges, AIInputView example chips). One `SelectablePill(label:icon:isSelected:color:)`
   component.

7. **Empty states re-implemented 5×** (Today, Habits, Overview, Missed,
   WeeklyMeals) — same icon-in-tinted-circle + headline + caption layout.
   Extract `EmptyStateView(icon:title:message:action:)`.

8. **Hard-coded `DateFormatter` with `"h:mm a"`** in `EventRowView.swift:9`,
   `EventDetailView.swift:11/17`, `AIInputView.swift:549`, `TodayView.swift:300` —
   ignores the user's 24-hour clock setting and allocates a formatter per
   render (they're expensive). Use `Date.FormatStyle`
   (`.formatted(date:…time:.shortened)`) which is locale-aware and cached, or
   static formatters.

9. **OverviewView stats are pure computation inside the View**
   (`OverviewView.swift:53-129`: category stats, perfect days, daily chart
   data). CLAUDE.md flags exactly this — extract an `OverviewStatsService`
   (pure functions: `[Event] -> Stats`), unit-test it, port it to Kotlin later.
   Same for TodayView's time-bucketing and WeeklyMealsView's slot resolution
   (`breakfast/dinner` by title matching at `WeeklyMealsView.swift:96-97` is
   fragile — a meal named "Breakfast burrito bowl" would land in the breakfast
   slot).

10. **Test coverage note:** `CadenceTests/` covers services only — after
    extracting 2, 4, and 9 above, those become directly testable, which is the
    realistic way to get UI-logic coverage without UI tests.

---

## 4. Performance

- **ScheduleView week strip builds 181 day pills eagerly**
  (`ScheduleView.swift:83-107`): plain `HStack` in a ScrollView, and each pill
  filters `allEvents` to compute its dot (`ScheduleView.swift:118`) — O(181×N)
  per body evaluation, re-run on every event change. Use `LazyHStack`, and
  precompute one `Set<Date>` of days-with-events per body pass.
- **TodayView/OverviewView filter `allEvents` repeatedly per render** — fine at
  current data sizes, but Overview recomputes `perfectDaysThisPeriod` with a
  30-day × N scan multiple times per body. Falls out naturally when §3.9's
  service computes stats once.
- `@Query private var allEvents` (unscoped, sorted) appears in 8 views; as the
  event table grows (calendar import!), consider date-bounded `#Predicate`
  queries per screen.

---

## 5. Gradient / texture direction

Current state: flat fills everywhere except three `LinearGradient`s
(Overview ring `OverviewView.swift:189`, Habits summary ring
`HabitsView.swift:99`, chart bars in HabitDetail/Overview). The accent system
already produces light/dark endpoints (`accentLight`, `appAccent`,
`accentDark` in `Color+Hex.swift`), so the palette is gradient-ready.

Suggested approach — **do §3.1 (Theme) and §3.5 (cardStyle) first**, then the
gradient rollout is ~1 line per surface instead of 100 edits:

```swift
struct Theme {
    let accentHex: String
    var accent: Color { Color(hex: accentHex) }
    // The one gradient definition every filled control uses:
    var accentGradient: LinearGradient {
        LinearGradient(colors: [.accentLight(accentHex), .appAccent(accentHex), .accentDark(accentHex)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    // Subtle wash for page backgrounds instead of the flat tint:
    var backgroundGradient: LinearGradient {
        LinearGradient(colors: [.appBackground(accentHex), .appDeep(accentHex).opacity(0.6)],
                       startPoint: .top, endPoint: .bottom)
    }
}
```

Rollout order (most visible first, all currently flat `Color.appAccent` /
`Color.white` fills):

1. **Filled buttons**: Today FAB (`TodayView.swift:266`), confirm buttons
   (`AIInputView.swift:373`), empty-state CTAs, Settings save row →
   `theme.accentGradient`.
2. **Selected pills/chips** (filter pills, category chips, day pill) — gradient
   on the selected state only; unselected stays flat.
3. **Page backgrounds**: swap `Color.appBackground(...).ignoresSafeArea()`
   (13 views) for `theme.backgroundGradient` — this alone kills most of the
   "plain color" feel.
4. **Progress bars** (dayStatsBar, habit daily/weekly bars, category bars) —
   fill with the gradient like the rings already do; instantly consistent.
5. **Cards last, and subtle**: a barely-tinted `white → appBackground` vertical
   gradient in `.cardStyle()`. Strong gradients on cards will fight the
   colored content inside them.

Two cautions: gradient text/small icons hurt legibility — keep text on flat
color; and the widgets mirror the accent via `WidgetSync.mirrorAccent`
(`SettingsView.swift:188`), so once the app goes gradient, do a matching pass
in `CadenceWidget/` or the widgets will look like the old app.

---

## 6. Accessibility & polish (batch these)

- Icon-only buttons need `.accessibilityLabel`: missed-events tray
  (`TodayView.swift:116`), habit +/− steppers, edit pencil
  (`EventRowView.swift:33`), compact-toggle (`HabitsView.swift:71`).
- Many hand-set tiny fonts (`.system(size: 9/10/11)`) won't scale with Dynamic
  Type — prefer `.caption2` etc.; audit at the largest accessibility size.
- `.preferredColorScheme(.light)` (`ContentView.swift:44`) is a deliberate
  lock, but hard-coded `Color.white` cards (~50 uses) make dark mode a rewrite
  later — routing them through `theme.cardSurface` now (§3.1/§3.5) keeps the
  door open for free.
- Swipe-to-complete works on events scheduled in the future ("Missed" a 9pm
  event at 8am) — consider gating status swipes on `startTime <= .now`.

---

## 7. Suggested order of attack

1. Crash + data-loss fixes: §1.1, §1.2 (small, urgent).
2. Theme + cardStyle extraction (§3.1, §3.5) — unblocks gradients.
3. Gradient rollout (§5), most visible payoff.
4. Tap-through to EventDetailView + Schedule-tab add button (§2) — the two
   biggest daily-use gaps.
5. mark()/notification/meal-pass dedup + OverviewStats extraction (§3.2–3.4,
   §3.9) with unit tests — the "solid base before the planner" work.
6. Remaining §1 fixes and §2 todos as filler tasks.
