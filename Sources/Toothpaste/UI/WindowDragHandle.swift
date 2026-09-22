import AppKit
import SwiftUI

/// Makes whatever it covers drag the window.
///
/// The panel used to rely on `isMovableByWindowBackground` alone, which asks the view
/// under the pointer for `mouseDownCanMoveWindow` and starts the drag itself. On
/// macOS 27 that stopped working for anything inside an `NSHostingView`: the flag still
/// reads true, but SwiftUI consumes the mouse-down before AppKit can begin a drag, so
/// the panel became impossible to move. Measured against a plain `NSView` panel on the
/// same machine, which drags fine — see PLAN.md, 2026-09-22.
///
/// So the drag is started explicitly instead, with `performDrag(with:)`.
///
/// **It has to be an `overlay`, not a `background`.** As a background it only receives
/// clicks where SwiftUI draws nothing at all — over a `Text` SwiftUI claims the click
/// and the handle never sees it, which in practice left a draggable strip of about
/// fifteen points. As an overlay the handle wins everywhere it covers. Anything that
/// must stay clickable goes *above* it in z-order, which works: a `Button` and a `Menu`
/// stacked over the handle both still respond.
struct WindowDragHandle: NSViewRepresentable {
    final class HandleView: NSView {
        /// The panel is non-activating, so the first click into it is also the one that
        /// has to start the drag.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Never take focus. The panel itself is the first responder — that is what
        /// makes type-to-search work — and quietly stealing it here would break
        /// searching in a way that looks unrelated to dragging.
        override var acceptsFirstResponder: Bool { false }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView { HandleView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
