import SwiftUI

struct EventRowView: View {
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"
    let event: Event
    var onEdit: (() -> Void)? = nil

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "\(f.string(from: event.startTime)) – \(f.string(from: event.endTime))"
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(categoryColor)
                .frame(width: 4)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(timeRange)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.appDeep(accentColorHex))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            statusBadge
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private var categoryColor: Color {
        if let hex = event.category?.colorHex {
            return Color(hex: hex)
        }
        return .accentLight(accentColorHex)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch event.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .missed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
        case .pending:
            EmptyView()
        }
    }
}
