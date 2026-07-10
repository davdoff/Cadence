import SwiftUI
import SwiftData

struct EventDetailView: View {
    let event: Event
    @Environment(\.modelContext) private var context
    @Environment(\.theme) private var theme
    @Query private var habits: [Habit]

    @State private var showingEdit = false

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

                if event.status == .pending {
                    markActions
                }

                Spacer()
            }
            .padding(16)
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
