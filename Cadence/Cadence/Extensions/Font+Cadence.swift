import SwiftUI
import UIKit

/// Cadence typography (CADENCE_DESIGN_SYSTEM §1). Two families:
///
/// - **Bricolage Grotesque ExtraBold** — big headlines and numbers *only*
///   (the Today date header, hero stat numbers).
/// - **Manrope 500–800** — all other UI text.
///
/// Both are bundled by David via `UIAppFonts` in Info.plist. Neither is a
/// system font, so if a face isn't registered we fall back to the **rounded**
/// system design at a matching heavy weight — an explicit, on-brand placeholder
/// rather than a silent San-Francisco substitution (the spec's §1 instruction).
/// Swap is transparent: once the real files ship, `bundled` flips to `true` and
/// every call site upgrades with no further edits.
enum CadenceType {

    // MARK: PostScript names (confirm in Font Book after bundling)

    static let display = "BricolageGrotesque-ExtraBold"

    /// Manrope face for a given UI weight. Only the 500–800 range is bundled;
    /// anything lighter maps to Medium.
    static func ui(_ weight: Font.Weight) -> String {
        switch weight {
        case .semibold:      return "Manrope-SemiBold"   // 600
        case .bold:          return "Manrope-Bold"       // 700
        case .heavy, .black: return "Manrope-ExtraBold"  // 800
        default:             return "Manrope-Medium"     // 500
        }
    }

    /// Whether the bundled faces are actually registered. Resolved once at
    /// first access; drives the fallback branch below.
    static let bundled: Bool = UIFont(name: display, size: 12) != nil

    // MARK: Builders

    /// Bricolage ExtraBold at an explicit size (headlines & numbers). Scales
    /// with Dynamic Type via `relativeTo:` when bundled; the fallback keeps the
    /// exact size (predictable placeholder) at rounded-heavy.
    static func displayFont(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        bundled
            ? .custom(display, size: size, relativeTo: style)
            : .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Manrope at an explicit size/weight (UI text).
    static func uiFont(_ size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) -> Font {
        bundled
            ? .custom(ui(weight), size: size, relativeTo: style)
            : .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Semantic roles

/// Semantic font vocabulary — call sites use intent (`.cadHero`, `.cadBody`),
/// not raw sizes, so the whole app restyles from this one file. Sizes track the
/// system text styles they replace so existing layouts don't shift.
extension Font {

    // Bricolage ExtraBold — headlines & numbers only
    /// Hero headline, e.g. the Today date "Saturday, Jul 11". (~28pt)
    static var cadHero: Font { CadenceType.displayFont(28, relativeTo: .title) }
    /// Section / card headline in the display face. (~20pt)
    static var cadHeadline: Font { CadenceType.displayFont(20, relativeTo: .title3) }
    /// Big stat number at an arbitrary size (hero counters, ring center).
    static func cadNumber(_ size: CGFloat) -> Font {
        CadenceType.displayFont(size, relativeTo: .largeTitle)
    }

    // Manrope — all other UI text
    /// Standard body / row text. (~16pt, weight 500)
    static var cadBody: Font { CadenceType.uiFont(16, weight: .medium, relativeTo: .body) }
    /// Emphasised body / titled control. (~16pt, weight 600)
    static var cadBodyStrong: Font { CadenceType.uiFont(16, weight: .semibold, relativeTo: .body) }
    /// Secondary line under a title. (~15pt, weight 500)
    static var cadSubheadline: Font { CadenceType.uiFont(15, weight: .medium, relativeTo: .subheadline) }
    /// Small emphasised label / chip text. (~13pt, weight 600)
    static var cadFootnote: Font { CadenceType.uiFont(13, weight: .semibold, relativeTo: .footnote) }
    /// Caption / metadata. (~12pt, weight 500)
    static var cadCaption: Font { CadenceType.uiFont(12, weight: .medium, relativeTo: .caption) }

    /// One-off Manrope at an explicit size/weight when a semantic role doesn't fit.
    static func cadUI(_ size: CGFloat, weight: Font.Weight = .medium, relativeTo style: Font.TextStyle = .body) -> Font {
        CadenceType.uiFont(size, weight: weight, relativeTo: style)
    }
}
