import SwiftUI

/// Brief ring-burst + checkmark pop played when a habit's daily goal is reached.
struct GoalBurstOverlay: View {
    let color: Color
    let isActive: Bool

    @State private var scale: CGFloat = 0.4
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.7), lineWidth: 3)
                .scaleEffect(scale)
                .opacity(opacity * 0.8)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(color)
                .scaleEffect(min(scale, 1.1))
                .opacity(opacity)
        }
        .frame(width: 46, height: 46)
        .allowsHitTesting(false)
        .onChange(of: isActive) { _, active in
            guard active else { return }
            scale = 0.4
            opacity = 1
            withAnimation(.spring(duration: 0.45)) { scale = 1.8 }
            withAnimation(.easeOut(duration: 0.75).delay(0.15)) { opacity = 0 }
        }
    }
}
