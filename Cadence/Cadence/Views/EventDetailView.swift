import SwiftUI

struct EventDetailView: View {
    let event: Event
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"

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

                Spacer()
            }
            .padding(16)
        }
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.cadenceCream, for: .navigationBar)
    }

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
