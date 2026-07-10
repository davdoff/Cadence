import SwiftUI

struct EventRowView: View {
    @Environment(\.theme) private var theme
    let event: Event
    var onEdit: (() -> Void)? = nil
    /// Dense single-line variant used by Schedule's month mode to fit more
    /// events on screen. Callers that omit it get the standard card row.
    var compact: Bool = false

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "\(f.string(from: event.startTime)) – \(f.string(from: event.endTime))"
    }

    private var startTimeShort: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: event.startTime)
    }

    var body: some View {
        if compact { compactBody } else { standardBody }
    }

    private var compactBody: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(categoryColor)
                .frame(width: 3, height: 26)

            Text(startTimeShort)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 66, alignment: .leading)

            Text(event.title)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            statusBadge
                .font(.caption)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .cardStyle()
    }

    private var standardBody: some View {
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
                        .background(theme.deep)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            statusBadge
        }
        .padding(14)
        .cardStyle()
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
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .missed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
        case .displaced:
            Image(systemName: "arrow.uturn.right.circle.fill")
                .foregroundColor(.orange)
        case .pending:
            EmptyView()
        }
    }
}
