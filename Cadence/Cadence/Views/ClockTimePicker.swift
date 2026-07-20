import SwiftUI

/// Radial time picker for a start/end pair: one 12-hour clock face, two hands
/// (start = accent, end = muted), and the duration drawn as an arc between
/// them. The face is a **single revolution**, and an explicit AM/PM pill
/// chooses morning vs afternoon for the active hand, because the face alone
/// can't disambiguate them. Dragging start past 12 o'clock wraps within its
/// current half (only the pill changes it); dragging end past 12 o'clock
/// *does* carry it into the next half — end trails start, so letting it wind
/// naturally past noon (or past midnight) is how a duration is meant to cross
/// into PM/the next half without a separate toggle.
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
    /// Continuous face angle of the hand being dragged; nil = idle. While a
    /// drag is live this single angle drives *all* rendering — both hands and
    /// the duration arc — so they glide 1:1 with the finger; the 15-minute
    /// snapping applies only to the value layer (readout, chips, haptics).
    @State private var accumulatedAngle: Double?
    @State private var lastFingerAngle = 0.0
    /// Gap (end − start, minutes) captured when the start hand is grabbed, so
    /// dragging start slides end along without shrinking the duration.
    @State private var dragGap: Int?
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
                handView(angle: endDisplayMinutes * 0.5,
                         length: radius * 0.58,
                         color: theme.text2,
                         width: 4,
                         isActive: activeHand == .end)
                handView(angle: startDisplayMinutes * 0.5,
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
            withAnimation(.snappy) {
                setActive(DialGeometry.snapped(activeMinutes + step))
            }
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

    // MARK: - Display minutes (continuous while dragging, snapped at rest)
    //
    // The value layer snaps to 15-min detents, but rendering from snapped
    // values makes hands jump in 7.5° steps mid-drag. So hands and arc render
    // from these instead: while a drag is live they follow the continuous
    // finger angle — the non-dragged end hand drawn rigidly `dragGap` ahead of
    // start — and at rest they settle to the snapped values (a jump of at most
    // half a detent, unanimated, so it can never spin the wrong way round the
    // 12 o'clock seam).

    private var startDisplayMinutes: Double {
        if let a = accumulatedAngle, activeHand == .start {
            return Double(DialGeometry.halfBase(startMinutes)) + DialGeometry.normalizedAngle(a) * 2
        }
        return Double(startMinutes)
    }

    private var endDisplayMinutes: Double {
        if let a = accumulatedAngle {
            if activeHand == .start {
                return startDisplayMinutes + Double(dragGap ?? (endMinutes - startMinutes))
            }
            return Double(DialGeometry.halfBase(endMinutes)) + DialGeometry.normalizedAngle(a) * 2
        }
        return Double(endMinutes)
    }

    /// Accent arc swept clockwise from the start hand to the end hand — this
    /// is what makes the duration *visible*. A duration of 12 h+ fills the
    /// whole ring.
    private var durationArc: some View {
        let sweep = max(0, min((endDisplayMinutes - startDisplayMinutes) * 0.5, 360))
        return Circle()
            .trim(from: 0, to: sweep / 360)
            .stroke(theme.accent.opacity(0.35),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round))
            // trim(0…) starts at 3 o'clock; rotate so it starts at the hand.
            .rotationEffect(.degrees(startDisplayMinutes * 0.5 - 90))
    }

    /// Faint sun/moon showing which lap the active hand is on, mid-drag.
    private func lapGlyph(radius: CGFloat) -> some View {
        Image(systemName: activeMinutes < 720 ? "sun.max.fill" : "moon.fill")
            .font(.footnote)
            .foregroundStyle(theme.text2.opacity(0.55))
            .offset(y: radius * 0.4)
            .animation(.snappy, value: activeMinutes < 720)
    }

    /// No implicit animation on the rotation: mid-drag the angle already
    /// tracks the finger 1:1 (a spring would only lag behind it), and paths
    /// that *should* animate — the accessibility ±15 min action, the hint
    /// nudge — wrap their state change in an explicit `withAnimation`.
    private func handView(angle: Double, length: CGFloat, color: Color,
                          width: CGFloat, isActive: Bool) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .shadow(color: isActive ? color.opacity(0.45) : .clear, radius: 4)
            .rotationEffect(.degrees(angle + (isActive ? hintNudge : 0)))
            .opacity(isActive ? 1 : 0.75)
    }

    // MARK: - Drag (continuous face angle; start wraps within its half, end can cross into the next)

    private func dialGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let finger = DialGeometry.fingerAngle(of: value.location, around: center)
                guard let current = accumulatedAngle else {
                    // Drag start: grab whichever hand is nearer the touch, seed
                    // the drag angle from its face position, and (if start was
                    // grabbed) remember the gap so end slides along with it.
                    grabNearestHand(toFaceAngle: finger)
                    accumulatedAngle = DialGeometry.continuousAngle(forMinutes: activeMinutes)
                    dragGap = activeHand == .start ? endMinutes - startMinutes : nil
                    lastFingerAngle = finger
                    return
                }
                // Keep the angle continuous (no window clamp) so the hand can
                // wind freely past a single revolution.
                let angle = current + DialGeometry.unwrappedDelta(from: lastFingerAngle, to: finger)
                lastFingerAngle = finger
                accumulatedAngle = angle
                let requested: Int
                if activeHand == .end {
                    // End is the one hand allowed to cross AM/PM by dragging
                    // past 12: snap the raw continuous angle directly so the
                    // half and the within-half position come from the same
                    // rounding step (see snappedContinuousMinutes — rounding
                    // them separately disagreed right at the 12 o'clock seam).
                    requested = DialGeometry.snappedContinuousMinutes(fromContinuousAngle: angle)
                } else {
                    // Start only ever wraps within its current half; only the
                    // AM/PM pill changes which half start is in.
                    let raw = DialGeometry.positionMinutes(fromFaceAngle: angle)
                    let position = DialGeometry.snapped(raw) % DialGeometry.halfDayMinutes
                    requested = DialGeometry.halfBase(activeMinutes) + position
                }
                let applied = setActive(requested)
                if applied != requested {
                    // A real wall fired (end pinned at start + minimum, or the
                    // day-end cap): re-anchor the drag angle so the rendered
                    // hand pins at the limit instead of running away with the
                    // finger, using `applied`'s own half so a later reversal
                    // doesn't lose track of a crossing already made.
                    accumulatedAngle = DialGeometry.continuousAngle(forMinutes: applied)
                }
            }
            .onEnded { _ in
                accumulatedAngle = nil
                dragGap = nil
            }
    }

    private func grabNearestHand(toFaceAngle finger: Double) {
        let toStart = DialGeometry.faceDistance(finger, DialGeometry.faceAngle(forMinutes: startMinutes))
        let toEnd = DialGeometry.faceDistance(finger, DialGeometry.faceAngle(forMinutes: endMinutes))
        withAnimation(.snappy) { activeHand = toStart <= toEnd ? .start : .end }
    }

    // MARK: - AM/PM pill (chooses the half: flips the active hand ±12 h)

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

    /// Applies the requested minutes to the active hand and returns what was
    /// actually applied — a caller comparing the two can tell a clamp fired.
    @discardableResult
    private func setActive(_ minutes: Int) -> Int {
        activeHand == .start ? setStart(minutes) : setEnd(minutes)
    }

    /// Moving start slides end along, preserving the current gap (the duration
    /// captured when the hand was grabbed, or at least `minimumDuration`). If
    /// end would run off the end of the day, start stops with it.
    @discardableResult
    private func setStart(_ minutes: Int) -> Int {
        let gap = max(dragGap ?? (endMinutes - startMinutes), minimumDuration)
        var m = min(max(minutes, 0), DialGeometry.maxSnappedMinutes)
        var e = m + gap
        if e > DialGeometry.maxSnappedMinutes {
            e = DialGeometry.maxSnappedMinutes
            m = e - gap
        }
        start = Self.setting(minutes: m, on: start)
        end = Self.setting(minutes: e, on: end)
        return m
    }

    @discardableResult
    private func setEnd(_ minutes: Int) -> Int {
        let m = min(max(minutes, startMinutes + minimumDuration), DialGeometry.maxSnappedMinutes)
        end = Self.setting(minutes: m, on: end)
        return m
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
