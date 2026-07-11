import SwiftUI

/// App-side presentation for `ThemeMode` (declared in the shared model layer,
/// SupportingTypes.swift). `.system` follows the device color scheme;
/// `.light`/`.dark` force a surface set regardless.
extension ThemeMode {
    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }
}

/// The *non-accent* half of the design tokens (CADENCE_DESIGN_SYSTEM §3): the
/// surfaces, text, and chrome that flip with light/dark mode. The accent half
/// (pills, ring, category/habit gradients) is layered on top by `Theme` from
/// the user's chosen accent hex — so the two axes stay independent.
struct Surface {
    let isDark: Bool

    // Text
    let text: Color
    let text2: Color
    // Cards
    let cardRing: Color
    let cardShadow: Color
    // Chips
    let chipBg: Color
    let chipText: Color
    let tabChip: Color
    // Tab bar wash (180°)
    let tabbarStops: [Color]
    // Hairlines / progress tracks
    let divider: Color
    let track: Color
    // Dark-only page-background stops (light builds its wash from the accent)
    let darkBgStops: [Color]

    /// 1b — Vibrant & Saturated (Light).
    static let light = Surface(
        isDark: false,
        text:  Color(hex: "#0f231a"),
        text2: Color(hex: "#5c7a6c"),
        cardRing:   Color.white.opacity(0.9),
        cardShadow: Color(hex: "#14965f").opacity(0.42),
        chipBg:   Color.white.opacity(0.78),
        chipText: Color(hex: "#4f7061"),
        tabChip:  Color.white.opacity(0.62),
        tabbarStops: [Color(hex: "#ecfbf3").opacity(0.74),
                      Color(hex: "#e0f6eb").opacity(0.94)],
        divider: Color(hex: "#0f5a37").opacity(0.11),
        track:   Color(hex: "#0f784b").opacity(0.14),
        darkBgStops: []
    )

    /// 1c — Dark Mode.
    static let dark = Surface(
        isDark: true,
        text:  Color(hex: "#eaf5ef"),
        text2: Color(hex: "#8ba39a"),
        cardRing:   Color.white.opacity(0.09),
        cardShadow: Color.black.opacity(0.7),
        chipBg:   Color.white.opacity(0.07),
        chipText: Color(hex: "#a7bcb2"),
        tabChip:  Color.white.opacity(0.06),
        tabbarStops: [Color(hex: "#101a16").opacity(0.6),
                      Color(hex: "#0c1411").opacity(0.92)],
        divider: Color.white.opacity(0.1),
        track:   Color.white.opacity(0.11),
        darkBgStops: [Color(hex: "#0c1613"), Color(hex: "#0d1524"), Color(hex: "#150f28")]
    )
}

/// One definition point for the app palette (UI_REVIEW §3.1). Two axes:
/// `accentHex` (user's picker, drives accent gradients) and `surface`
/// (light/dark mode, drives chrome). ContentView injects it via
/// `.environment(\.theme, …)`; views read `@Environment(\.theme)`.
struct Theme {
    let accentHex: String
    var surface: Surface = .light

    var isDark: Bool { surface.isDark }

    // MARK: - Accent-derived (existing API, unchanged names)

    var accent: Color { .appAccent(accentHex) }
    var deep: Color   { .appDeep(accentHex) }
    var light: Color  { .accentLight(accentHex) }
    var dark: Color   { .accentDark(accentHex) }

    // MARK: - Surface-derived

    var text: Color  { surface.text }
    var text2: Color { surface.text2 }
    /// Legacy name kept for callers still using `theme.background`.
    var background: Color { isDark ? Color(hex: "#0d1524") : .appBackground(accentHex) }
    /// Card surface base — the single hook views read for solid card fills.
    var cardSurface: Color { isDark ? Color.white.opacity(0.06) : .white }
    var divider: Color { surface.divider }
    var track: Color   { surface.track }
    var cardRing: Color { surface.cardRing }
    var cardShadow: Color { surface.cardShadow }
    var chipBg: Color  { surface.chipBg }
    var chipText: Color { surface.chipText }

    // MARK: - Gradients

    /// Legacy multi-stop accent gradient (topLeading→bottomTrailing).
    var accentGradient: LinearGradient {
        LinearGradient(colors: [light, accent, dark],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// §3 pill — 135° accent gradient for filled controls (buttons, active
    /// pills/chips, selected segments/cells).
    var pillGradient: LinearGradient {
        LinearGradient(colors: [light, dark],
                       startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    /// Soft colored glow cast under filled pills/FABs.
    var pillGlow: Color { accent.opacity(isDark ? 0.55 : 0.6) }

    /// Full-screen page wash (§3 app-bg). Dark uses the fixed 1c stops; light
    /// harmonizes with the chosen accent (so any accent works, not just green)
    /// and cools toward a light-blue corner like the spec's third stop.
    var backgroundGradient: LinearGradient {
        if isDark {
            return LinearGradient(colors: surface.darkBgStops,
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [.appBackground(accentHex),
                                       .appBackground(accentHex),
                                       Color(hex: "#dfeaff")],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Horizontal fill for accent progress bars (§3 progress-bar fill).
    var barGradient: LinearGradient {
        LinearGradient(colors: [light, accent],
                       startPoint: .leading, endPoint: .trailing)
    }

    /// Card surface wash (§3 card-bg). Light: white→faint accent tint.
    /// Dark: glassy white translucency.
    var cardGradient: LinearGradient {
        if isDark {
            return LinearGradient(colors: [Color.white.opacity(0.07),
                                           Color.white.opacity(0.025)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [.white, .appBackground(accentHex)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// §3 ring — conic accent sweep for the habits progress ring. Draw via
    /// `Circle().trim(from:to:)` stroked with this, rotated so it starts at top.
    var ringGradient: AngularGradient {
        AngularGradient(gradient: Gradient(colors: [light, accent, dark, light]),
                        center: .center,
                        startAngle: .degrees(-90), endAngle: .degrees(270))
    }

    /// §3 empty-orb — radial glow behind empty-state icons.
    var emptyOrb: RadialGradient {
        RadialGradient(colors: isDark
                        ? [accent.opacity(0.22), accent.opacity(0.05)]
                        : [light.opacity(0.9), background],
                       center: .center, startRadius: 2, endRadius: 70)
    }

    /// §3 tab bar — translucent gradient laid under `.ultraThinMaterial`.
    var tabbarGradient: LinearGradient {
        LinearGradient(colors: surface.tabbarStops,
                       startPoint: .top, endPoint: .bottom)
    }

    /// §3 category bar/dot — 180° gradient derived from any category's stored
    /// hex (generalizes the fixed Health/Work/Personal/Study examples, since
    /// categories are user-editable).
    func categoryGradient(hex: String) -> LinearGradient {
        LinearGradient(colors: [.accentLight(hex), Color(hex: hex)],
                       startPoint: .top, endPoint: .bottom)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(accentHex: "#E8784D", surface: .light)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Card style

/// Shared card chrome (UI_REVIEW §3.5 / DESIGN §2): gradient surface, corner
/// radius, soft colored shadow, and a 1px translucent ring — one place instead
/// of hand-rolled variants in every view.
private struct CardStyleModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let prominent: Bool

    private var radius: CGFloat { prominent ? 24 : 18 }

    func body(content: Content) -> some View {
        content
            .background(theme.cardGradient)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(theme.cardRing, lineWidth: 1)
            )
            .shadow(color: theme.cardShadow.opacity(prominent ? 1 : 0.6),
                    radius: prominent ? 16 : 9, x: 0, y: prominent ? 8 : 4)
    }
}

extension View {
    /// Standard card surface; pass `prominent: true` for hero cards
    /// (larger radius and shadow).
    func cardStyle(prominent: Bool = false) -> some View {
        modifier(CardStyleModifier(prominent: prominent))
    }

    /// Makes a text field focus when tapped *anywhere* in its frame, not just
    /// on the text glyphs. A bare `TextField`'s hit region is only the text
    /// itself, so taps in the surrounding padding miss and the keyboard never
    /// appears — this forwards the whole frame to first responder. Apply as the
    /// outermost modifier (after any `.padding()`/`.cardStyle()`) so the entire
    /// card is the tap target.
    func tapToFocus() -> some View {
        modifier(TapToFocusModifier())
    }
}

/// Backs `View.tapToFocus()`. Owns its own `@FocusState`, so each field it's
/// applied to gets an independent focus binding with no plumbing at the call
/// site. `contentShape(Rectangle())` makes the padded area hit-testable and the
/// tap gesture drives first responder programmatically.
private struct TapToFocusModifier: ViewModifier {
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
    }
}

// MARK: - Tab bar chrome (§4)

#if canImport(UIKit)
import UIKit

extension Theme {
    /// Applies the design tab-bar chrome to the global `UITabBar` appearance:
    /// the translucent `tabbar-bg` wash laid over the system blur, a 1px top
    /// divider, and accent-tinted selection. Call on appear and whenever the
    /// accent or surface changes. (SwiftUI's `TabView` exposes no per-item
    /// background, so the active-icon "pill chip" would need a fully custom bar
    /// — intentionally left out to keep navigation stock.)
    func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        // Pin the blur + tint to the app's own surface. Otherwise the default
        // material resolves against the *device* system scheme (not the app's
        // chosen theme), so a Light theme on a Dark-mode phone — or vice-versa —
        // inverts the bar against the rest of the surface.
        appearance.backgroundEffect = UIBlurEffect(
            style: isDark ? .systemThinMaterialDark : .systemThinMaterialLight)
        appearance.backgroundColor = UIColor(surface.tabbarStops.last ?? background)
        appearance.shadowColor = UIColor(divider)            // 1px top hairline

        let normal = UIColor(text2)
        let selected = UIColor(accent)
        for item in [appearance.stackedLayoutAppearance,
                     appearance.inlineLayoutAppearance,
                     appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = [.foregroundColor: normal]
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = [.foregroundColor: selected]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
#endif
