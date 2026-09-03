import SwiftUI
import UIKit
import WidgetKit

// Standalone Quick Timer feature — see CADENCE_WIDGET_TIMERS.md.
// Not wired to Event/Habit/Meal data; safe to delete independently.

/// Wraps UIDatePicker's `.countDownTimer` mode — the same hour/minute wheel
/// iOS's own Clock app uses for entering a duration (as opposed to a
/// time-of-day picker). SwiftUI has no native equivalent.
struct CountdownDurationPicker: UIViewRepresentable {
    @Binding var duration: TimeInterval

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .countDownTimer
        picker.minuteInterval = 1
        picker.addTarget(context.coordinator,
                         action: #selector(Coordinator.changed(_:)),
                         for: .valueChanged)
        // UIDatePicker drops `countDownDuration` when it's assigned in the same
        // runloop pass that set `.countDownTimer` — a long-standing UIKit quirk
        // that otherwise leaves every slot showing 1:00. Defer it a pass.
        DispatchQueue.main.async { [duration] in
            picker.countDownDuration = duration
        }
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        if abs(uiView.countDownDuration - duration) > 0.5 {
            uiView.countDownDuration = duration
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        let parent: CountdownDurationPicker
        init(_ parent: CountdownDurationPicker) { self.parent = parent }

        @objc func changed(_ sender: UIDatePicker) {
            parent.duration = sender.countDownDuration
        }
    }
}

struct QuickTimerSettingsView: View {
    @Environment(\.theme) private var theme

    /// `sheet(item:)` rather than `sheet(isPresented:)` — the latter captures its
    /// content closure before the index is read, which can present a stale slot.
    private struct SlotSelection: Identifiable { let id: Int }

    @State private var slots: [TimeInterval] = TimerSettingsStore.defaultSlotsSeconds
    @State private var editing: SlotSelection?

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()
            List {
                Section {
                    ForEach(slots.indices, id: \.self) { i in
                        Button {
                            editing = SlotSelection(id: i)
                        } label: {
                            HStack {
                                Text("Slot \(i + 1)")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(TimerSettingsStore.durationLabel(slots[i]))
                                    .foregroundColor(theme.accent)
                            }
                        }
                    }
                } footer: {
                    Text(footerText)
                        .font(.caption)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Quick Timer")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(theme.background, for: .navigationBar)
        .onAppear { slots = TimerSettingsStore.slotsSeconds() }
        .task {
            // The alarm needs its own permission (AlarmKit on iOS 26+, otherwise
            // notifications), so the feature stays usable even if event
            // reminders are switched off.
            await QuickTimer.requestAuthorization()
        }
        // onDismiss covers swipe-to-dismiss too, not just the Done button.
        .sheet(item: $editing, onDismiss: save) { selection in
            editSheet(for: selection.id)
        }
    }

    private func editSheet(for index: Int) -> some View {
        NavigationStack {
            CountdownDurationPicker(duration: Binding(
                get: { slots.indices.contains(index) ? slots[index] : TimerSettingsStore.minimumSeconds },
                set: { if slots.indices.contains(index) { slots[index] = $0 } }
            ))
            .padding()
            .navigationTitle("Slot \(index + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { editing = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var footerText: String {
        let base = "These 5 presets show as buttons on the Quick Timer widget. It's standalone — not connected to your events, meals, or habits."
        return QuickTimer.usesRealAlarm
            ? base + "\n\nTimers ring as a real alarm — they'll sound even on Silent."
            : base + "\n\nThis device is below iOS 26, so timers ring as a normal notification and stay silent on Silent Mode."
    }

    private func save() {
        TimerSettingsStore.setSlotsSeconds(slots)
        // Read back so the rows show the clamped values the store actually kept.
        slots = TimerSettingsStore.slotsSeconds()
        WidgetCenter.shared.reloadTimelines(ofKind: "QuickTimer")
    }
}
