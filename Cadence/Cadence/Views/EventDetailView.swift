import SwiftUI
import SwiftData

struct EventDetailView: View {
    let event: Event
    @Environment(\.modelContext) private var context
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @Query private var habits: [Habit]

    @State private var showingEdit = false
    @State private var notesExpanded = false
    @State private var notesTruncated = false

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: event.startTime)
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "\(f.string(from: event.startTime)) – \(f.string(from: event.endTime))"
    }

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()
            // Scrolls because imported notes can run long once expanded.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Title card
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(categoryColor)
                            .frame(width: 5)
                            .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                                .font(.title2.weight(.bold))
                            Text(dateString)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(timeRange)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(16)
                    .cardStyle()

                    if let location = event.location {
                        locationRow(location)
                    }

                    // Status card
                    HStack {
                        Text("Status")
                            .foregroundColor(.secondary)
                        Spacer()
                        statusBadge
                    }
                    .font(.subheadline)
                    .padding(16)
                    .cardStyle()

                    if let cat = event.category {
                        HStack {
                            Text("Category")
                                .foregroundColor(.secondary)
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: cat.colorHex))
                                    .frame(width: 8, height: 8)
                                Text(cat.name)
                                    .fontWeight(.medium)
                            }
                        }
                        .font(.subheadline)
                        .padding(16)
                        .cardStyle()
                    }

                    if let repeats = recurrenceDescription {
                        HStack {
                            Text("Repeats")
                                .foregroundColor(.secondary)
                            Spacer()
                            Label(repeats, systemImage: "repeat")
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .padding(16)
                        .cardStyle()
                    }

                    if let notes = event.notes {
                        notesSection(notes)
                    }

                    if event.status == .pending {
                        markActions
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingEdit = true } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(theme.accent)
                }
                .accessibilityLabel("Edit event")
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddEventView(editingEvent: event)
        }
    }

    // MARK: - Location & notes (CADENCE_README §1.1b)
    //
    // Display-only here. Imported events' location/notes come from the source
    // calendar and are refreshed on every re-sync, so they have no edit
    // affordance anywhere; other events' notes are edited via the pencil
    // (AddEventView).

    /// Room / building / address as the source wrote it. Tap opens Apple Maps;
    /// long-press selects the text (e.g. to copy a room number).
    private func locationRow(_ location: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundColor(theme.accent)
            Text(location)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .font(.subheadline)
        .padding(16)
        .cardStyle()
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = Self.mapsURL(for: location) { openURL(url) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Location: \(location)")
        .accessibilityHint("Opens in Maps")
        .accessibilityAddTraits(.isButton)
    }

    /// The event's notes: 6 lines, then "Show more". URLs (Canvas, Zoom, …)
    /// are tappable.
    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(Self.linkified(notes))
                .font(.subheadline)
                .lineLimit(notesExpanded ? nil : 6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(truncationProbe(notes))
            if notesTruncated {
                Button(notesExpanded ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.2)) { notesExpanded.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(theme.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .cardStyle()
    }

    /// Sits behind the 6-line text at its clamped size: when the full text
    /// doesn't fit that height, ViewThatFits falls through to the second
    /// branch, which flags the notes as truncated (so "Show more" appears
    /// only when there is more to show).
    private func truncationProbe(_ notes: String) -> some View {
        ViewThatFits(in: .vertical) {
            Text(notes)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
            Color.clear
                .onAppear { notesTruncated = true }
        }
    }

    // MARK: - Mark actions

    private var markActions: some View {
        HStack(spacing: 12) {
            Button {
                mark(.completed)
            } label: {
                Label("Mark Complete", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button {
                mark(.missed)
            } label: {
                Label("Missed", systemImage: "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Logic

    private func mark(_ status: EventStatus) {
        let svc = NotificationService()
        event.status = status
        svc.cancelEventNotifications(for: event)
        if status == .completed, let cat = event.category?.name {
            for habit in habits where habit.correlatedCategoryName?.lowercased() == cat.lowercased() {
                habit.increment()
            }
        } else if status == .missed {
            svc.scheduleReschedulingNudge(for: event, after: 2)
        }
        try? context.save()
        WidgetSync.refresh()
    }

    // MARK: - Helpers

    /// Nil for one-off events; the rule text for native series; a generic
    /// label for imported series (the source calendar owns their rule).
    private var recurrenceDescription: String? {
        guard event.isRecurring else { return nil }
        if let series = RecurrenceService.shared.series(for: event, context: context) {
            return series.rule.displayText
        }
        return "From imported calendar"
    }

    /// Apple Maps search for the location text, as-is (no geocoding). Every
    /// character outside RFC 3986's unreserved set is percent-encoded, so
    /// "&", "+", "#" or "," in an address can't break the query.
    static func mapsURL(for location: String) -> URL? {
        let unreserved = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let query = location.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        return URL(string: "https://maps.apple.com/?q=\(query)")
    }

    /// Notes text with detected URLs turned into tappable links.
    static func linkified(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return attributed }
        let fullRange = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: fullRange) {
            guard let url = match.url,
                  let stringRange = Range(match.range, in: text),
                  let range = Range(stringRange, in: attributed)
            else { continue }
            attributed[range].link = url
        }
        return attributed
    }

    private var categoryColor: Color {
        if let hex = event.category?.colorHex {
            return Color(hex: hex)
        }
        return theme.light
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch event.status {
        case .completed:
            Label("Completed", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .fontWeight(.semibold)
        case .missed:
            Label("Missed", systemImage: "exclamationmark.circle.fill")
                .foregroundColor(.red)
                .fontWeight(.semibold)
        case .displaced:
            Label("Needs rescheduling", systemImage: "arrow.uturn.right.circle.fill")
                .foregroundColor(.orange)
                .fontWeight(.semibold)
        case .pending:
            Label("Upcoming", systemImage: "clock.fill")
                .foregroundColor(theme.accent)
                .fontWeight(.semibold)
        }
    }
}
