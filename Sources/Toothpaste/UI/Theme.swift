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
    static let ok = dynamic { isDark in
        isDark ? .systemGreen : NSColor(srgbRed: 0.11, green: 0.50, blue: 0.18, alpha: 1)
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
