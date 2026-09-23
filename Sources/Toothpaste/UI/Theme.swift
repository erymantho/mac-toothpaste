import AppKit
import SwiftUI

/// The colours the app names itself, in both system appearances.
///
/// The panel paints its own background instead of using the window's, but its text uses
/// the semantic colours — `.primary`, `.secondary`, `.tertiary` — which follow the
/// system appearance either way. Fixed near-black greys therefore only worked by
/// accident: in Light Mode the text turned near-black too and the panel arrived as an
/// unreadable black box. See PLAN.md, 2026-09-17.
///
/// The dark values are the originals. The light ones invert the direction of each step
/// while keeping its order — a row is a plate set apart from the surface, a pinned row
/// is set further apart — because a raised surface reads as lighter than its background
/// in dark and darker than it in light. That inversion is why one set of greys cannot
/// serve both, and it is how AppKit's own control colours behave.
enum Theme {

    /// The panel body.
    static let surface = grey(dark: 0.07, light: 0.98)

    /// History rows. A pinned row also carries an accent stripe, so its fill only has to
    /// be tellable apart, not loud.
    static let row = grey(dark: 0.11, light: 0.93)
    static let rowPinned = grey(dark: 0.155, light: 0.87)

    /// The search query display.
    static let field = grey(dark: 0.12, light: 0.92)

    /// Hairlines tint from the opposite end in each appearance: a white border is
    /// invisible on a light panel and a black one on a dark panel.
    static let border = hairline(dark: 0.12, light: 0.15)
    static let separator = hairline(dark: 0.06, light: 0.09)

    /// Status text. The system's orange and green reach roughly 2:1 against a light
    /// background, which is below readable, so light mode gets the same hues taken down
    /// until they carry. Both are used for things the user has to be able to read —
    /// a missing permission, characters that cannot be typed.
    static let warning = dynamic { isDark in
        isDark ? .systemOrange : NSColor(srgbRed: 0.72, green: 0.38, blue: 0.02, alpha: 1)
    }
    ///
    /// The light green was taken down once more when it became a heading: at 0.50 it read
    /// 4.28:1 on the 0.925 window background that macOS 14 and 15 use, under the 4.5:1 that
    /// text of that size needs. At 0.45 it is 5.1:1 there and 6.0:1 on white.
    static let ok = dynamic { isDark in
        isDark ? .systemGreen : NSColor(srgbRed: 0.09, green: 0.45, blue: 0.16, alpha: 1)
    }

    /// The heading for new features in release notes.
    ///
    /// Not the system accent colour, which is whatever the user picked. Measured in light
    /// mode: a yellow accent reaches 1.56:1 against the background and a green one 2.43:1 —
    /// and green is also the hue `ok` gives bug fixes, so under a green accent the one
    /// distinction these headings exist for disappears. A blue of its own reads at roughly
    /// 6:1 in both appearances whatever has been chosen.
    static let newFeature = dynamic { isDark in
        isDark ? NSColor(srgbRed: 0.45, green: 0.66, blue: 1.0, alpha: 1)
               : NSColor(srgbRed: 0.12, green: 0.35, blue: 0.80, alpha: 1)
    }

    private static func grey(dark: CGFloat, light: CGFloat) -> Color {
        dynamic { isDark in
            let value = isDark ? dark : light
            return NSColor(srgbRed: value, green: value, blue: value, alpha: 1)
        }
    }

    /// The arguments are alphas: white over a dark surface, black over a light one.
    private static func hairline(dark: CGFloat, light: CGFloat) -> Color {
        dynamic { isDark in
            isDark
                ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: dark)
                : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: light)
        }
    }

    /// One dynamic `NSColor` bridged into SwiftUI. Resolving through AppKit rather than
    /// reading `\.colorScheme` keeps this out of the views: nothing has to thread an
    /// environment value down to a row to know which grey it is.
    private static func dynamic(_ resolve: @escaping (Bool) -> NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            resolve(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        })
    }
}

/// Which appearance the app renders in, whatever the system is set to.
///
/// Worth being a preference rather than always following the system. The panel is a
/// dark HUD by design and someone on a light desktop may well want to keep it that way,
/// or the reverse; both are reasonable and neither is guessable from the machine's
/// setting. Automatic stays the default, because that is the answer that is right
/// without being asked.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Automatic"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` is how AppKit spells "inherit". On the application object there is nothing
    /// left to inherit from but the system, which is exactly what `.system` means.
    private var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Set on the application rather than on each window: the panel, the settings window
    /// and onboarding then cannot drift apart, windows opened later inherit it without
    /// being told, and open windows redraw immediately.
    @MainActor
    func apply() {
        NSApp.appearance = nsAppearance
    }
}
