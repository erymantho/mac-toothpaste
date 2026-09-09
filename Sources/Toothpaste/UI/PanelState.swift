import Combine
import Foundation

/// What the panel shows while it is open.
///
/// The panel's content view is rebuilt on each show, so most of this could have been
/// passed in once. `armed` could not: arming happens *while* the panel is open and
/// has to change what is on screen immediately.
@MainActor
final class PanelState: ObservableObject {
    /// An item chosen but not yet delivered. While this is set the panel stays open
    /// and the next click in another window decides the destination.
    @Published var armed: ClipItem?

    @Published var accessibilityGranted = false

    /// One line of context under the title. It changes meaning as things happen —
    /// where you came from, what is being typed where, what was cancelled — so it is
    /// one string rather than fields that would each go stale on their own.
    @Published var statusLine = ""
}
