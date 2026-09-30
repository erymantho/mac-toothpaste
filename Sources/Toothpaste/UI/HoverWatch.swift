import AppKit

/// Ends a hover that AppKit did not end.
///
/// A tracking area promises `mouseEntered` and `mouseExited` in pairs, and a quick pass
/// over a small area can come without the exit: the hover then sticks, and a row button
/// stayed lit with the pointer long gone, until a slow pass over it produced the missing
/// pair. The state handling around it was measured and is not the cause — an enter and an
/// exit delivered in the same turn of the run loop clear it correctly — so the gap is in
/// what arrives, and this does not rely on it.
///
/// While a view is hovered, it looks at where the pointer really is ten times a second,
/// and ends the hover once the pointer has left the part of the view that can be seen.
/// Nothing runs while nothing is hovered.
@MainActor
final class HoverWatch {
    private var timer: Timer?

    func start(_ view: NSView, onLeave: @escaping () -> Void) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self, weak view] timer in
            MainActor.assumeIsolated {
                // The run loop keeps a repeating timer alive after its owner is gone, so it
                // has to end itself when there is no one left to stop it.
                guard let self else {
                    timer.invalidate()
                    return
                }
                // A view gone from its window has certainly been left.
                guard let view, let window = view.window else {
                    self.stop()
                    onLeave()
                    return
                }
                let pointer = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if !view.visibleRect.contains(pointer) {
                    self.stop()
                    onLeave()
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
