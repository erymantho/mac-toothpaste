import AppKit
import SwiftUI

/// Acts on a click even when it is the one that activates the window.
///
/// `acceptsFirstMouse` on the hosting view is not enough on its own. SwiftUI's tap
/// gesture ignores it, which produced a window where a `WindowDragHandle` moved the
/// panel on the first click while a row right below it still needed two — same window,
/// same setting, different event path. Measured; see PLAN.md, 2026-09-22.
///
/// This is the normal path here rather than a corner case: arming an item means clicking
/// into another window, so the panel is open and inactive for most of its life, and
/// every return trip was spending a click on nothing.
///
/// Like the drag handle it has to be an `overlay` — as a background it would only see
/// clicks where SwiftUI draws nothing at all. Anything that must stay clickable goes
/// above it in z-order.
struct ClickCatcher: NSViewRepresentable {
    var onClick: () -> Void

    final class CatcherView: NSView {
        var onClick: () -> Void = {}

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Never take focus. The panel itself is first responder, and that is what makes
        /// type-to-search work.
        override var acceptsFirstResponder: Bool { false }

        /// Accepted rather than ignored, so the matching mouse-up arrives here instead of
        /// going up the responder chain.
        override func mouseDown(with event: NSEvent) {}

        /// On release, and only inside the view — so sliding off a row before letting go
        /// cancels the click, the way a button behaves.
        override func mouseUp(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return }
            onClick()
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.onClick = onClick
        return view
    }

    /// Rows are reused as the list changes, so the closure has to be refreshed or a row
    /// would go on arming whichever entry it was first built for.
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.onClick = onClick
    }
}
