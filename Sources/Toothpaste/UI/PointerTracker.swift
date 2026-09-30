import AppKit
import SwiftUI

/// Says when the pointer enters and leaves a view, whether or not the panel is active.
///
/// The same tracking area `ClickCatcher` uses for a row's hover, for the same reason: the
/// panel is inactive for most of its life, and an AppKit tracking area can be told to work
/// regardless. Unlike the catcher it never takes a click. It sits under a button, and the
/// button has to keep every one of them.
struct PointerTracker: NSViewRepresentable {
    var onChange: (Bool) -> Void

    final class TrackingView: NSView {
        var onChange: (Bool) -> Void = { _ in }
        /// Ends the hover if the exit never comes — see `HoverWatch`.
        private let watch = HoverWatch()

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) {
            onChange(true)
            watch.start(self) { [weak self] in self?.onChange(false) }
        }

        override func mouseExited(with event: NSEvent) {
            watch.stop()
            onChange(false)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { watch.stop() }
            super.viewWillMove(toWindow: newWindow)
        }

        /// Transparent to clicks, so they reach the button this sits under.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var acceptsFirstResponder: Bool { false }
    }

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    /// Rows are reused, so the closure is refreshed or a slot would light the button it
    /// was first built for.
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TrackingView)?.onChange = onChange
    }
}
