import SwiftUI

/// Root of the Overview tab. Hosts a top segmented control switching between the
/// Deep Planner (primary) and the Overview stats dashboard. Each half keeps its
/// own scrolling content; this container owns the background, the segmented
/// control, and the navigation title so the two halves stay chrome-free.
struct OverviewTabView: View {
    @Environment(\.theme) private var theme

    enum Segment: String, CaseIterable, Identifiable {
        case planner = "Planner", stats = "Stats"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .planner

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                Picker("View", selection: $segment) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                switch segment {
                case .planner: DeepPlannerView()
                case .stats:   OverviewView()
                }
            }
        }
        .navigationTitle(segment == .planner ? "Planner" : "Overview")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(theme.background, for: .navigationBar)
    }
}
