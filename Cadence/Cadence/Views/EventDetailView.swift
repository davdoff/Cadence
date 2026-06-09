import SwiftUI
import SwiftData

struct EventDetailView: View {
    let event: Event
    @Environment(\.modelContext) private var context
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"
    @Query private var habits: [Habit]

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
            Color.cadenceCream.ignoresSafeArea()
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
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)

                // Status card
                HStack {
                    Text("Status")
                        .foregroundColor(.secondary)
                    Spacer()
                    statusBadge
                }
                .font(.subheadline)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)

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
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
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
        .toolbarBackground(Color.cadenceCream, for: .navigationBar)
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
    }

    // MARK: - Helpers

    private var categoryColor: Color {
        if let hex = event.category?.colorHex {
            return Color(hex: hex)
        }
        return .cadenceOrangeLight
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
        case .pending:
            Label("Upcoming", systemImage: "clock.fill")
                .foregroundColor(Color(hex: accentColorHex))
                .fontWeight(.semibold)
        }
    }
}
