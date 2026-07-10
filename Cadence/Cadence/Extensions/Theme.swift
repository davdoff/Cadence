import SwiftUI

/// One definition point for the accent-derived palette (UI_REVIEW §3.1).
/// ContentView injects it via `.environment(\.theme, …)`; views read
/// `@Environment(\.theme)` instead of re-deriving colors from
/// `@AppStorage("accentColorHex")` at every call site.
struct Theme {
    let accentHex: String

    var accent: Color     { .appAccent(accentHex) }
    var background: Color { .appBackground(accentHex) }
    var deep: Color       { .appDeep(accentHex) }
    var light: Color      { .accentLight(accentHex) }
    var dark: Color       { .accentDark(accentHex) }
    /// Card surface — the single hook for future dark-mode support.
    var cardSurface: Color { .white }

    /// The one gradient every filled control uses (FABs, confirm buttons,
    /// selected pills).
    var accentGradient: LinearGradient {
        LinearGradient(colors: [light, accent, dark],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Subtle top-to-bottom wash for page backgrounds.
    var backgroundGradient: LinearGradient {
        LinearGradient(colors: [background, deep.opacity(0.6)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// Horizontal fill for accent-colored progress bars.
    var barGradient: LinearGradient {
        LinearGradient(colors: [light, accent],
                       startPoint: .leading, endPoint: .trailing)
    }

    /// Barely-tinted wash for card surfaces — strong gradients would fight
    /// the colored content inside cards.
    var cardGradient: LinearGradient {
        LinearGradient(colors: [cardSurface, background],
                       startPoint: .top, endPoint: .bottom)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(accentHex: "#E8784D")
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Card style

/// Shared card chrome (UI_REVIEW §3.5): one place for surface, corner
/// radius, and shadow instead of hand-rolled variants in every view.
private struct CardStyleModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let prominent: Bool

    func body(content: Content) -> some View {
        content
            .background(theme.cardGradient)
            .clipShape(RoundedRectangle(cornerRadius: prominent ? 20 : 14))
            .shadow(color: .black.opacity(prominent ? 0.05 : 0.04),
                    radius: prominent ? 8 : 4, y: 2)
    }
}

extension View {
    /// Standard card surface; pass `prominent: true` for hero cards
    /// (larger radius and shadow).
    func cardStyle(prominent: Bool = false) -> some View {
        modifier(CardStyleModifier(prominent: prominent))
    }
}
