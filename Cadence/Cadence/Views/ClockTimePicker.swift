import SwiftUI

/// Radial time picker for a start/end pair: one 12-hour clock face, two hands
/// (start = accent, end = muted), and the duration drawn as an arc between
/// them. The full 24 h takes **two spins** of a hand (lap 0 = AM, lap 1 = PM),
/// with an explicit AM/PM pill because the face alone can't disambiguate laps.
///
/// Dragging snaps to 15-minute detents with haptic ticks; exact minutes — and
/// VoiceOver / motor-accessibility users — use the classic wheel pickers, kept
/// one tap away (the "123" toggle, or tapping the big readout).
///
/// Presentation-only: binds two `Date`s and edits their time-of-day in place,
/// preserving the day component. All angle↔time math lives in `DialGeometry`.
struct ClockTimePicker: View {
    @Environment(\.theme) private var theme

    @Binding var start: Date
    @Binding var end: Date
    /// The dial keeps `end` at least this many minutes after `start`, so the
    /// caller's end-after-start invariant can't break from a drag. (Wheel
    /// edits are deliberately unconstrained — same as the old pickers — and
    /// stay covered by the caller's validation.)
    var minimumDuration = 15

    private enum Hand { case start, end }
    private enum InputMode { case dial, wheel }

    @State private var activeHand: Hand = .start
    @State private var inputMode: InputMode = .dial
    /// Accumulated rotation (0°–720°) of the hand being dragged; nil = idle.
    @State private var accumulatedAngle: Double?
    @State private var lastFingerAngle = 0.0
    /// One-time "you can spin this" nudge on first ever appearance.
    @AppStorage("clockDialHintShown") private var hintShown = false
    @State private var hintNudge = 0.0

    var body: some View {
        VStack(spacing: 14) {
            header
            if inputMode == .dial {
                dial
                    .frame(height: 250)
                amPmPill
                handChips
            } else {
                DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                    .tint(theme.accent)
                DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                    .tint(theme.accent)
            }
        }
        .sensoryFeedback(.selection, trigger: startMinutes)
        .sensoryFeedback(.selection, trigger: endMinutes)
        .task { await runHintNudge() }
    }

    // MARK: - Header (readout + mode toggle)

    private var header: some View {
        HStack {
            if inputMode == .dial {
                // Tapping the readout is the fine-edit path: it opens the
                // wheels for exact minutes (the dial only does 15-min steps).
                Button {
                    withAnimation(.snappy) { inputMode = .wheel }
                } label: {
                    Text(timeText(forMinutes: activeMinutes))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.text)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: activeMinutes)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(activeHand == .start ? "Start" : "End") time \(timeText(forMinutes: activeMinutes)). Edit exact minutes")
            } else {
                Text("Set exact time")
                    .font(.headline)
                    .foregroundStyle(theme.text)
            }
            Spacer()
            Button {
                withAnimation(.snappy) {
                    inputMode = (inputMode == .dial) ? .wheel : .dial
                }
            } label: {
                Image(systemName: inputMode == .dial ? "123.rectangle" : "clock")
                    .font(.title3)
                    .foregroundStyle(theme.accent)
                    .frame(width: 44, height: 44)
                    .background(theme.chipBg, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(inputMode == .dial ? "Switch to wheel pickers" : "Switch to clock dial")
        }
    }

    // MARK: - Dial

    private var dial: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = size / 2

            ZStack {
                face(radius: radius)
                durationArc
                    .padding(6)
                lapGlyph(radius: radius)
                handView(minutes: endMinutes,
                         length: radius * 0.58,
                         color: theme.text2,
                         width: 4,
                         isActive: activeHand == .end)
                handView(minutes: startMinutes,
                         length: radius * 0.72,
                         color: theme.accent,
                         width: 5,
                         isActive: activeHand == .start)
                Circle()
                    .fill(theme.accent)
                    .frame(width: 11, height: 11)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(dialGesture(center: center))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement()
        .accessibilityLabel(activeHand == .start ? "Start time dial" : "End time dial")
        .accessibilityValue(timeText(forMinutes: activeMinutes))
        .accessibilityHint("Adjusts in 15 minute steps. For exact minutes use the wheel pickers button.")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? DialGeometry.snapStep : -DialGeometry.snapStep
            setActive(DialGeometry.snapped(activeMinutes + step))
        }
    }

    /// The four cardinal numerals and their unit offsets from center.
    private static let numerals: [(value: Int, dx: CGFloat, dy: CGFloat)] = [
        (12, 0, -1), (3, 1, 0), (6, 0, 1), (9, -1, 0)
    ]

    private func face(radius: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(theme.cardGradient)
            Circle()
                .stroke(theme.cardRing, lineWidth: 1)
            // 15-min detent grid: 48 ticks, hour ticks emphasized.
            ForEach(0..<48, id: \.self) { i in
                let isHour = i % 4 == 0
                Rectangle()
                    .fill(isHour ? theme.text2 : theme.track)
                    .frame(width: isHour ? 2 : 1, height: isHour ? 9 : 5)
                    .offset(y: -(radius - (isHour ? 12 : 10)))
                    .rotationEffect(.degrees(Double(i) * 7.5))
            }
            ForEach(Self.numerals, id: \.value) { numeral in
                Text("\(numeral.value)")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.text2)
                    .offset(x: numeral.dx * (radius - 28), y: numeral.dy * (radius - 28))
            }
        }
    }

    /// Accent arc swept clockwise from the start hand to the end hand — this
    /// is what makes the duration *visible*. A duration of 12 h+ fills the
    /// whole ring.
    private var durationArc: some View {
        let sweep = max(0, min(Double(endMinutes - startMinutes) * 0.5, 360))
        return Circle()
            .trim(from: 0, to: sweep / 360)
            .stroke(theme.accent.opacity(0.35),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round))
            // trim(0…) starts at 3 o'clock; rotate so it starts at the hand.
            .rotationEffect(.degrees(DialGeometry.faceAngle(forMinutes: startMinutes) - 90))
            .animation(.snappy, value: startMinutes)
            .animation(.snappy, value: endMinutes)
    }

    /// Faint sun/moon showing which lap the active hand is on, mid-drag.
    private func lapGlyph(radius: CGFloat) -> some View {
        Image(systemName: activeMinutes < 720 ? "sun.max.fill" : "moon.fill")
            .font(.footnote)
            .foregroundStyle(theme.text2.opacity(0.55))
            .offset(y: radius * 0.4)
            .animation(.snappy, value: activeMinutes < 720)
    }

    private func handView(minutes: Int, length: CGFloat, color: Color,
                          width: CGFloat, isActive: Bool) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .shadow(color: isActive ? color.opacity(0.45) : .clear, radius: 4)
            // Rotate by the *accumulated* angle (0°–720°), not the face angle:
            // visually identical (rotation is periodic) but animates smoothly
            // across the 12-o'clock wrap instead of spinning the long way back.
            .rotationEffect(.degrees(DialGeometry.totalAngle(fromMinutes: minutes)
                                     + (isActive ? hintNudge : 0)))
            .animation(.snappy, value: minutes)
            .opacity(isActive ? 1 : 0.75)
    }

    // MARK: - Drag (accumulated rotation + winding)

    private func dialGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let finger = DialGeometry.fingerAngle(of: value.location, around: center)
                guard let current = accumulatedAngle else {
                    // Drag start: grab whichever hand is nearer the touch,
                    // then seed the accumulated rotation from its time.
                    grabNearestHand(toFaceAngle: finger)
                    accumulatedAngle = DialGeometry.totalAngle(fromMinutes: activeMinutes)
                    lastFingerAngle = finger
                    return
                }
                let delta = DialGeometry.unwrappedDelta(from: lastFingerAngle, to: finger)
                lastFingerAngle = finger
                // Clamp to this hand's legal window so there's no "dead zone"
                // where the finger keeps winding past the limit.
                let angle = min(max(current + delta, minAngleForActiveHand), maxAngleForActiveHand)
                accumulatedAngle = angle
                setActive(DialGeometry.snapped(DialGeometry.minutes(fromTotalAngle: angle)))
            }
            .onEnded { _ in accumulatedAngle = nil }
    }

    private var minAngleForActiveHand: Double {
        activeHand == .end
            ? DialGeometry.totalAngle(fromMinutes: startMinutes + minimumDuration)
            : 0
    }

    private var maxAngleForActiveHand: Double {
        activeHand == .start
            ? DialGeometry.totalAngle(fromMinutes: DialGeometry.maxSnappedMinutes - minimumDuration)
            : DialGeometry.totalDegrees
    }

    private func grabNearestHand(toFaceAngle finger: Double) {
        let toStart = DialGeometry.faceDistance(finger, DialGeometry.faceAngle(forMinutes: startMinutes))
        let toEnd = DialGeometry.faceDistance(finger, DialGeometry.faceAngle(forMinutes: endMinutes))
        withAnimation(.snappy) { activeHand = toStart <= toEnd ? .start : .end }
    }

    // MARK: - AM/PM pill (lap indicator *and* shortcut: flips ±12 h)

    private var amPmPill: some View {
        Picker("AM or PM", selection: amPmBinding) {
            Text("AM").tag(false)
            Text("PM").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: 130)
    }

    private var amPmBinding: Binding<Bool> {
        Binding(
            get: { activeMinutes >= 720 },
            set: { pm in
                let m = activeMinutes
                if pm, m < 720 { setActive(m + 720) }
                if !pm, m >= 720 { setActive(m - 720) }
            }
        )
    }

    // MARK: - Start/End chips (hand selector) + duration

    private var handChips: some View {
        HStack {
            handChip(.start, label: "Start", minutes: startMinutes)
            Spacer()
            Text(durationText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.text2)
            Spacer()
            handChip(.end, label: "End", minutes: endMinutes)
        }
    }

    private func handChip(_ hand: Hand, label: String, minutes: Int) -> some View {
        let isActive = activeHand == hand
        return Button {
            withAnimation(.snappy) { activeHand = hand }
        } label: {
            VStack(spacing: 1) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isActive ? Color.white.opacity(0.85) : theme.chipText)
                Text(timeText(forMinutes: minutes))
                    .font(.callout.weight(.bold))
                    .foregroundStyle(isActive ? .white : theme.text)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: minutes)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background {
                if isActive {
                    Capsule().fill(theme.pillGradient)
                        .shadow(color: theme.pillGlow, radius: 6, y: 2)
                } else {
                    Capsule().fill(theme.chipBg)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) time, \(timeText(forMinutes: minutes))")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    // MARK: - Time plumbing

    private var startMinutes: Int { Self.minutesOfDay(start) }
    private var endMinutes: Int { Self.minutesOfDay(end) }
    private var activeMinutes: Int { activeHand == .start ? startMinutes : endMinutes }

    private func setActive(_ minutes: Int) {
        activeHand == .start ? setStart(minutes) : setEnd(minutes)
    }

    /// Moving start drags end along when needed, preserving `minimumDuration`.
    private func setStart(_ minutes: Int) {
        let m = min(max(minutes, 0), DialGeometry.maxSnappedMinutes - minimumDuration)
        start = Self.setting(minutes: m, on: start)
        if endMinutes < m + minimumDuration {
            end = Self.setting(minutes: m + minimumDuration, on: end)
        }
    }

    private func setEnd(_ minutes: Int) {
        let m = min(max(minutes, startMinutes + minimumDuration), DialGeometry.maxSnappedMinutes)
        end = Self.setting(minutes: m, on: end)
    }

    private static func minutesOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Rewrites only the time-of-day, keeping the date's day component.
    private static func setting(minutes: Int, on date: Date) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                              second: 0, of: date) ?? date
    }

    private func timeText(forMinutes minutes: Int) -> String {
        let date = Self.setting(minutes: minutes, on: start)
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var durationText: String {
        let d = endMinutes - startMinutes
        guard d > 0 else { return "—" }
        let h = d / 60, m = d % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: - First-run hint

    /// Nothing about a static dial says "spin me" — nudge the active hand
    /// once, ever, so the affordance is discoverable.
    private func runHintNudge() async {
        guard !hintShown else { return }
        hintShown = true
        try? await Task.sleep(for: .seconds(0.6))
        withAnimation(.spring(duration: 0.4)) { hintNudge = 9 }
        try? await Task.sleep(for: .seconds(0.45))
        withAnimation(.spring(duration: 0.6, bounce: 0.4)) { hintNudge = 0 }
    }
}

#Preview {
    @Previewable @State var start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
    @Previewable @State var end = Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: .now)!
    Form {
        Section("Time") {
            ClockTimePicker(start: $start, end: $end)
        }
    }
}
