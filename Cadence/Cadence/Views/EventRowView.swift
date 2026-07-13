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
                .fill(categoryBarGradient)
                .frame(width: 3, height: 26)

            Text(startTimeShort)
                .font(.cadCaption)
                .foregroundColor(.secondary)
                .frame(width: 66, alignment: .leading)

            Text(event.title)
                .font(.cadSubheadline)
                .foregroundColor(.primary)
                .lineLimit(1)

            if event.isRecurring {
                Image(systemName: "repeat")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

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
            // 6px vertical bar in the event's category gradient, with a matching
            // glow (§4 Schedule event cards).
            RoundedRectangle(cornerRadius: 3)
                .fill(categoryBarGradient)
                .frame(width: 6)
                .padding(.vertical, 4)
                .shadow(color: categoryGlow, radius: 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.cadBodyStrong)
                    .foregroundColor(.primary)
                HStack(spacing: 5) {
                    Text(timeRange)
                    if event.isRecurring {
                        Image(systemName: "repeat")
                            .font(.caption2)
                    }
                }
                .font(.cadCaption)
                .foregroundColor(.secondary)
            }

            Spacer()

            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(theme.chipBg)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            statusBadge
        }
        .padding(14)
        .cardStyle()
    }

    /// The event's category gradient (falls back to the accent pill gradient
    /// for uncategorised events).
    private var categoryBarGradient: LinearGradient {
        if let hex = event.category?.colorHex {
            return theme.categoryGradient(hex: hex)
        }
        return theme.pillGradient
    }

    private var categoryGlow: Color {
        if let hex = event.category?.colorHex {
            return Color(hex: hex).opacity(0.5)
        }
        return theme.pillGlow
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
