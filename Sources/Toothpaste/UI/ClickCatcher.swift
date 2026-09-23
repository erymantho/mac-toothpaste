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

    /// Non-nil only when `Settings.dragToType` is on. Dragging an entry out of the panel
    /// then means "click here and type it", which is the one thing in this app that posts
    /// a mouse event rather than a key event — hence the switch, and hence off by default.
    var onDrop: ((NSPoint) -> Void)?

    /// What the card beside the pointer shows while the entry is carried: the row's own
    /// text, already masked if the row is. Only asked for once a drag has really started.
    /// See `DragPreview`.
    var dragCard: (() -> (text: String, pinned: Bool))?

    /// Tells the row it is being carried, so it can fade the way a Finder item does.
    var onDragChanged: ((Bool) -> Void)?

    final class CatcherView: NSView {
        var onClick: () -> Void = {}
        var onDrop: ((NSPoint) -> Void)?
        var dragCard: (() -> (text: String, pinned: Bool))?
        var onDragChanged: ((Bool) -> Void)?

        private var pressOrigin: NSPoint?
        private var dragging = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Never take focus. The panel itself is first responder, and that is what makes
        /// type-to-search work.
        override var acceptsFirstResponder: Bool { false }

        /// Accepted rather than ignored, so the matching drag and mouse-up arrive here
        /// instead of going up the responder chain.
        override func mouseDown(with event: NSEvent) {
            pressOrigin = event.locationInWindow
            dragging = false
        }

        /// Once the button is down the window keeps the mouse until it is released, so
        /// these keep arriving even while the pointer is over another application. That
        /// is what makes dropping onto something else possible at all.
        override func mouseDragged(with event: NSEvent) {
            if dragging {
                DragPreview.shared.move(to: NSEvent.mouseLocation)
                return
            }
            guard onDrop != nil, let origin = pressOrigin else { return }
            let dx = event.locationInWindow.x - origin.x
            let dy = event.locationInWindow.y - origin.y
            // A few points of slack, so a heavy-handed click is still a click.
            guard dx * dx + dy * dy > 16 else { return }
            dragging = true
            // The crosshair stays: it is where the click will land, and the card beside it
            // is only there to say what will be typed.
            NSCursor.crosshair.push()
            if let card = dragCard?() {
                DragPreview.shared.show(card.text, pinned: card.pinned, at: NSEvent.mouseLocation)
            }
            onDragChanged?(true)
        }

        override func mouseUp(with event: NSEvent) {
            defer { pressOrigin = nil; dragging = false }

            if dragging {
                // Off screen before anything happens at the drop point.
                endDrag()
                // Released back over the panel: that is someone changing their mind, not
                // a destination. Nothing is clicked and nothing is typed.
                let location = NSEvent.mouseLocation
                guard window?.frame.contains(location) != true else { return }
                onDrop?(location)
                return
            }

            // Only inside the view, so sliding off a row before letting go cancels the
            // click the way a button behaves.
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return }
            onClick()
        }

        /// A row can leave the list mid-drag — the entry removed, the history trimmed by a
        /// new copy — and then no mouse-up ever reaches it. Without this the card would stay
        /// on screen and the cursor stuck as a crosshair.
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil, dragging {
                endDrag()
                dragging = false
                pressOrigin = nil
            }
            super.viewWillMove(toWindow: newWindow)
        }

        private func endDrag() {
            DragPreview.shared.hide()
            NSCursor.pop()
            onDragChanged?(false)
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.onClick = onClick
        view.onDrop = onDrop
        view.dragCard = dragCard
        view.onDragChanged = onDragChanged
        return view
    }

    /// Rows are reused as the list changes, so the closure has to be refreshed or a row
    /// would go on arming whichever entry it was first built for.
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? CatcherView else { return }
        view.onClick = onClick
        view.onDrop = onDrop
        view.dragCard = dragCard
        view.onDragChanged = onDragChanged
    }
}
