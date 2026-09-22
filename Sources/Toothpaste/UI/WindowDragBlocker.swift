import AppKit
import SwiftUI

/// Stops window dragging for whatever it backs.
///
/// AppKit decides whether a background drag may start by asking the view under the
/// pointer for `mouseDownCanMoveWindow`, and this answers no.
///
/// That is only half the story now. On macOS 27 SwiftUI consumes the mouse-down before
/// AppKit can start a background drag at all, so the header is dragged explicitly by
/// `WindowDragHandle` instead. This still earns its place on earlier systems, where
/// background dragging does work and brushing past a row would otherwise shift the
/// panel. Both can be true at once, and the two are deliberately symmetric: this one
/// says where dragging must not start, the handle says where it must.
struct WindowDragBlocker: NSViewRepresentable {
    final class BlockingView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }

    func makeNSView(context: Context) -> NSView { BlockingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
