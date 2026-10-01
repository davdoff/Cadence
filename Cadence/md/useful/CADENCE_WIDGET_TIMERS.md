# Quick Timer Widget

A standalone home-screen widget with 5 tappable presets ("5m", "10m", "15m",
"20m", "30m" by default). Tap one and it starts a **real system alarm** — on
iOS 26+ it rings through Silent Mode and Focus, takes over the Lock Screen, and
has to be dismissed. No connection to `Event`, `Habit`, `Meal`, or any other app
data. Built for David's own use, not a user-facing app feature.

## How it works

- **Widget** (`CadenceWidget/QuickTimerWidget.swift`): a `systemMedium` widget,
  kind `"QuickTimer"`. Idle state shows 5 preset buttons; running state shows a
  live countdown (`Text(timerInterval:)`) and a Cancel button.
- **Scheduler** (`Cadence/Models/Shared/QuickTimerScheduler.swift`): the whole
  alarm mechanism, behind a small `QuickTimerScheduling` protocol with two
  implementations — `AlarmKitTimerScheduler` (iOS 26+, a genuine alarm) and
  `NotificationTimerScheduler` (below 26, an ordinary local notification). The
  `QuickTimer` facade is the single place the version branch lives, so the rest
  of the feature never checks the OS version.
- **Intents** (`Cadence/Models/Shared/QuickTimerIntents.swift`): `Start`,
  `Cancel`, and `QuickTimerStopped`. All three are **`LiveActivityIntent`, not
  plain `AppIntent`** — see the note below.
- **Alarm UI** (`CadenceWidget/QuickTimerAlarmActivity.swift`): the Lock Screen
  / Dynamic Island / StandBy countdown, an `ActivityConfiguration` over
  `AlarmAttributes<QuickTimerMetadata>`. AlarmKit **requires** this to exist.
- **Shared state** (`Cadence/Models/Shared/TimerSettingsStore.swift`): the 5
  preset durations, the active alarm's id, and a mirrored end-date, in the App
  Group `UserDefaults` suite (`AppGroup.defaults`) the widget already uses for
  the accent colour. The end-date is only a display cache for the home-screen
  widget's own countdown — AlarmKit owns the real alarm.
- **Settings screen** (`Cadence/Views/QuickTimerSettingsView.swift`): reachable
  from Settings → "Quick Timer" → "Edit timer presets". Each slot opens a sheet
  with `CountdownDurationPicker`, a thin `UIViewRepresentable` around
  `UIDatePicker(.countDownTimer)` — the hour/minute wheel iOS's own Clock app
  uses. It also requests alarm permission on first open.

### Why the intents are `LiveActivityIntent`

A plain `AppIntent` fired from a widget button runs in the **widget extension**
process. AlarmKit's authorization and its `NSAlarmKitUsageDescription` belong to
the **app**, so scheduling from the extension is unreliable. `LiveActivityIntent`
runs `perform()` in the app process instead. `Models/Shared/StopEventIntent.swift`
already relies on the same trick, and AlarmKit corroborates it — its `stopIntent`
parameter is typed `(any LiveActivityIntent)?`.

The consequence: those files must be in **both** targets, because the app needs
the definition in order to execute `perform()`, and the widget needs it to build
the button.

### Setup requirements

- **`NSAlarmKitUsageDescription` in `Cadence/Info.plist`** — mandatory. If it's
  missing or empty, no permission prompt appears and scheduling fails *silently*.
  That symptom (no prompt at all) almost always means this key got lost.
- **Deployment target stays 18.5.** AlarmKit is gated behind
  `if #available(iOS 26, *)` plus `#if canImport(AlarmKit)`, so nothing else in
  Cadence is affected.

### Caveats worth knowing

- **Below iOS 26 it's just a notification** — it respects Silent Mode and Focus,
  so it can finish without a sound. The settings footer says so on-device.
- **The Simulator can't demonstrate the Silent Mode override.** Testing the
  actual point of this feature needs a real iOS 26 device.
- **The countdown survives killing the app** — it's a scheduled system alarm plus
  a stored end-date, not a live process.

## How to safely remove it

Nothing outside these files references the feature, so deleting is
straightforward:

1. Delete these files:
   - `CadenceWidget/QuickTimerWidget.swift`
   - `CadenceWidget/QuickTimerAlarmActivity.swift`
   - `Cadence/Models/Shared/QuickTimerScheduler.swift`
   - `Cadence/Models/Shared/QuickTimerIntents.swift`
   - `Cadence/Models/Shared/TimerSettingsStore.swift`
   - `Cadence/Views/QuickTimerSettingsView.swift`
   - `CADENCE_WIDGET_TIMERS.md` (this file)
2. In `CadenceWidget/CadenceWidgetBundle.swift`, remove the `QuickTimerWidget()`
   line and the `if #available(iOS 26.0, *) { QuickTimerAlarmActivity() }` block.
3. In `Cadence/Views/SettingsView.swift`, remove the `Section("Quick Timer")`
   block.
4. In `Cadence/Info.plist`, remove `NSAlarmKitUsageDescription`.
5. In `CADENCE_README.md`, remove the "Quick Timer (standalone, personal
   utility)" subsection under *App Architecture*.
6. If you'd previously added the widget to a home screen, iOS will show it as
   unavailable until you remove it manually (long-press → Remove Widget).

No SwiftData model changes were made, no migrations to worry about, and no other
service (`WidgetSync`, `AIService`, notifications for events, etc.) calls into
any of the above — it's fully isolated.
