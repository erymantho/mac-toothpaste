import AppKit
import SwiftUI

/// Stops window dragging for whatever it backs.
///
/// AppKit decides whether a background drag may start by asking the view under the
/// pointer for `mouseDownCanMoveWindow`. So rather than making the header draggable —
/// a background `NSView` never sees those clicks, because SwiftUI does not draw its
/// text as separate views — the window stays draggable everywhere and this blocks it
/// under everything except the header.
struct WindowDragBlocker: NSViewRepresentable {
    final class BlockingView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }

    func makeNSView(context: Context) -> NSView { BlockingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
